param(
  [Parameter(Mandatory = $true)][string]$Image,
  [Parameter(Mandatory = $true)][string]$Out
)

# Decode any image (png / jpg / webp / gif / tif / bmp) into a plain PNG frame,
# so the crop pipeline can treat photos exactly like screenshots.
# Uses the Windows Imaging Component through WinRT, because System.Drawing has no WebP decoder.

$ErrorActionPreference = 'Stop'

function Fail($msg) {
  Write-Output ((@{ ok = $false; error = [string]$msg } | ConvertTo-Json -Compress))
  exit 2
}

if (-not (Test-Path -LiteralPath $Image)) { Fail ('image not found: ' + $Image) }

# WinRT wants a real Windows path; callers often pass forward slashes.
$WinPath = ($Image -replace '/', '\')
if (-not [System.IO.Path]::IsPathRooted($WinPath)) { $WinPath = [System.IO.Path]::GetFullPath($WinPath) }

Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]

function AwaitOp($op, [Type]$t) {
  $m = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
      $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*'
    })[0]
  $task = $m.MakeGenericMethod($t).Invoke($null, @($op))
  $task.Wait(-1) | Out-Null
  $task.Result
}

try {
  $file = AwaitOp ([Windows.Storage.StorageFile]::GetFileFromPathAsync($WinPath)) ([Windows.Storage.StorageFile])
  $stream = AwaitOp ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $dec = AwaitOp ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $iw = [int]$dec.PixelWidth
  $ih = [int]$dec.PixelHeight
  if ($iw -le 0 -or $ih -le 0) { Fail 'decoded size is zero' }

  $transform = [Windows.Graphics.Imaging.BitmapTransform]::new()
  $data = AwaitOp ($dec.GetPixelDataAsync(
      [Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,
      [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied,
      $transform,
      [Windows.Graphics.Imaging.ExifOrientationMode]::IgnoreExifOrientation,
      [Windows.Graphics.Imaging.ColorManagementMode]::DoNotColorManage)) ([Windows.Graphics.Imaging.PixelDataProvider])
  $bytes = $data.DetachPixelData()

  $bmp = [System.Drawing.Bitmap]::new($iw, $ih, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $rect = [System.Drawing.Rectangle]::new(0, 0, $iw, $ih)
  $bd = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $bd.Scan0, [Math]::Min($bytes.Length, $bd.Stride * $ih))
  $bmp.UnlockBits($bd)
  $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  $stream.Dispose()
} catch {
  Fail ($_.Exception.Message)
}

$sha = [System.Security.Cryptography.SHA256]::Create()
$fs = [System.IO.File]::OpenRead($Out)
$hashBytes = $sha.ComputeHash($fs)
$fs.Dispose()
$hash = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLower()

Write-Output ((@{
      ok      = $true
      w       = $iw
      h       = $ih
      x       = 0
      y       = 0
      path    = $Out
      src     = $Image
      hash    = $hash
      frameId = (Get-Date -Format 'yyyyMMdd-HHmmssfff')
    } | ConvertTo-Json -Compress))
