# Spectacles self-test
# Runs on a machine where the plugin was just installed and reports what works.
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File selftest.ps1 [-Json]
# Exit code 0 = all required checks passed, 1 = something required failed.

param([switch]$Json)

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
$dataDir = if ($env:DSH_LOOK_DATA) { $env:DSH_LOOK_DATA } else { Join-Path $env:TEMP 'dsh-look-selftest' }
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }

$checks = New-Object System.Collections.ArrayList
function Add-Check([string]$name, [bool]$ok, [string]$detail, [bool]$required = $true) {
  [void]$checks.Add([ordered]@{ name = $name; ok = $ok; required = $required; detail = $detail })
}

# ---------------------------------------------------------------- environment
$os = [Environment]::OSVersion.Version
Add-Check 'windows' ($os.Major -ge 10) ('Windows ' + $os.Major + '.' + $os.Minor + ' build ' + $os.Build)

$psv = $PSVersionTable.PSVersion
Add-Check 'powershell' ($psv.Major -ge 5) ('PowerShell ' + $psv.ToString())

$needed = @('look.ps1', 'look2.ps1', 'look-pick.ps1', 'read-text.ps1')
$missing = @()
foreach ($n in $needed) { if (-not (Test-Path (Join-Path $here $n))) { $missing += $n } }
$scriptDetail = 'all 4 scripts present'
if ($missing.Count -gt 0) { $scriptDetail = 'missing: ' + ($missing -join ', ') }
Add-Check 'scripts' ($missing.Count -eq 0) $scriptDetail

$probe = Join-Path $dataDir 'write-probe.txt'
$writable = $false
try {
  Set-Content -Path $probe -Value 'ok' -ErrorAction Stop
  $writable = (Test-Path $probe)
  Remove-Item $probe -Force -ErrorAction SilentlyContinue
} catch { $writable = $false }
Add-Check 'temp-writable' $writable $dataDir

# ---------------------------------------------------------------- display
if (-not ('YM.SelfTest' -as [type])) {
  Add-Type -Namespace YM -Name SelfTest -MemberDefinition @'
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
[DllImport("user32.dll")] public static extern uint GetDpiForSystem();
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@
}
try { [void][YM.SelfTest]::SetProcessDPIAware() } catch {}

$sw = [YM.SelfTest]::GetSystemMetrics(0)
$sh = [YM.SelfTest]::GetSystemMetrics(1)
Add-Check 'screen-size' ($sw -gt 0 -and $sh -gt 0) ($sw.ToString() + ' x ' + $sh)

$dpi = 96
try { $dpi = [int][YM.SelfTest]::GetDpiForSystem() } catch {}
Add-Check 'dpi' ($dpi -ge 96) ($dpi.ToString() + ' dpi (' + [math]::Round($dpi / 96 * 100) + '%)')

try {
  Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
  $mon = [System.Windows.Forms.Screen]::AllScreens.Count
  Add-Check 'monitors' ($mon -ge 1) ($mon.ToString() + ' monitor(s)')
} catch {
  Add-Check 'monitors' $false ('could not query: ' + $_.Exception.Message) $false
}

# ---------------------------------------------------------------- full screen
$full = Join-Path $dataDir 'selftest-full.png'
$fullOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'look.ps1') -Image -Out $full 2>&1 | Out-String
$fullOk = $false
$fullDetail = $fullOut.Trim()
try {
  $o = $fullOut | ConvertFrom-Json
  $fullOk = [bool]$o.ok -and (Test-Path $full)
  if ($fullOk) { $fullDetail = $o.source + ' ' + $o.screen.w + 'x' + $o.screen.h + ' in ' + $o.captureMs + 'ms' }
} catch {}
Add-Check 'fullscreen-capture' $fullOk $fullDetail

# ---------------------------------------------------------------- window capture
$winScript = Join-Path $here 'look2.ps1'
$picked = $null
try {
  $listOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $winScript -List 2>&1 | Out-String
  $list = $listOut | ConvertFrom-Json
  if ($list.windows) {
    $picked = $list.windows |
      Where-Object { $_.title -and $_.rect.w -gt 200 -and $_.rect.h -gt 120 -and $_.rect.x -gt -1000 } |
      Select-Object -First 1
  }
} catch {}
if ($picked) {
  $winPng = Join-Path $dataDir 'selftest-window.png'
  $winOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $winScript -Window $picked.title -Image -Out $winPng 2>&1 | Out-String
  $winOk = $false
  $winDetail = $winOut.Trim()
  try {
    $o = $winOut | ConvertFrom-Json
    $winOk = [bool]$o.ok -and (Test-Path $winPng)
    if ($winOk) { $winDetail = '"' + $picked.title + '" ' + $o.region[2] + 'x' + $o.region[3] + ' via ' + $o.source }
  } catch {}
  Add-Check 'window-capture' $winOk $winDetail
} else {
  Add-Check 'window-capture' $false 'no capturable window found (open Notepad and rerun)' $false
}

# ---------------------------------------------------------------- OCR
if (Test-Path $full) {
  $ocrOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'read-text.ps1') -File $full 2>&1 | Out-String
  $ocrOk = $false
  $ocrDetail = 'no output'
  try {
    $o = $ocrOut | ConvertFrom-Json
    $ocrOk = [bool]$o.ok -and ([int]$o.chars -gt 0)
    $ocrDetail = $o.chars.ToString() + ' chars, ' + $o.disagree + ' uncertain, ' + $o.ms + 'ms'
  } catch { $ocrDetail = $ocrOut.Trim() }
  Add-Check 'ocr' $ocrOk $ocrDetail
} else {
  Add-Check 'ocr' $false 'skipped: full screen capture failed'
}

# ---------------------------------------------------------------- optional
$ff = $env:DSH_LOOK_FFMPEG
if ($ff) {
  Add-Check 'ffmpeg' (Test-Path $ff) ('DSH_LOOK_FFMPEG=' + $ff) $false
} else {
  $g = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
  $ffNote = 'not used (optional)'
  if ($g) { $ffNote = 'found on PATH, not used (optional)' }
  Add-Check 'ffmpeg' $true $ffNote $false
}

# ---------------------------------------------------------------- report
$failed = @($checks | Where-Object { $_.required -and -not $_.ok })
$ok = ($failed.Count -eq 0)

if ($Json) {
  [ordered]@{ ok = $ok; machine = $env:COMPUTERNAME; checks = $checks; dataDir = $dataDir } | ConvertTo-Json -Depth 5
} else {
  Write-Output ('Spectacles self-test on ' + $env:COMPUTERNAME)
  Write-Output ''
  foreach ($c in $checks) {
    $mark = '[FAIL]'
    if ($c.ok) { $mark = '[ ok ]' } elseif (-not $c.required) { $mark = '[warn]' }
    Write-Output ($mark + ' ' + $c.name.PadRight(18) + $c.detail)
  }
  Write-Output ''
  if ($ok) { Write-Output 'All required checks passed.' }
  else { Write-Output ('Failed: ' + (($failed | ForEach-Object { $_.name }) -join ', ')) }
  Write-Output ('Artifacts: ' + $dataDir)
}

if ($ok) { exit 0 } else { exit 1 }
