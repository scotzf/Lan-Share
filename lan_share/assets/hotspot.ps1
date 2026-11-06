# LAN Share hotspot helper. Commands: status | start | stop | clients | recover
# Prints one line of JSON. Uses Windows Mobile Hotspot (NetworkOperatorTetheringManager).
#   start   : turns the hotspot on with a random name and password, remembering the user's
#             own settings; does nothing to a hotspot that was already on.
#   stop    : turns it off and restores the remembered settings (only if LAN Share started it).
#   recover : same as stop, but skipped while the app that started it is still running;
#             run at app start to clean up after a crash.
param([Parameter(Position = 0)][string]$Command = 'status', [int]$OwnerPid = 0)
$ErrorActionPreference = 'Stop'

function Out-Json($o) { $o | ConvertTo-Json -Compress; exit 0 }
function Fail($msg) { Out-Json @{ ok = $false; error = $msg } }

try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
  $null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
} catch { Fail 'unsupported' }

$asOp = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$asAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]

function Await-Op($op, $type) {
  $t = $asOp.MakeGenericMethod($type).Invoke($null, @($op)); $null = $t.Wait(-1); $t.Result
}
function Await-Action($a) {
  $t = $asAction.Invoke($null, @($a)); $null = $t.Wait(-1)
}

$stateDir = Join-Path $env:LOCALAPPDATA 'LANShare'
$stateFile = Join-Path $stateDir 'hotspot_state.json'

$profile = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
if ($null -eq $profile) {
  if ($Command -eq 'stop' -or $Command -eq 'recover') {
    # offline now, but a hotspot we started may still need cleaning up: nothing can be done without a profile
    Out-Json @{ ok = $true; state = 'offline' }
  }
  Fail 'offline'
}
$cap = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::GetTetheringCapabilityFromConnectionProfile($profile)
if ("$cap" -ne 'Enabled') { Fail "unavailable:$cap" }
$mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($profile)

function Hotspot-Ip {
  $a = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -like '192.168.137.*' -and $_.AddressState -eq 'Preferred' } | Select-Object -First 1
  if ($a) { $a.IPAddress } else { $null }
}

# Windows reports the hotspot started before it has an address; wait for it (up to ~20 s).
function Wait-HotspotIp {
  for ($i = 0; $i -lt 40; $i++) {
    $ip = Hotspot-Ip
    if ($ip) { return $ip }
    Start-Sleep -Milliseconds 500
  }
  return $null
}

switch ($Command) {
  'status' {
    Out-Json @{ ok = $true; on = ("$($mgr.TetheringOperationalState)" -eq 'On'); clients = [int]$mgr.ClientCount }
  }
  'clients' {
    Out-Json @{ ok = $true; clients = [int]$mgr.ClientCount; on = ("$($mgr.TetheringOperationalState)" -eq 'On') }
  }
  'start' {
    $cfg = $mgr.GetCurrentAccessPointConfiguration()
    if ("$($mgr.TetheringOperationalState)" -eq 'On') {
      # the user's own hotspot is already running: use it as it is and never turn it off
      $ip = Wait-HotspotIp
      if (-not $ip) { Fail 'start:noaddress' }
      Out-Json @{ ok = $true; ssid = $cfg.Ssid; pass = $cfg.Passphrase; ip = $ip; owned = $false }
    }
    New-Item -ItemType Directory -Force $stateDir | Out-Null
    @{ ssid = $cfg.Ssid; pass = $cfg.Passphrase; ownerPid = $OwnerPid } | ConvertTo-Json -Compress | Set-Content $stateFile -Encoding UTF8
    $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
    $rand = New-Object System.Random
    $newPass = -join (1..12 | ForEach-Object { $chars[$rand.Next($chars.Length)] })
    $cfg.Ssid = 'LANShare-' + (-join (1..4 | ForEach-Object { $chars[$rand.Next($chars.Length)] }))
    $cfg.Passphrase = $newPass
    Await-Action ($mgr.ConfigureAccessPointAsync($cfg))
    $res = Await-Op ($mgr.StartTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
    if ("$($res.Status)" -ne 'Success') {
      # put the user's settings back before reporting the failure
      $old = Get-Content $stateFile -Raw | ConvertFrom-Json
      $cfg.Ssid = $old.ssid; $cfg.Passphrase = $old.pass
      Await-Action ($mgr.ConfigureAccessPointAsync($cfg))
      Remove-Item $stateFile -ErrorAction SilentlyContinue
      Fail "start:$($res.Status)"
    }
    $ip = Wait-HotspotIp
    if (-not $ip) {
      # no address ever appeared: undo everything so the hotspot is not left half on
      $null = Await-Op ($mgr.StopTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
      $old = Get-Content $stateFile -Raw | ConvertFrom-Json
      $cfg.Ssid = $old.ssid; $cfg.Passphrase = $old.pass
      Await-Action ($mgr.ConfigureAccessPointAsync($cfg))
      Remove-Item $stateFile -ErrorAction SilentlyContinue
      Fail 'start:noaddress'
    }
    Out-Json @{ ok = $true; ssid = $cfg.Ssid; pass = $newPass; ip = $ip; owned = $true }
  }
  { $_ -in 'stop', 'recover' } {
    if (-not (Test-Path $stateFile)) { Out-Json @{ ok = $true; state = 'not-ours' } }
    if ($Command -eq 'recover') {
      $owner = [int](Get-Content $stateFile -Raw | ConvertFrom-Json).ownerPid
      if ($owner -gt 0 -and (Get-Process -Id $owner -ErrorAction SilentlyContinue)) { Out-Json @{ ok = $true; state = 'in-use' } }
    }
    if ("$($mgr.TetheringOperationalState)" -eq 'On') {
      $null = Await-Op ($mgr.StopTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
    }
    $old = Get-Content $stateFile -Raw | ConvertFrom-Json
    $cfg = $mgr.GetCurrentAccessPointConfiguration()
    $cfg.Ssid = $old.ssid; $cfg.Passphrase = $old.pass
    Await-Action ($mgr.ConfigureAccessPointAsync($cfg))
    Remove-Item $stateFile -ErrorAction SilentlyContinue
    Out-Json @{ ok = $true; state = 'restored' }
  }
  default { Fail "unknown:$Command" }
}
