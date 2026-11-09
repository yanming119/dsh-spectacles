param(
  [string]$Window = "",
  [string]$Crop = "",
  [double]$Scale = 1.0,
  [switch]$Image,
  [switch]$Raise,
  [switch]$List,
  [string]$Out = "",
  [string]$SaveDir = ""
)
$DataDir = if ($env:DSH_LOOK_DATA) { $env:DSH_LOOK_DATA } else { Join-Path $env:TEMP 'dsh-look' }
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force -Path $DataDir | Out-Null }
if (-not $SaveDir) { $SaveDir = $DataDir }
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class W2 {
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll", SetLastError = true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);

  public struct RECT { public int Left, Top, Right, Bottom; }

  public class Win { public IntPtr H; public string Title; public uint Pid; public int L, T, R, B; }

  public static List<Win> List() {
    var res = new List<Win>();
    EnumWindows((h, p) => {
      if (!IsWindowVisible(h)) return true;
      var sb = new StringBuilder(512);
      GetWindowText(h, sb, 512);
      string t = sb.ToString();
      if (t.Length == 0) return true;
      RECT r; if (!GetWindowRect(h, out r)) return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      var w = new Win(); w.H = h; w.Title = t; w.Pid = pid;
      w.L = r.Left; w.T = r.Top; w.R = r.Right; w.B = r.Bottom;
      res.Add(w);
      return true;
    }, IntPtr.Zero);
    return res;
  }
}
"@

function Resolve-Window([string]$sel) {
  $all = [W2]::List()

  # picked：用人点过的那一个（look-pick.ps1 写 picked.json）
  if ($sel -eq 'picked') {
    $pf = Join-Path $DataDir 'picked.json'
    if (-not (Test-Path $pf)) { return $null }
    $pj = Get-Content $pf -Raw -Encoding UTF8 | ConvertFrom-Json
    $h = [IntPtr][long]$pj.hwnd
    return ($all | Where-Object { $_.H -eq $h } | Select-Object -First 1)
  }

  # @名字：查白名单 windows.json
  if ($sel.StartsWith('@')) {
    $name = $sel.Substring(1)
    $cf = Join-Path $DataDir 'windows.json'
    if (-not (Test-Path $cf)) { return $null }
    $cfg = Get-Content $cf -Raw -Encoding UTF8 | ConvertFrom-Json
    $entry = $cfg.windows | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $entry) { return $null }
    if ($entry.title) { return ($all | Where-Object { $_.Title -like "*$($entry.title)*" } | Select-Object -First 1) }
    return $null
  }

  if ($sel -match '^\d+$') {
    $h = [IntPtr][long]$sel
    return ($all | Where-Object { $_.H -eq $h } | Select-Object -First 1)
  }
  if ($sel -match '^pid:(\d+)$') {
    $p = [uint32]$Matches[1]
    return ($all | Where-Object { $_.Pid -eq $p } | Select-Object -First 1)
  }
  return ($all | Where-Object { $_.Title -like "*$sel*" } | Select-Object -First 1)
}

if ($List) {
  $all = [W2]::List() | Where-Object { ($_.R - $_.L) -gt 0 -and ($_.B - $_.T) -gt 0 }
  $rows = @()
  foreach ($w in $all) {
    $rows += [ordered]@{
      hwnd  = [int64]$w.H
      pid   = $w.Pid
      title = $w.Title
      rect  = [ordered]@{ x = $w.L; y = $w.T; w = ($w.R - $w.L); h = ($w.B - $w.T) }
    }
  }
  [ordered]@{ ok = $true; count = $rows.Count; windows = $rows } | ConvertTo-Json -Compress -Depth 6
  exit 0
}
if (-not $Window) { throw "need -Window (hwnd | title | pid:1234)" }

$w = Resolve-Window $Window
if (-not $w) { @{ ok = $false; error = "window not found: $Window" } | ConvertTo-Json -Compress; exit 1 }

$ww = $w.R - $w.L
$wh = $w.B - $w.T
if ($ww -le 0 -or $wh -le 0) { @{ ok = $false; error = "bad rect" } | ConvertTo-Json -Compress; exit 1 }

