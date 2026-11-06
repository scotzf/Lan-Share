# Adds "LAN Share" to the Windows right-click menu for files (current user).
# Remove with: reg delete "HKCU\Software\Classes\*\shell\LANShare" /f
param([string]$Exe = (Join-Path $PSScriptRoot '..\..\build\windows\x64\runner\Release\lan_share.exe'))
$exe = (Resolve-Path $Exe).Path
$cmd = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Classes\*\shell\LANShare\command')
$cmd.SetValue('', '"' + $exe + '" "%1"')
$cmd.Close()
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes\*\shell\LANShare', $true)
$key.SetValue('', 'LAN Share')
$key.SetValue('Icon', '"' + $exe + '"')
$key.Close()
Write-Host 'Registered.'
