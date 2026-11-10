param(
  [string]$Filter = '',
  [int]$Limit = 300
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# 1) families the current session can actually use
$fam = @()
try {
  $ff = New-Object System.Drawing.Text.InstalledFontCollection
  foreach ($f in $ff.Families) { $fam += $f.Name }
} catch {}

# 2) registry: display name -> file name  (this is the "key ring")
$reg = @()
foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
                    'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts')) {
  if (-not (Test-Path $root)) { continue }
  $props = Get-ItemProperty $root
  foreach ($p in $props.PSObject.Properties) {
    if ($p.Name -like 'PS*') { continue }
    $val = [string]$p.Value
    if ([string]::IsNullOrWhiteSpace($val)) { continue }
    if ($val -notmatch '\.(ttf|ttc|otf|fon)$') { continue }
    $reg += [pscustomobject]@{
      display = $p.Name
      file    = $val
      source  = if ($root -like 'HKCU*') { 'user' } else { 'machine' }
    }
  }
}

$dirs = @("$env:WINDIR\Fonts", "$env:LOCALAPPDATA\Microsoft\Windows\Fonts")
$rows = @()
foreach ($r in $reg) {
  $path = $null
  foreach ($d in $dirs) {
    $c = Join-Path $d $r.file
    if (Test-Path $c) { $path = $c; break }
  }
  if (-not $path -and (Test-Path $r.file)) { $path = $r.file }

  $disp = $r.display -replace '\s*\((TrueType|OpenType|All res|PostScript).*\)\s*$', ''
  foreach ($piece in ($disp -split '\s*&\s*')) {
    $name = $piece.Trim()
    if ($name -eq '') { continue }
    $rows += [pscustomobject]@{
      family = $name
      file   = $path
      source = $r.source
      loaded = ($fam -contains $name)
    }
  }
}

if ($Filter -ne '') {
  $rows = @($rows | Where-Object { $_.family -like "*$Filter*" })
}

$rows = @($rows | Sort-Object family -Unique)
$total = $rows.Count

$out = [pscustomobject]@{
  ok       = $true
  count    = $total
  shown    = [Math]::Min($total, $Limit)
  fonts    = @($rows | Select-Object -First $Limit)
  hint     = 'pick the family that matches the app UI (noted by name or file); if the app bundles its own ttf/otf, pass that file path instead'
}

$out | ConvertTo-Json -Compress -Depth 4
