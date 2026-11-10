param(
  [Parameter(Mandatory = $true)][string]$Frame,
  [Parameter(Mandatory = $true)][string]$Crop,      # 相对整屏 x,y,w,h —— 刚好包住这一段文字
  [Parameter(Mandatory = $true)][string]$TextFile,  # UTF-8，这一段读到的文字
  [string]$Fonts = '',
  [string]$FontFiles = '',
  [string]$Sizes = '12,13,14,15,16,17,18,19,20',
  [double]$SpikeK = 2.0,     # 单字差 > 全行中位数 × K 算可疑
  [double]$SpikeMin = 0.06   # 且绝对差要超过这个
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Drawing;
using System.Drawing.Text;
using System.Collections.Generic;

public class Px {
  public static byte[] Gray(Bitmap b) {
    int w = b.Width, h = b.Height;
    byte[] g = new byte[w * h];
    for (int y = 0; y < h; y++)
      for (int x = 0; x < w; x++) {
        Color c = b.GetPixel(x, y);
        g[y * w + x] = (byte)((c.R * 299 + c.G * 587 + c.B * 114) / 1000);
      }
    return g;
  }

  public static byte[] RenderGray(string text, string font, int px, int w, int h, int ox, int oy) {
    Bitmap t = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format24bppRgb);
    Graphics g = Graphics.FromImage(t);
    g.Clear(Color.White);
    g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
    g.DrawString(text, new Font(font, px, FontStyle.Regular, GraphicsUnit.Pixel), Brushes.Black, ox, oy);
    g.Dispose();
    byte[] r = Gray(t);
    t.Dispose();
    return r;
  }

  // 在 +/-range 内找最佳平移，返回平均绝对差（0..1）
  public static double Scan(byte[] src, byte[] canvas, int sw, int sh, int cw, int ch, int pad,
                            int rx, int ry, out int bx, out int by) {
    bx = 0; by = 0;
    double best = double.MaxValue;
    for (int dx = -rx; dx <= rx; dx++) {
      if (pad + dx < 0 || pad + dx + sw > cw) continue;
      for (int dy = -ry; dy <= ry; dy++) {
        if (pad + dy < 0 || pad + dy + sh > ch) continue;
        long s = 0;
        for (int y = 0; y < sh; y++) {
          int srow = y * sw;
          int crow = (y + pad + dy) * cw + pad + dx;
          for (int x = 0; x < sw; x++) {
            int d = src[srow + x] - canvas[crow + x];
            if (d < 0) d = -d;
            s += d;
          }
        }
        double m = (double)s / (sw * sh) / 255.0;
        if (m < best) { best = m; bx = dx; by = dy; }
      }
    }
    return best;
  }

  // 每个字格的平均绝对差；edges 是每个字的起止 x（相对源图）
  public static double[] CharDiffs(byte[] src, byte[] canvas, int sw, int sh, int cw, int pad,
                                   int dx, int dy, int[] edges, int n) {
    double[] res = new double[n];
    for (int i = 0; i < n; i++) {
      int x0 = edges[i], x1 = edges[i + 1];
      int w = x1 - x0;
      if (w < 2) { res[i] = 0; continue; }
      long s = 0;
      for (int y = 0; y < sh; y++) {
        int srow = y * sw + x0;
        int crow = (y + pad + dy) * cw + pad + dx + x0;
        for (int x = 0; x < w; x++) {
          int d = src[srow + x] - canvas[crow + x];
          if (d < 0) d = -d;
          s += d;
        }
      }
      res[i] = (double)s / (w * sh) / 255.0;
    }
    return res;
  }

  public static int[] InkBox(byte[] g, int w, int h, int thr) {
    int minX = w, minY = h, maxX = -1, maxY = -1;
    for (int y = 0; y < h; y++)
      for (int x = 0; x < w; x++)
        if (g[y * w + x] < thr) {
          if (x < minX) minX = x; if (x > maxX) maxX = x;
          if (y < minY) minY = y; if (y > maxY) maxY = y;
        }
    if (maxX < 0) return new int[] { 0, 0, 0, 0 };
    return new int[] { minX, minY, maxX - minX + 1, maxY - minY + 1 };
  }

  public static double[] ColumnProfile(byte[] src, byte[] canvas, int sw, int sh, int cw, int pad, int dx, int dy) {
    double[] col = new double[sw];
    for (int x = 0; x < sw; x++) {
      long s = 0;
      for (int y = 0; y < sh; y++) {
        int d = src[y * sw + x] - canvas[(y + pad + dy) * cw + pad + dx + x];
        if (d < 0) d = -d;
        s += d;
      }
      col[x] = (double)s / sh / 255.0;
    }
    return col;
  }

  public static double Measure(string text, string font, int px) {    Bitmap t = new Bitmap(8, 8);
    Graphics g = Graphics.FromImage(t);
    SizeF sz = g.MeasureString(text, new Font(font, px, FontStyle.Regular, GraphicsUnit.Pixel), 10000, StringFormat.GenericTypographic);
    g.Dispose(); t.Dispose();
    return sz.Width;
  }

  public static List<double> Measures(string text, string font, int px) {
    List<double> ms = new List<double>();
    for (int i = 0; i <= text.Length; i++) ms.Add(Measure(text.Substring(0, i), font, px));
    return ms;
  }
}
"@

