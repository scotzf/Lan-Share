Build the Android app, then copy it here as `lanshare.apk`:

    flutter build apk --release --target-platform android-arm64
    copy build\app\outputs\flutter-apk\app-release.apk dist\lanshare.apk

`windows\installer\install.ps1` installs it next to the laptop app, which then offers it to phones.
