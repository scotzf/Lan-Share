# Home, Theme and Hotspot: Design Addendum

Date: 2026-11-06. Extends `2026-10-31-lan-share-design.md`. Android is out of scope; phones use the browser.

## Goals (user-approved)
1. **Home**: one large drop zone (drag files in, or click to pick). Receive is a small secondary button.
2. **Theme**: follow the system light/dark setting in the app and on the phone pages.
3. **Polish**: review every screen and state visually and fix what looks off.
4. **Hotspot**: laptop starts Windows Mobile Hotspot so a phone with no shared Wi-Fi can join by scanning a QR, then transfers; the hotspot is turned off afterwards.

## Hotspot design
- Capability confirmed read-only on the target laptop: tethering "Enabled" over the current Wi-Fi.
- API: `Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager`, driven from a PowerShell script (`windows/hotspot/hotspot.ps1`: `status`, `start`, `stop`, `clients`) that the app launches hidden. The script prints JSON.
- Per session: save the current hotspot SSID/passphrase, set a random SSID `LANShare-XXXX` and a random 12-character passphrase, start. On stop, restore the saved values and turn the hotspot off.
- Step 1 QR: `WIFI:T:WPA;S:<ssid>;P:<pass>;;` (phone joins). The app polls client count; at first client it moves to step 2.
- Step 2 QR: the normal download link, served on the hotspot adapter address (`192.168.137.1`).
- Stops on: transfer done, window closed, QR expired, app exit. A stale hotspot found at next launch is stopped and restored.
- Needs an internet connection to share; otherwise the button shows the offline icon state.
- No words in the UI: hotspot icon button; join QR shows a Wi-Fi icon badge; states shown by icon and colour.

## Non-goals
Internet relay; changing the user's saved hotspot permanently; Android/iOS apps.

## Testing
Pure logic (QR string escaping, state machine, script output parsing) is unit tested. The script itself is tested by running it on the laptop: start, observe client-ready state, stop, confirm original settings restored.
