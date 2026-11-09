param(
  [int]$TimeoutSec = 30,
  [string]$Out = ""
)
$DataDir = if ($env:DSH_LOOK_DATA) { $env:DSH_LOOK_DATA } else { Join-Path $env:TEMP 'dsh-look' }
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force -Path $DataDir | Out-Null }
if (-not $Out) { $Out = Join-Path $DataDir 'picked.json' }
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class Pk3 {
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);

  public struct POINT { public int X, Y; }
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

function Get-Title($h) {
  $sb = New-Object System.Text.StringBuilder 512
  [Pk3]::GetWindowText($h, $sb, 512) | Out-Null
  return $sb.ToString()
}

function Emit($obj) {
  $json = $obj | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText($Out, $json, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output $json
}

$start = [Pk3]::GetForegroundWindow()
$deadline = (Get-Date).AddSeconds($TimeoutSec)

while ((Get-Date) -lt $deadline) {
  $fg = [Pk3]::GetForegroundWindow()
  if ($fg -ne [IntPtr]::Zero -and $fg -ne $start -and [Pk3]::IsWindowVisible($fg) -and (Get-Title $fg).Length -gt 0) {
    # 真正判据：鼠标此刻就在这个窗口上——说明是用户点它，不是别的窗口自己冒出来。
    $pt = New-Object Pk3+POINT
    [Pk3]::GetCursorPos([ref]$pt) | Out-Null
    $under = [Pk3]::WindowFromPoint($pt)
    $root = if ($under -ne [IntPtr]::Zero) { [Pk3]::GetAncestor($under, 2) } else { [IntPtr]::Zero }
    if ($root -eq $fg) {
      # 别把宿主自己（DeepSeek Harness 的窗口）当成目标——它自己会冒到前台
      $procId = 0
      [Pk3]::GetWindowThreadProcessId($fg, [ref]$procId) | Out-Null
      $pname = ''
      try { $pname = (Get-Process -Id ([int]$procId) -ErrorAction Stop).ProcessName } catch { $pname = '' }
      if ($pname -like '*Harness*' -or (Get-Title $fg) -like '*DeepSeek Harness*') {
        Start-Sleep -Milliseconds 60
        continue
      }
      $r = New-Object Pk3+RECT
      [Pk3]::GetWindowRect($fg, [ref]$r) | Out-Null
      $procId = 0
      [Pk3]::GetWindowThreadProcessId($fg, [ref]$procId) | Out-Null
      Emit ([ordered]@{
        ok    = $true
        when  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        hwnd  = [int]$fg
        title = (Get-Title $fg)
        pid   = [int]$procId
        rect  = @([int]$r.Left, [int]$r.Top, [int]($r.Right - $r.Left), [int]($r.Bottom - $r.Top))
      })
      exit 0
    }
  }
  Start-Sleep -Milliseconds 60
}

Emit ([ordered]@{ ok = $false; error = 'timeout: no click' })
exit 1
