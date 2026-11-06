# Installs the app build to a fixed folder and points both Windows menu entries at it.
# Needs: windows\sparse\lanshare.msix built, and its certificate trusted (see windows\sparse).
# Uses the Debug build by default: Smart App Control blocked a fresh unsigned Release build
# on this PC but allows Debug builds. Pass -Source ...\Release if your PC allows it.
param(
  [string]$Source = (Join-Path $PSScriptRoot '..\..\build\windows\x64\runner\Debug'),
  [string]$Target = (Join-Path $env:LOCALAPPDATA 'Programs\LANShare')
)
$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path $Source).Path
Stop-Process -Name lan_share -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# 1. Copy the app
New-Item -ItemType Directory -Force $Target | Out-Null
Copy-Item -Path (Join-Path $Source '*') -Destination $Target -Recurse -Force
$exe = Join-Path $Target 'lan_share.exe'

# The Android app, offered to phones from the laptop's download page (build it first, see dist\README)
$apk = Join-Path $PSScriptRoot '..\..\dist\lanshare.apk'
if (Test-Path $apk) { Copy-Item $apk (Join-Path $Target 'lanshare.apk') -Force }

# 2. Right-click entry (Show more options)
$cmd = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Classes\*\shell\LANShare\command')
$cmd.SetValue('', '"' + $exe + '" "%1"'); $cmd.Close()
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes\*\shell\LANShare', $true)
$key.SetValue('', 'LAN Share'); $key.SetValue('Icon', '"' + $exe + '"'); $key.Close()

# 3. "Share with" entry (sparse package pointing at the install folder)
Get-AppxPackage -Name LanShare.Dev | Remove-AppxPackage
Add-AppxPackage -Path (Join-Path $PSScriptRoot '..\sparse\lanshare.msix') -ExternalLocation $Target
Write-Host "Installed to $Target"
