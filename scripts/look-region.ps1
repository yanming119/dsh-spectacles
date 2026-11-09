param(
  [int]$TimeoutSec = 60,
  [string]$Out = ""
)
$DataDir = if ($env:DSH_LOOK_DATA) { $env:DSH_LOOK_DATA } else { Join-Path $env:TEMP 'dsh-look' }
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force -Path $DataDir | Out-Null }
if (-not $Out) { $Out = Join-Path $DataDir 'region.json' }
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class Rg {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);

  public struct POINT { public int X, Y; }
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][Rg]::SetProcessDPIAware()

$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen

# 不抓屏幕：这层遮罩只是一块半透明的、能透过它看见下面东西的玻璃，
# 用来接你的拖动、记下矩形坐标。框选本身不产生任何画面内容。
$script:W = $vs.Width
$script:H = $vs.Height
$script:sel = $null
$script:dragging = $false
$script:done = $false
$script:cancelled = $false
$script:start = $null
$script:pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 0, 205, 120)), 2
$script:penDot = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(200, 255, 255, 255)), 1
$script:font = New-Object System.Drawing.Font 'Microsoft YaHei UI', 12, ([System.Drawing.FontStyle]::Bold)
$script:brText = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$script:brBox = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(215, 20, 24, 30))

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Bounds = New-Object System.Drawing.Rectangle $vs.Left, $vs.Top, $vs.Width, $vs.Height
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.Cursor = [System.Windows.Forms.Cursors]::Cross
$form.KeyPreview = $true
$form.BackColor = [System.Drawing.Color]::Black
$form.Opacity = 0.22
try { $form.GetType().GetProperty('DoubleBuffered', 'Instance,NonPublic').SetValue($form, $true) } catch {}

function Draw-Tag($g, $text, $x, $y) {
  $sz = $g.MeasureString($text, $script:font)
  $w = [int]$sz.Width + 16; $h = [int]$sz.Height + 8
  $bx = [Math]::Max(0, [Math]::Min($x, $script:W - $w))
  $by = [Math]::Max(0, [Math]::Min($y, $script:H - $h))
  $g.FillRectangle($script:brBox, $bx, $by, $w, $h)
  $g.DrawString($text, $script:font, $script:brText, ($bx + 8), ($by + 4))
}

$form.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $r = $script:sel
    if ($r -and $r.Width -gt 0 -and $r.Height -gt 0) {
      $g.DrawRectangle($script:pen, $r)
      Draw-Tag $g ("{0} x {1}" -f $r.Width, $r.Height) ($r.Left + 6) ($r.Top + 6)
    }
    else {
      Draw-Tag $g '拖一个框；Esc 取消' 40 40
    }
  })

$form.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
      $script:start = $e.Location
      $script:sel = New-Object System.Drawing.Rectangle $e.X, $e.Y, 0, 0
      $script:dragging = $true
      $s.Invalidate()
    }
    elseif ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
      $script:cancelled = $true
      $s.Close()
    }
  })

$form.Add_MouseMove({
    param($s, $e)
    if (-not $script:dragging) { return }
    $x1 = [Math]::Min($script:start.X, $e.X); $y1 = [Math]::Min($script:start.Y, $e.Y)
    $x2 = [Math]::Max($script:start.X, $e.X); $y2 = [Math]::Max($script:start.Y, $e.Y)
    $script:sel = New-Object System.Drawing.Rectangle $x1, $y1, ($x2 - $x1), ($y2 - $y1)
    $s.Invalidate()
  })

$closeTimer = New-Object System.Windows.Forms.Timer
$closeTimer.Interval = 160
$closeTimer.Add_Tick({ $closeTimer.Stop(); $form.Close() })

$form.Add_MouseUp({
    param($s, $e)
    if (-not $script:dragging) { return }
    $script:dragging = $false
    if ($script:sel -and $script:sel.Width -ge 8 -and $script:sel.Height -ge 8) {
      $script:done = $true
      # 先把遮罩藏掉（人立刻看见框定住了），窗口晚 160ms 再关：
      # 松手这一下要是当场关窗，抬键消息会漏给下面的窗口，有的程序会当成一次点击。
      $s.Visible = $false
      $closeTimer.Start()
    }
  })

$form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
      $script:cancelled = $true
      $s.Close()
    }
  })

$form.Add_Shown({ $form.Activate() })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [Math]::Max(1000, $TimeoutSec * 1000)
$timer.Add_Tick({ $script:cancelled = $true; $form.Close() })
$timer.Start()

[System.Windows.Forms.Application]::Run($form)
$timer.Stop()

if (-not $script:done -or -not $script:sel) {
  @{ ok = $false; error = 'cancelled' } | ConvertTo-Json -Compress
  exit 1
}

# 等遮罩真的消失，不然 WindowFromPoint 会点到我们自己
Start-Sleep -Milliseconds 90

$sel = $script:sel
$sx = $vs.Left + $sel.X
$sy = $vs.Top + $sel.Y

$pt = New-Object Rg+POINT
$pt.X = $sx + [int]($sel.Width / 2)
$pt.Y = $sy + [int]($sel.Height / 2)
$h = [Rg]::WindowFromPoint($pt)
if ($h -eq [IntPtr]::Zero) { @{ ok = $false; error = 'no window under the box' } | ConvertTo-Json -Compress; exit 1 }
$root = [Rg]::GetAncestor($h, 2)
if ($root -eq [IntPtr]::Zero) { $root = $h }

$sb = New-Object System.Text.StringBuilder 512
[Rg]::GetWindowText($root, $sb, 512) | Out-Null
if ($sb.Length -eq 0) {
  @{ ok = $false; error = '那个位置没有窗口（是桌面空白处），换个地方再框' } | ConvertTo-Json -Compress
  exit 1
}
$wr = New-Object Rg+RECT
[Rg]::GetWindowRect($root, [ref]$wr) | Out-Null
$procId = 0
[Rg]::GetWindowThreadProcessId($root, [ref]$procId) | Out-Null

# 框可能越出窗口：裁到窗口里面，换算成相对窗口左上角
$ix = [Math]::Max($sx, $wr.Left); $iy = [Math]::Max($sy, $wr.Top)
$ir = [Math]::Min($sx + $sel.Width, $wr.Right); $ib = [Math]::Min($sy + $sel.Height, $wr.Bottom)
$cw = [Math]::Max(1, $ir - $ix)
$ch = [Math]::Max(1, $ib - $iy)
$cx = $ix - $wr.Left
$cy = $iy - $wr.Top

$res = [ordered]@{
  ok     = $true
  when   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
  hwnd   = [int64]$root
  title  = $sb.ToString()
  pid    = $procId
  rect   = @($wr.Left, $wr.Top, ($wr.Right - $wr.Left), ($wr.Bottom - $wr.Top))
  screen = @($sx, $sy, $sel.Width, $sel.Height)
  crop   = @($cx, $cy, $cw, $ch)
}

$dir = Split-Path $Out -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
[System.IO.File]::WriteAllText($Out, ($res | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))

$res | ConvertTo-Json -Compress
