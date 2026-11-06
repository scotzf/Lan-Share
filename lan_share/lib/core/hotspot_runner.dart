import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// Runs the bundled hotspot script with PowerShell and returns its stdout.
/// The script is copied next to the app's data so PowerShell can open it.
Future<String> powershellRunner(String command) async {
  final base = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
  final dir = await Directory('$base${Platform.pathSeparator}LANShare').create(recursive: true);
  final script = File('${dir.path}${Platform.pathSeparator}hotspot.ps1');
  final source = await rootBundle.loadString('assets/hotspot.ps1');
  if (!script.existsSync() || script.readAsStringSync() != source) {
    script.writeAsStringSync(source);
  }
  final proc = await Process.start('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle',
    'Hidden',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    script.path,
    command,
    '-OwnerPid',
    '$pid',
  ]);
  final out = proc.stdout.transform(utf8.decoder).join();
  unawaited(proc.stderr.drain<void>());
  try {
    await proc.exitCode.timeout(const Duration(seconds: 40));
  } on TimeoutException {
    proc.kill();
    return '{"ok":false,"error":"timeout"}';
  }
  return out;
}
