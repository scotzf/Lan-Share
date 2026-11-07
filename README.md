# LAN Share

Send files from a Windows laptop to a phone over your own network.
Right-click a file, scan the QR code, done. No cloud, no account, nothing leaves your network.

<p align="center"><img src="lan_share/assets/logo.png" width="120" alt="LAN Share logo"></p>

## How it works

| You | Steps |
|---|---|
| **Any phone, same Wi-Fi** | Scan the QR with the camera, tap **Advanced → Proceed** once, tap download. |
| **Phone with no scanner** | Tap **No scanner?** on the laptop. On the phone, type the laptop's address, then the 6-digit code. |
| **Android with the LAN Share app** | Scan once. If the phone is not on your Wi-Fi, the app joins the laptop's hotspot by itself (one Android confirm tap) and downloads. |
| **Any phone, no app yet** | Tap **Android app** at the bottom of the download page to get the app from the laptop. |

On the laptop: right-click files and choose **Share with → LAN Share** (or **Show more options → LAN Share**), or drag files onto the app.

## Features

- **Direct and private.** The laptop runs a temporary server on your LAN and stops it after the transfer.
- **Encrypted by default.** TLS with a self-signed certificate. The QR carries the certificate fingerprint, so the app only trusts your laptop. Each QR works once and expires after 5 minutes.
- **Fast mode (a switch, off by default).** The **Fast** chip on the home screen shares over plain HTTP, like SHAREit: no browser certificate warning and much quicker (about 8× on the same PC: 22 MB/s encrypted, 188 MB/s plain, measured in the real app). The catch is that nothing is encrypted, so anyone on the same network who sees the link could download the files. Intended for your own home network. A bolt badge shows on the sending screen whenever a share is not encrypted. Your choice is remembered.
- **One QR, two networks.** The server listens on the home Wi-Fi and on the laptop's hotspot. With *hotspot assist* (on by default) the QR also carries the hotspot details, so the Android app can reach the laptop when the phone is on another network. The hotspot is turned off after the transfer, and your own hotspot settings are restored.
- **Nearby list.** Devices running the app can find each other and pair with a 4-digit code shown on both screens.
- **Live feedback.** Progress ring with percentage and MB/s; clear icon states for done, failed, expired and offline.
- **Light and dark.** Follows the system theme, in the laptop app, the Android app and the phone web pages.

## Requirements

- Windows 10/11 (the laptop app).
- [Flutter](https://docs.flutter.dev/get-started/install) with Windows desktop enabled, Developer Mode on, and Visual Studio Build Tools with the C++ desktop workload.
- For the Android app: the Android SDK (Android 10 or newer on the phone for the automatic hotspot join).

## Build and run

```powershell
cd lan_share
flutter pub get
flutter test                      # unit tests and end-to-end phone journeys
flutter build windows --debug
```

Install the laptop app and its menu entries:

```powershell
powershell -ExecutionPolicy Bypass -File windows\installer\install.ps1
```

The **Share with** entry needs a signed package that Windows trusts. Build it with
`windows\sparse\build_sparse.ps1`, then import the generated `lanshare.cer` into
*Trusted People* once, from an administrator PowerShell.
Remove everything with `windows\installer\uninstall.ps1`.

Android app (served to phones by the laptop):

```powershell
flutter build apk --release --target-platform android-arm64
copy build\app\outputs\flutter-apk\app-release.apk dist\lanshare.apk
# install.ps1 copies it next to the laptop app
```

> Windows **Smart App Control** can block a freshly built unsigned Release `.exe`.
> The installer therefore uses the Debug build by default.

## Project layout

```
lan_share/
  lib/core/      server, TLS identity, pairing, hotspot, QR payload, web pages
  lib/ui/        laptop screens
  lib/mobile/    Android app (scan, join hotspot, download, save)
  assets/        logo and hotspot.ps1 (Windows Mobile Hotspot control)
  android/       Android project (Kotlin helpers for Wi-Fi join and Downloads)
  windows/       runner, installer scripts, Share-with package
  test/          unit, end-to-end, gallery (screenshots of every screen)
  integration_test/   drives the real app and the real hotspot
docs/superpowers/    design specs and implementation plans
```

Useful commands:

```powershell
flutter test                                          # everything except live hardware tests
$env:GALLERY_OUT="gallery"; flutter test test/gallery # render every screen to PNG
$env:HOTSPOT_LIVE=1; flutter test test/live           # turns the real hotspot on and off
flutter test integration_test/app_test.dart -d windows  # real app + real hotspot
```

The integration tests build a test harness into the Debug folder; run `flutter build windows --debug` again before installing.

## Security notes

- By default traffic is encrypted end to end between the laptop and the phone; a phone browser shows a one-time certificate warning because the certificate is self-signed. In **Fast mode** it is plain HTTP (not encrypted), by your choice.
- The typed-code route locks after five wrong tries.
- The hotspot uses a random name and password per session and is stopped afterwards.
- Nothing is sent to any server other than the laptop itself.

## Status and known limits

- Laptop app, phone web pages and the end-to-end flows are tested, including against the real Windows hotspot.
- The **Android app** has been built and tested in logic and screens, but **not yet on a real phone** (camera scan, hotspot join and saving to Downloads need a device).
- Sharing several files at once through **Share with** in Explorer is not yet confirmed.
- iPhone: browser only, same Wi-Fi.
- Laptop app is Windows only.

## Docs

Design specs and plans are in [`docs/superpowers`](docs/superpowers).

## License

No license has been chosen yet.