$p = $Crop -split ','
$cx = [int]$p[0]; $cy = [int]$p[1]; $cw = [int]$p[2]; $chh = [int]$p[3]
$src = New-Object System.Drawing.Bitmap $Frame
if ($cx + $cw -gt $src.Width) { $cw = $src.Width - $cx }
if ($cy + $chh -gt $src.Height) { $chh = $src.Height - $cy }
$rect = New-Object System.Drawing.Rectangle $cx, $cy, $cw, $chh
$bmp = $src.Clone($rect, $src.PixelFormat)
$src.Dispose()
$srcGray = [Px]::Gray($bmp)

$text = ([IO.File]::ReadAllText($TextFile, [Text.UTF8Encoding]::new($false))).TrimEnd("`r", "`n")
if ($text.Length -lt 1) {
  @{ ok = $true; verdict = 'no-text'; suspect = @() } | ConvertTo-Json -Compress
  $bmp.Dispose(); exit 0
}

$pad = 8
$Bw = $cw + $pad * 2; $Bh = $chh + $pad * 2
$sb = [Px]::InkBox($srcGray, $cw, $chh, 160)
if ($sb[2] -le 0) {
  @{ ok = $true; verdict = 'no-text'; suspect = @() } | ConvertTo-Json -Compress
  $bmp.Dispose(); exit 0
}

# 1) 字体/字号 + 对齐：全在 C# 里跑
$pfc = $null
# when a font file is given it IS the key: only compare against that family
if (($FontFiles -ne '') -and ($Fonts -eq '')) { $Fonts = '#' }
$cand = @($Fonts -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and $_ -ne '#' })
if ($FontFiles -ne '') {
  $pfc = New-Object System.Drawing.Text.PrivateFontCollection
  foreach ($ff in ($FontFiles -split ',')) {
    if (($ff.Trim() -ne '') -and (Test-Path $ff.Trim())) { $pfc.AddFontFile($ff.Trim()) }
  }
  foreach ($fam in $pfc.Families) { $cand += $fam.Name }
}
if ($cand.Count -eq 0) { $cand = @('Microsoft YaHei','Microsoft JhengHei','DengXian','SimSun','Segoe UI') }

$best = $null
foreach ($f in $cand) {
  foreach ($sz in (($Sizes -split ',') | ForEach-Object { [int]$_ })) {
    $canvas = [Px]::RenderGray($text, $f, $sz, $Bw, $Bh, $pad, $pad)
    $rb = [Px]::InkBox($canvas, $Bw, $Bh, 160)
    # 让渲染出来的墨迹落在源图墨迹上
    $bx0 = $rb[0] - $pad - $sb[0]
    $by0 = $rb[1] - $pad - $sb[1]
    $dx = 0; $dy = 0
    $m = [Px]::Scan($srcGray, $canvas, $cw, $chh, $Bw, $Bh, $pad, [Math]::Max(1, [Math]::Abs($bx0) + 3), [Math]::Max(1, [Math]::Abs($by0) + 3), [ref]$dx, [ref]$dy)
    if ($null -eq $best -or $m -lt $best.m) {
      $best = [pscustomobject]@{ font = $f; size = $sz; m = $m; dx = $dx; dy = $dy }
    }
  }
}

