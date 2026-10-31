# LAN Share: Design Spec

Date: 2026-10-31

## Goal
Share files between devices on the same Wi-Fi/LAN with near-zero steps:
select files, right-click (Windows) or Share sheet (Android), pick the app,
the other side scans a QR code (or picks the sender from a nearby list), files transfer.
No cloud, no account. Traffic never leaves the LAN.

## Decisions (agreed)
- Platforms: Windows and Android, one Flutter codebase plus thin native glue.
- Receiver with a camera: scans QR. Receiver may be the app or a plain phone browser (no install).
- Receiver without a camera: app shows a nearby-sender list; user taps one and confirms a 4-digit code shown on both screens.
- Chosen for speed of delivery (single codebase). Transfer speed is LAN-bound regardless of stack.

## Components
1. **Share entry**
   - Windows: shell integration that passes selected file paths to the app (Windows 11: under "Show more options"; a packaged app is needed for a first-level entry, a later improvement).
   - Android: share target intent (ACTION_SEND / SEND_MULTIPLE).
2. **Sender service**: temporary HTTP server bound to the LAN interface, serving only the chosen files. Stops when the transfer completes or after ~5 minutes idle.
3. **QR screen**: QR encodes `https://<lan-ip>:<port>/<one-time-token>`. Shows the nearby-discovery state alongside.
4. **Discovery**: mDNS/DNS-SD advertisement of the sender; receivers list nearby senders.
5. **Receiver**: app (scan or nearby list, then confirm, then download) and a browser download page served by the sender.

## Flow
Pick files, Share with, QR appears. Receiver scans, or taps sender in nearby list and confirms the 4-digit code on both screens. Files stream directly; progress ring fills; green check on completion.

## Security
- Token is single-use and expires (default 5 min).
- App-to-app: TLS with the session key bound to the confirmed 4-digit code (pairing code defeats a rogue device on the LAN).
- Browser receive: self-signed certificate means a one-time browser warning; plain-HTTP fallback is NOT offered by default.
- Server serves only the selected files, no directory access; filenames sanitized on the receiver.
- No accounts, no telemetry, no external network calls.

## Errors
- Different network: icon state with retry.
- Interrupted transfer: retry button, resume where feasible.
- Expired token: refresh button generates a new QR.
- Code mismatch: transfer is refused and the session closed.

## UI
Per project style: icons, colour and progress rings; labels 1-3 words; no instructional text; one primary action per state.

## Build order
1. Transfer core (server, token, discovery, encryption) with tests.
2. Windows app and right-click entry.
3. Android app and Share sheet.
4. Browser download page.

## Testing
Unit tests for token lifecycle, code confirmation and encryption; integration test of sender/receiver on loopback; manual two-device LAN test on Windows and Android.

## Out of scope (v1)
iOS/macOS/Linux, internet relay, folders-as-trees beyond flat selection, transfer history.
