# Android Helper and Hotspot Assist: Design Addendum

Date: 2026-11-06. Supersedes "Android is out of scope" in earlier specs. Approved by the user in chat.

## Goal
Fewest steps possible. Browser phones on the same Wi-Fi: scan once. Android phones with our app: scan once, even when not on the same Wi-Fi (one system "Connect" tap when a hotspot join is needed). Browser phones off the LAN must join the LAN (or use the manual hotspot Wi-Fi QR).

## Laptop
- Server listens on all interfaces (`0.0.0.0`) so one port serves both the home Wi-Fi address and the hotspot address (`192.168.137.1`). Redirects use the Host header the phone typed.
- New `GET /ping` returns 204 and consumes nothing; the app uses it to test reachability without using the one-time token.
- QR payload v2 = the normal secure link plus a URL fragment `#hs=<ssid>&hp=<pass>&hip=<ip>` when the hotspot is up. Browsers ignore the fragment. Pure functions `qrPayload` / `parseQrPayload` (shared by the laptop and Android app).
- Hotspot assist: setting `hotspotAssist` (default **on**), stored in `settings.json` in the app support folder. While sharing, the hotspot starts in the background; the QR gains the hint when it is up. The hotspot button toggles it and remembers the choice. Stops after the transfer, on close, on expiry, and on app exit (existing behaviour).
- The manual "Wi-Fi join QR" view stays, reachable while the hotspot is up, for browser phones off the LAN.

## Android app (same Flutter project, Android platform)
- Home: one big scan button (icon). Scanner reads the QR, parses the payload.
- Receive: probe `https://<lan>:<port>/ping` (2 s). If reachable download. Else if the payload has hotspot info: join with `WifiNetworkSpecifier` (system prompt), bind the process to that network, probe `https://<hip>:<port>/ping` for up to 8 s, download from there. Else show the no-network state.
- Download uses the existing pinned-TLS `ReceiverClient`; files are written to cache then copied into the public Downloads folder through MediaStore (platform channel). Network released afterwards.
- UI: same visual language, light/dark, no instructional text: scanning, joining (Wi-Fi icon, violet), downloading (ring + speed), done (check), failed, offline.
- Android 10+ (API 29) needed for the join; older phones can use the LAN path only.

## Distribution
Release APK (debug-signed) built from the same code and bundled with the laptop app as an asset; the laptop serves it at `/app.apk` and the browser download page shows an "Android app" button.

## Testing
Unit: payload round trip, settings, `/ping`, dual-interface server, assist state machine. Emulator: LAN path against the running laptop app. Real phone needed for the hotspot join (cannot be emulated).

## Out of scope
iPhone app; phone-to-laptop sending (later); Play Store distribution.
