param(
  [string]$Crop = "",
  [double]$Scale = 1.0,
  [switch]$Image,
  [string]$Out = "",
  [string]$SaveDir = "",
  [int]$TimeoutMs = 6000
)
$DataDir = if ($env:DSH_LOOK_DATA) { $env:DSH_LOOK_DATA } else { Join-Path $env:TEMP 'dsh-look' }
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force -Path $DataDir | Out-Null }
if (-not $SaveDir) { $SaveDir = $DataDir }

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# fullscreen capture defaults to GDI: fast (~200ms) and needs no external binary.
# set DSH_LOOK_FFMPEG only to force the ffmpeg/DXGI path (slower, but sees some hardware overlays).
$ffmpeg = $env:DSH_LOOK_FFMPEG
if ($ffmpeg -and -not (Test-Path $ffmpeg)) { $ffmpeg = '' }

if (-not (Test-Path $SaveDir)) { New-Item -ItemType Directory -Path $SaveDir -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$tmp = Join-Path $SaveDir "raw-$stamp.png"
$stateFile = Join-Path $SaveDir 'last-grid.txt'

$sw = [Diagnostics.Stopwatch]::StartNew()
$source = 'gdi-copyfromscreen'
if ($ffmpeg) {
  $source = 'dxgi-ddagrabb'
  & $ffmpeg -hide_banner -loglevel error -f lavfi -i "ddagrab=0:framerate=1" -vf "hwdownload,format=bgra" -frames:v 1 -y $tmp 2>$null | Out-Null
} else {
  # GDI screen copy (DPI-aware, no external binary)
  if (-not ('YM.Dpi' -as [type])) {
    Add-Type -Namespace YM -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);'
  }
  [void][YM.Dpi]::SetProcessDPIAware()
  $sw0 = [YM.Dpi]::GetSystemMetrics(0); $sh0 = [YM.Dpi]::GetSystemMetrics(1)
  $shot = New-Object System.Drawing.Bitmap $sw0, $sh0
  $g0 = [System.Drawing.Graphics]::FromImage($shot)
  $g0.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size $sw0, $sh0))
  $g0.Dispose()
  $shot.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
  $shot.Dispose()
}
$sw.Stop()
if (-not (Test-Path $tmp)) { Write-Output '{"ok":false,"error":"capture failed"}'; exit 1 }

$src = [System.Drawing.Bitmap]::FromFile($tmp)
$screenW = $src.Width
$screenH = $src.Height

$x = 0; $y = 0; $w = $screenW; $h = $screenH
if ($Crop) {
  $p = $Crop -split ','
  if ($p.Length -eq 4) {
    $x = [int]$p[0]; $y = [int]$p[1]; $w = [int]$p[2]; $h = [int]$p[3]
    if ($x -lt 0) { $x = 0 }
    if ($y -lt 0) { $y = 0 }
    if (($x + $w) -gt $screenW) { $w = $screenW - $x }
    if (($y + $h) -gt $screenH) { $h = $screenH - $y }
  }
}

function New-StatBitmap($bmp, $tw, $th) {
  $small = New-Object System.Drawing.Bitmap $tw, $th
  $g = [System.Drawing.Graphics]::FromImage($small)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
  $g.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0, 0, $tw, $th), (New-Object System.Drawing.Rectangle $x, $y, $w, $h), [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()
  return $small
}

$stat = New-StatBitmap $src 64 36
$gw = $stat.Width; $gh = $stat.Height
$gray = New-Object 'int[]' ($gw * $gh)
$sumR = 0; $sumG = 0; $sumB = 0
for ($yy = 0; $yy -lt $gh; $yy++) {
  for ($xx = 0; $xx -lt $gw; $xx++) {
    $c = $stat.GetPixel($xx, $yy)
    $sumR += $c.R; $sumG += $c.G; $sumB += $c.B
    $gray[$yy * $gw + $xx] = [int](($c.R * 0.299) + ($c.G * 0.587) + ($c.B * 0.114))
  }
}
$n = $gw * $gh
$avgR = [int]($sumR / $n); $avgG = [int]($sumG / $n); $avgB = [int]($sumB / $n)

$edges = 0
for ($yy = 1; $yy -lt $gh - 1; $yy++) {
  for ($xx = 1; $xx -lt $gw - 1; $xx++) {
    $i = $yy * $gw + $xx
    $dx = [Math]::Abs($gray[$i + 1] - $gray[$i - 1])
    $dy = [Math]::Abs($gray[$i + $gw] - $gray[$i - $gw])
    if (($dx + $dy) -gt 60) { $edges++ }
  }
}
$edgeDensity = [Math]::Round($edges / $n, 4)

$cur = ($gray | ForEach-Object { if ($_ -lt 10) { '00' } elseif ($_ -lt 100) { '0' + $_ } else { "$_" } }) -join ''
$changed = $null
if (Test-Path $stateFile) { $prev = Get-Content $stateFile -Raw; if ($prev.Trim() -eq $cur) { $changed = $false } else { $changed = $true } }
Set-Content -Path $stateFile -Value $cur -NoNewline

$stat.Dispose()

$pngPath = ''
if ($Image -or $Out) {
  $target = New-Object System.Drawing.Bitmap ([int]($w * $Scale)), ([int]($h * $Scale))
  $g2 = [System.Drawing.Graphics]::FromImage($target)
  $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g2.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $target.Width, $target.Height), (New-Object System.Drawing.Rectangle $x, $y, $w, $h), [System.Drawing.GraphicsUnit]::Pixel)
  $g2.Dispose()
  if ($Out) { $pngPath = $Out } else { $pngPath = Join-Path $SaveDir "look-$stamp.png" }
  $target.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $target.Dispose()
}

$src.Dispose()
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

$obj = [ordered]@{
  ok         = $true
  when       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
  source     = $source
  screen     = @{ w = $screenW; h = $screenH }
  region     = @{ x = $x; y = $y; w = $w; h = $h }
  captureMs  = $sw.ElapsedMilliseconds
  avgColor   = ('#{0:X2}{1:X2}{2:X2}' -f $avgR, $avgG, $avgB)
  edgeDensity = $edgeDensity
  changed    = $changed
  grid       = "$gw" + 'x' + "$gh"
  png        = $pngPath
}
$obj | ConvertTo-Json -Compress -Depth 4
