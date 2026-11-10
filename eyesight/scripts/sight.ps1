param(
  [Parameter(Mandatory = $true)][ValidateSet('capture', 'crop', 'wide', 'hash', 'diff')][string]$Mode,
  [string]$Frame = '',
  [string]$Frame2 = '',
  [string]$Out = '',
  [string]$Crop = '',
  [int]$Width = 512,
  [double]$Scale = 1,
  [int]$Cols = 8,
  [int]$Rows = 6,
  [int]$Tol = 12
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# Ask for real pixels instead of DPI-scaled ones (Win10/11 per-monitor scaling).
try {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SightDpi {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
  [SightDpi]::SetProcessDPIAware() | Out-Null
} catch { }

function Emit($obj) { $obj | ConvertTo-Json -Compress }

# 像素级帮手：分块哈希与逐像素差都在 C# 里做，PowerShell 逐像素循环太慢（5.4M 像素会跑几分钟）。
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

public class SightPX {
  public static byte[] RegionBytes(Bitmap bmp, int x, int y, int w, int h) {
    Rectangle r = new Rectangle(x, y, w, h);
    BitmapData d = bmp.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    int len = Math.Abs(d.Stride) * h;
    byte[] buf = new byte[len];
    Marshal.Copy(d.Scan0, buf, 0, len);
    bmp.UnlockBits(d);
    return buf;
  }
  public static string HashOf(byte[] buf) {
    using (SHA256 sha = SHA256.Create()) {
      return BitConverter.ToString(sha.ComputeHash(buf)).Replace("-", "").Substring(0, 32).ToLowerInvariant();
    }
  }
  public static string RegionHash(Bitmap bmp, int x, int y, int w, int h) {
    return HashOf(RegionBytes(bmp, x, y, w, h));
  }
  public static string FileHash(string path) {
    using (SHA256 sha = SHA256.Create()) {
      using (System.IO.FileStream fs = System.IO.File.OpenRead(path)) {
        return BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "").ToLowerInvariant();
      }
    }
  }
  public static int DiffRegion(Bitmap a, Bitmap b, int x, int y, int w, int h, int tol) {
    Rectangle r = new Rectangle(x, y, w, h);
    BitmapData da = a.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    BitmapData db = b.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    int len = Math.Abs(da.Stride) * h;
    byte[] ba = new byte[len];
    byte[] bb = new byte[len];
    Marshal.Copy(da.Scan0, ba, 0, len);
    Marshal.Copy(db.Scan0, bb, 0, len);
    a.UnlockBits(da);
    b.UnlockBits(db);
    int changed = 0;
    int lenB = Math.Min(ba.Length, bb.Length);
    for (int i = 0; i + 2 < lenB; i += 3) {
      int d0 = ba[i] - bb[i]; if (d0 < 0) d0 = -d0;
      int d1 = ba[i + 1] - bb[i + 1]; if (d1 < 0) d1 = -d1;
      int d2 = ba[i + 2] - bb[i + 2]; if (d2 < 0) d2 = -d2;
      if (d0 > tol) changed++;
      else if (d1 > tol) changed++;
      else if (d2 > tol) changed++;
    }
    return changed;
  }
}
"@

function Block-Letter($i) { if ($i -lt 26) { return [char](65 + $i) } else { return "Z$i" } }

function Grid-Boxes($w, $h, $cols, $rows) {
  $cw = [int][Math]::Ceiling($w / [double]$cols)
  $ch = [int][Math]::Ceiling($h / [double]$rows)
  $list = @()
  for ($r = 0; $r -lt $rows; $r++) {
    for ($c = 0; $c -lt $cols; $c++) {
      $x = $c * $cw; $y = $r * $ch
      $bw = [Math]::Min($cw, $w - $x); $bh = [Math]::Min($ch, $h - $y)
      if ($bw -gt 0 -and $bh -gt 0) {
        $list += [pscustomobject]@{ id = ((Block-Letter $c) + ($r + 1)); x = $x; y = $y; w = $bw; h = $bh }
      }
    }
  }
  return , $list
}

if ($Mode -eq 'capture') {
  $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $vs.Width, $vs.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($vs.X, $vs.Y, 0, 0, $bmp.Size)
  $g.Dispose()
  $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
  $boxes = Grid-Boxes $bmp.Width $bmp.Height $Cols $Rows
  $blocks = @()
  foreach ($b in $boxes) {
    $blocks += [pscustomobject]@{ id = $b.id; x = $b.x; y = $b.y; w = $b.w; h = $b.h; hash = [SightPX]::RegionHash($bmp, $b.x, $b.y, $b.w, $b.h) }
  }
  $bmp.Dispose()
  Emit @{ ok = $true; w = $vs.Width; h = $vs.Height; x = $vs.X; y = $vs.Y; path = $Out;
          hash = [SightPX]::FileHash($Out); frameId = (Get-Date -Format 'yyyyMMdd-HHmmssfff');
          cols = $Cols; rows = $Rows; blocks = $blocks }
  exit 0
}

if ($Mode -eq 'hash') {
  $bmp = New-Object System.Drawing.Bitmap $Frame
  if ($Crop -ne '') {
    $p = $Crop -split ','
    $hx = [int]$p[0]; $hy = [int]$p[1]; $hw = [int]$p[2]; $hh = [int]$p[3]
    if ($hx + $hw -gt $bmp.Width) { $hw = $bmp.Width - $hx }
    if ($hy + $hh -gt $bmp.Height) { $hh = $bmp.Height - $hy }
    $one = [SightPX]::RegionHash($bmp, $hx, $hy, $hw, $hh)
    $W = $bmp.Width; $H = $bmp.Height
    $bmp.Dispose()
    Emit @{ ok = $true; x = $hx; y = $hy; w = $hw; h = $hh; hash = $one; frameW = $W; frameH = $H }
    exit 0
  }
  $boxes = Grid-Boxes $bmp.Width $bmp.Height $Cols $Rows
  $blocks = @()
  foreach ($b in $boxes) {
    $blocks += [pscustomobject]@{ id = $b.id; x = $b.x; y = $b.y; w = $b.w; h = $b.h; hash = [SightPX]::RegionHash($bmp, $b.x, $b.y, $b.w, $b.h) }
  }
  $W = $bmp.Width; $H = $bmp.Height
  $bmp.Dispose()
  Emit @{ ok = $true; w = $W; h = $H; hash = [SightPX]::FileHash($Frame); cols = $Cols; rows = $Rows; blocks = $blocks }
  exit 0
}

if ($Mode -eq 'diff') {
  $a = New-Object System.Drawing.Bitmap $Frame
  $b = New-Object System.Drawing.Bitmap $Frame2
  $boxes = Grid-Boxes ([Math]::Min($a.Width, $b.Width)) ([Math]::Min($a.Height, $b.Height)) $Cols $Rows
  $changed = @()
  foreach ($bx in $boxes) {
    $n = [SightPX]::DiffRegion($a, $b, $bx.x, $bx.y, $bx.w, $bx.h, $Tol)
    $ratio = [Math]::Round($n / [double]($bx.w * $bx.h), 4)
    if ($ratio -gt 0.0005) {
      $changed += [pscustomobject]@{ id = $bx.id; x = $bx.x; y = $bx.y; w = $bx.w; h = $bx.h; ratio = $ratio; px = $n }
    }
  }
  $same = [SightPX]::FileHash($Frame) -eq [SightPX]::FileHash($Frame2)
  $nA = $a.Width; $nB = $a.Height
  $a.Dispose(); $b.Dispose()
  Emit @{ ok = $true; identical = $same; total = $boxes.Count; changedCount = $changed.Count; changed = $changed;
          hashA = [SightPX]::FileHash($Frame); hashB = [SightPX]::FileHash($Frame2); w = $nA; h = $nB }
  exit 0
}

$src = [System.Drawing.Image]::FromFile($Frame)
$srcW = $src.Width
$srcH = $src.Height

if ($Mode -eq 'wide') {
  $w = [int][Math]::Min($Width, $src.Width)
  $h = [int][Math]::Round($src.Height * ($w / [double]$src.Width))
  $dst = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($dst)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($src, 0, 0, $w, $h)
  $g.Dispose()
  $dst.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
  $dst.Dispose()
  $src.Dispose()
  Emit @{ ok = $true; w = $w; h = $h; srcW = $srcW; srcH = $srcH; path = $Out }
  exit 0
}

$p = $Crop -split ','
if ($p.Count -ne 4) { throw 'Crop must be "x,y,w,h"' }
$x = [int]$p[0]; $y = [int]$p[1]; $cw = [int]$p[2]; $ch = [int]$p[3]
if ($x -lt 0) { $x = 0 }
if ($y -lt 0) { $y = 0 }
if ($x -ge $src.Width) { throw "x $x outside frame (width $($src.Width))" }
if ($y -ge $src.Height) { throw "y $y outside frame (height $($src.Height))" }
if ($x + $cw -gt $src.Width) { $cw = $src.Width - $x }
if ($y + $ch -gt $src.Height) { $ch = $src.Height - $y }

$rect = New-Object System.Drawing.Rectangle $x, $y, $cw, $ch
$piece = $src.Clone($rect, $src.PixelFormat)
$ow = [int][Math]::Round($cw * $Scale)
$oh = [int][Math]::Round($ch * $Scale)
$dst = New-Object System.Drawing.Bitmap $ow, $oh
$g = [System.Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($piece, 0, 0, $ow, $oh)
$g.Dispose()
$dst.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$dst.Dispose()
$piece.Dispose()
$src.Dispose()
Emit @{ ok = $true; x = $x; y = $y; w = $ow; h = $oh; cw = $cw; ch = $ch; path = $Out }
