param(
  [string]$Crop = '',
  [string]$File = '',
  [int]$S1 = 3,
  [int]$S2 = 4
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing

$tmpDir = if ($env:DSH_LOOK_DATA) { $env:DSH_LOOK_DATA } else { Join-Path $env:TEMP 'dsh-look' }
if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null }

$src = $File
if ($Crop -ne '') {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
  $src = Join-Path $tmpDir "read-$stamp.png"
  $look = Join-Path $PSScriptRoot 'look.ps1'
  $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $look, '-Crop', $Crop, '-Image', '-Out', $src)
  $out = & powershell.exe @args
  if (-not (Test-Path $src)) { '{"ok":false,"error":"capture failed"}'; exit 1 }
}
if (-not (Test-Path $src)) { '{"ok":false,"error":"no image"}'; exit 1 }

$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
  })[0]
function Await($op, $type) {
  $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
  $t.Wait()
  return $t.Result
}
[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if ($null -eq $engine) { '{"ok":false,"error":"no ocr engine"}'; exit 1 }

$base = [System.Drawing.Image]::FromFile($src)
$sw = [System.Diagnostics.Stopwatch]::StartNew()

function Ocr-Scaled($img, [int]$scale, [string]$tag) {
  $bw = $img.Width * $scale
  $bh = $img.Height * $scale
  $b = New-Object System.Drawing.Bitmap $bw, $bh
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($img, 0, 0, $bw, $bh)
  $g.Dispose()
  $png = Join-Path $tmpDir ("ocr-" + $tag + ".png")
  $b.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
  $b.Dispose()

  $f = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($png)) ([Windows.Storage.StorageFile])
  $st = Await ($f.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $dec = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($st)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $sb = Await ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $r = Await ($engine.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
  $st.Dispose()
  return @($r.Lines | ForEach-Object { $_.Text })
}

$h1 = @(Ocr-Scaled $base $S1 "a")
$h2 = @(Ocr-Scaled $base $S2 "b")
$base.Dispose()
$sw.Stop()

$A = @($h1 | Where-Object { $_.Trim() -ne '' })
$B = @($h2 | Where-Object { $_.Trim() -ne '' })

function Sim($x, $y) {
  if ($x -eq $y) { return 1.0 }
  $cx = @{}; foreach ($c in $x.ToCharArray()) { $cx[$c] = 1 + ($cx[$c] -as [int]) }
  $used = 0
  foreach ($c in $y.ToCharArray()) { if (($cx[$c] -as [int]) -gt 0) { $cx[$c] = $cx[$c] - 1; $used++ } }
  $max = [Math]::Max($x.Length, $y.Length)
  if ($max -eq 0) { return 1.0 }
  return [double]$used / $max
}

$items = New-Object System.Collections.ArrayList
$usedB = New-Object 'bool[]' $B.Count
foreach ($a in $A) {
  $best = -1; $bestS = 0.0
  for ($j = 0; $j -lt $B.Count; $j++) {
    if ($usedB[$j]) { continue }
    $s = Sim $a $B[$j]
    if ($s -gt $bestS) { $bestS = $s; $best = $j }
  }
  if ($best -ge 0 -and $bestS -ge 0.6) {
    $usedB[$best] = $true
    if ($B[$best] -eq $a) {
      [void]$items.Add(@{ text = $a; consistent = $true })
    } else {
      $x = $a; $y = $B[$best]
      if ($y.Length -gt $x.Length) { $x = $B[$best]; $y = $a }
      [void]$items.Add(@{ text = $x; alt = $y; consistent = $false })
    }
  } else {
    [void]$items.Add(@{ text = $a; alt = $null; consistent = $false; uncertain = $true })
  }
}

$chars = 0
foreach ($it in $items) { $chars += $it.text.Length }

$obj = [ordered]@{
  ok       = $true
  file     = $src
  scales   = @($S1, $S2)
  lines    = $items
  chars    = $chars
  disagree = @($items | Where-Object { -not $_.consistent }).Count
  ms       = $sw.ElapsedMilliseconds
}
$obj | ConvertTo-Json -Depth 6 -Compress

