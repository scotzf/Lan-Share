import 'dart:io';

/// The Android app, if it was installed beside this program (see windows/installer/install.ps1).
File? bundledApk() {
  final f = File('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}lanshare.apk');
  return f.existsSync() ? f : null;
}
