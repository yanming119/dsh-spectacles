param(
  [int]$TimeoutSec = 30,
  [string]$Out = ""
)
$DataDir = if ($env:DSH_LOOK_DATA) { $env:DSH_LOOK_DATA } else { Join-Path $env:TEMP 'dsh-look' }
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force -Path $DataDir | Out-Null }
if (-not $Out) { $Out = Join-Path $DataDir 'picked.json' }
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class Pk {
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);

  public struct POINT { public int X, Y; }
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

Write-Host "请点击你要指定的窗口（$TimeoutSec 秒内）..." -ForegroundColor Yellow

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$prevDown = ([Pk]::GetAsyncKeyState(0x01) -band 0x8000) -ne 0

$target = [IntPtr]::Zero
while ((Get-Date) -lt $deadline) {
  $down = ([Pk]::GetAsyncKeyState(0x01) -band 0x8000) -ne 0
  if ($down -and -not $prevDown) {
    $p = New-Object Pk+POINT
    [Pk]::GetCursorPos([ref]$p) | Out-Null
    $h = [Pk]::WindowFromPoint($p)
    if ($h -ne [IntPtr]::Zero) {
      $root = [Pk]::GetAncestor($h, 2)   # GA_ROOT
      if ($root -ne [IntPtr]::Zero) { $target = $root } else { $target = $h }
      break
    }
  }
  $prevDown = $down
  Start-Sleep -Milliseconds 40
}

if ($target -eq [IntPtr]::Zero) {
  @{ ok = $false; error = "timeout: no click" } | ConvertTo-Json -Compress
  exit 1
}

$sb = New-Object System.Text.StringBuilder 512
[Pk]::GetWindowText($target, $sb, 512) | Out-Null
$r = New-Object Pk+RECT
[Pk]::GetWindowRect($target, [ref]$r) | Out-Null
$procId = 0
[Pk]::GetWindowThreadProcessId($target, [ref]$procId) | Out-Null

$res = [ordered]@{
  ok    = $true
  when  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
  hwnd  = [int64]$target
  title = $sb.ToString()
  pid   = $procId
  rect  = @($r.Left, $r.Top, ($r.Right - $r.Left), ($r.Bottom - $r.Top))
}

$dir = Split-Path $Out -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
[System.IO.File]::WriteAllText($Out, ($res | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))

Write-Host ("已指定: [{0}] {1}  hwnd={2}" -f $res.pid, $res.title, $res.hwnd) -ForegroundColor Green
$res | ConvertTo-Json -Compress

