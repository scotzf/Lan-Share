# Removes LAN Share: menu entries, package registration, installed files.
# The signing certificate is removed separately (admin):
#   Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object Subject -eq 'CN=LanShareDev' | Remove-Item
param([string]$Target = (Join-Path $env:LOCALAPPDATA 'Programs\LANShare'))
Stop-Process -Name lan_share -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
Get-AppxPackage -Name LanShare.Dev | Remove-AppxPackage
[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\Classes\*\shell\LANShare', $false)
if (Test-Path $Target) { Remove-Item -Recurse -Force $Target }
Write-Host 'Removed.'