# 2) 定位：逐列算像素差，找「比全行都明显差」的列带（不猜字宽）
$canvas = [Px]::RenderGray($text, $best.font, $best.size, $Bw, $Bh, $pad, $pad)
$col = [Px]::ColumnProfile($srcGray, $canvas, $cw, $chh, $Bw, $pad, $best.dx, $best.dy)

# 3 列滑动平均，压掉单列噪声
$sm = New-Object 'double[]' $cw
for ($i = 0; $i -lt $cw; $i++) {
  $a = [Math]::Max(0, $i - 1); $b = [Math]::Min($cw - 1, $i + 1)
  $s = 0.0; for ($j = $a; $j -le $b; $j++) { $s += $col[$j] }
  $sm[$i] = $s / ($b - $a + 1)
}
$sortedCol = @($sm | Sort-Object)
$colMedian = $sortedCol[[int][Math]::Floor(($sortedCol.Count - 1) / 2)]
$colThr = [Math]::Max($SpikeMin, $colMedian * $SpikeK)

# 找连续的可疑列带
$runs = @()
$inRun = $false; $runStart = 0
for ($i = 0; $i -lt $cw; $i++) {
  if ($sm[$i] -gt $colThr) {
    if (-not $inRun) { $inRun = $true; $runStart = $i }
  } else {
    if ($inRun) { $runs += ,@($runStart, ($i - 1)); $inRun = $false }
  }
}
if ($inRun) { $runs += ,@($runStart, ($cw - 1)) }

# 列带 → 大致对应哪几个字（字宽仍用渲染比例，只用于报位置，不用于判定）
$advAll = [Px]::Measure($text, $best.font, $best.size)
$k = if ($advAll -gt 1) { $sb[2] / $advAll } else { 1.0 }
$ms = [Px]::Measures($text, $best.font, $best.size)
$suspect = @()
foreach ($r in $runs) {
  $rx0 = $r[0]; $rx1 = $r[1]
  if (($rx1 - $rx0) -lt 1) { continue }
  $ci0 = 0; $ci1 = $text.Length - 1
  for ($i = 0; $i -lt $text.Length; $i++) {
    $e0 = ($ms[$i] - $ms[0]) * $k; $e1 = ($ms[$i + 1] - $ms[0]) * $k
    if ($e1 -ge $rx0 - $sb[0] -and $ci0 -eq 0) { $ci0 = $i }
    if ($e0 -le $rx1 - $sb[0]) { $ci1 = $i }
  }
  $peak = 0.0
  for ($i = $rx0; $i -le $rx1; $i++) { if ($sm[$i] -gt $peak) { $peak = $sm[$i] } }
  $suspect += [pscustomobject]@{
    text = $text.Substring($ci0, [Math]::Max(1, $ci1 - $ci0 + 1))
    diff = [Math]::Round($peak, 3)
    x = $cx + $rx0; y = $cy; w = ($rx1 - $rx0 + 1); h = $chh
  }
}

$verdict = if ($suspect.Count -gt 0) { 'mismatch' } elseif ($best.m -gt 0.25) { 'unknown-font' } else { 'ok' }

[pscustomobject]@{
  ok = $true
  verdict = $verdict
  font = $best.font
  size = $best.size
  align = @{ dx = $best.dx; dy = $best.dy }
  lineDiff = [Math]::Round($best.m, 3)
  colMedian = [Math]::Round($colMedian, 3)
  chars = $text.Length
  suspectCount = $suspect.Count
  suspect = @($suspect | Select-Object -First 20)
} | ConvertTo-Json -Compress -Depth 5
