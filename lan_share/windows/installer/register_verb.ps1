# Adds "LAN Share" to the Windows right-click menu for files (current user).
param([string]$Exe = (Join-Path $PSScriptRoot '..\..\build\windows\x64\runner\Release\lan_share.exe'))
$exe = (Resolve-Path $Exe).Path
$key = 'HKCU:\Software\Classes\*\shell\LANShare'
New-Item -Path "$key\command" -Force | Out-Null
Set-ItemProperty -Path $key -Name '(default)' -Value 'LAN Share'
Set-ItemProperty -Path $key -Name 'Icon' -Value "`"$exe`""
# One instance receives every selected file.
Set-ItemProperty -Path $key -Name 'MultiSelectModel' -Value 'Player'
Set-ItemProperty -Path "$key\command" -Name '(default)' -Value "`"$exe`" `"%1`""
Write-Host 'Registered.'
