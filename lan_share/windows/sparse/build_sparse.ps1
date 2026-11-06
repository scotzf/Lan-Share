# Builds and signs the sparse package that registers LAN Share as a Windows share target.
# Output: lanshare.msix (signed) and lanshare.cer (public cert to trust).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$sdk = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64'

$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=LanShareDev' } | Select-Object -First 1
if (-not $cert) {
  $cert = New-SelfSignedCertificate -Type Custom -Subject 'CN=LanShareDev' -KeyUsage DigitalSignature `
    -FriendlyName 'LAN Share Dev' -CertStoreLocation 'Cert:\CurrentUser\My' `
    -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
}
Export-Certificate -Cert $cert -FilePath (Join-Path $here 'lanshare.cer') | Out-Null

$msix = Join-Path $here 'lanshare.msix'
if (Test-Path $msix) { Remove-Item $msix }
& "$sdk\makeappx.exe" pack /d (Join-Path $here 'stage') /p $msix /nv | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'makeappx failed' }
& "$sdk\signtool.exe" sign /fd SHA256 /sha1 $cert.Thumbprint $msix | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'signtool failed' }
Write-Host "Built $msix ; thumbprint $($cert.Thumbprint)"