$full = [System.Drawing.Bitmap]::new([int]$ww, [int]$wh)
$g = [System.Drawing.Graphics]::FromImage($full)
$hdc = $g.GetHdc()
$ok = [W2]::PrintWindow($w.H, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()
$source = 'printwindow'
if (-not $ok) {
  if (-not $Raise) {
    @{ ok = $false; error = 'printwindow-failed' } | ConvertTo-Json -Compress
    exit 1
  }
  # 这个窗口不吃「重画」这条请求（GPU 直绘常见）。临时把它提到最上层，从屏幕抓它那一块，再立刻还原。
  # 不抢焦点（NOACTIVATE）、不移动、不改大小。
  $exBefore = [W2]::GetWindowLong($w.H, -20)
  $wasTop = (($exBefore -band 0x0008) -ne 0)
  $raised = [W2]::SetWindowPos($w.H, [IntPtr](-1), 0, 0, 0, 0, (0x0002 -bor 0x0001 -bor 0x0010))
  if (-not $raised) {
    # 置顶被拒（有些游戏/带反截屏保护的程序会拒绝 SetWindowPos）。这时屏幕那块是别的窗口，抓了就是错图，宁可报错。
    $werr = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    @{ ok = $false; error = 'raise-failed'; win32Error = $werr; hint = '这个窗口不让被提到最前，此时抓屏会抓到压在上面的窗口，所以没有出图' } | ConvertTo-Json -Compress
    exit 1
  }
  try {
    Start-Sleep -Milliseconds 90
    $g2 = [System.Drawing.Graphics]::FromImage($full)
    $sz = New-Object System.Drawing.Size ([int]$ww), ([int]$wh)
    $g2.CopyFromScreen([int]$w.L, [int]$w.T, 0, 0, $sz)
    $g2.Dispose()
    $source = 'screen-raised'
  } finally {
    if (-not $wasTop) {
      [W2]::SetWindowPos($w.H, [IntPtr](-2), 0, 0, 0, 0, (0x0002 -bor 0x0001 -bor 0x0010)) | Out-Null
    }
  }
}

# 可选区域裁剪（相对窗口左上角）
$rect = New-Object System.Drawing.Rectangle 0, 0, $ww, $wh
if ($Crop) {
  $c = $Crop -split ','
  $rect = New-Object System.Drawing.Rectangle ([int]$c[0]), ([int]$c[1]), ([int]$c[2]), ([int]$c[3])
  if ($rect.X -lt 0) { $rect.X = 0 }
  if ($rect.Y -lt 0) { $rect.Y = 0 }
  if ($rect.X + $rect.Width -gt $ww) { $rect.Width = $ww - $rect.X }
  if ($rect.Y + $rect.Height -gt $wh) { $rect.Height = $wh - $rect.Y }
}

$img = $full.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

# 统计：平均色 + 边缘密度 + 64x36 灰度网格（用于比对"有没有变"）
$bw = 64; $bh = 36
$small = [System.Drawing.Bitmap]::new([int]$bw, [int]$bh)
$gs = [System.Drawing.Graphics]::FromImage($small)
$gs.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gs.DrawImage($img, 0, 0, $bw, $bh)
$gs.Dispose()

$grid = New-Object 'int[]' ($bw * $bh)
$sumR = 0.0; $sumG = 0.0; $sumB = 0.0; $n = 0
for ($y = 0; $y -lt $bh; $y++) {
  for ($x = 0; $x -lt $bw; $x++) {
    $c = $small.GetPixel($x, $y)
    $gray = [int](0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B)
    $grid[$y * $bw + $x] = $gray
    $sumR += $c.R; $sumG += $c.G; $sumB += $c.B; $n++
  }
}

# 边缘密度：相邻像素差 > 24 的比例
$edge = 0; $tot = 0
for ($y = 0; $y -lt $bh; $y++) {
  for ($x = 1; $x -lt $bw; $x++) {
    $d = [Math]::Abs($grid[$y * $bw + $x] - $grid[$y * $bw + $x - 1])
    if ($d -gt 24) { $edge++ }
    $tot++
  }
}
$edgeDensity = [Math]::Round($edge / [Math]::Max(1, $tot), 4)

$key = "w$($w.Pid)_$($rect.X)_$($rect.Y)_$($rect.Width)x$($rect.Height)"
if (-not (Test-Path $SaveDir)) { New-Item -ItemType Directory -Path $SaveDir -Force | Out-Null }
$lastFile = Join-Path $SaveDir "last-$key.txt"
$sig = ($grid -join ',')
$changed = $null
if (Test-Path $lastFile) {
  $prev = Get-Content $lastFile -Raw
  if ($prev) { $changed = -not ($prev -eq $sig) }
}
Set-Content -Path $lastFile -Value $sig -NoNewline

$pngPath = $null
if ($Image) {
  if (-not $Out) { $Out = Join-Path $SaveDir ("win-" + (Get-Date -Format 'HHmmss') + ".png") }
  $dir = Split-Path $Out -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if ($Scale -gt 1) {
    $sx = [int]($img.Width * $Scale); $sy = [int]($img.Height * $Scale)
    $big = [System.Drawing.Bitmap]::new([int]$sx, [int]$sy)
    $gb = [System.Drawing.Graphics]::FromImage($big)
    $gb.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gb.DrawImage($img, 0, 0, $sx, $sy)
    $gb.Dispose()
    $big.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    $big.Dispose()
  } else {
    $img.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
  }
  $pngPath = $Out
}

$avg = "#{0:X2}{1:X2}{2:X2}" -f [int]($sumR / $n), [int]($sumG / $n), [int]($sumB / $n)

$res = [ordered]@{
  ok        = $true
  when      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
  source    = $source
  window    = [ordered]@{ hwnd = [int64]$w.H; title = $w.Title; pid = $w.Pid; rect = @($w.L, $w.T, $ww, $wh) }
  region    = @($rect.X, $rect.Y, $rect.Width, $rect.Height)
  avgColor  = $avg
  edgeDensity = $edgeDensity
  changed   = $changed
  grid      = "$bw x $bh"
}
if ($pngPath) { $res.png = $pngPath }

$img.Dispose(); $full.Dispose(); $small.Dispose()

$res | ConvertTo-Json -Compress

