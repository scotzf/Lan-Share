// Live check against the real Windows hotspot. Turns the hotspot on and off.
// Run:  HOTSPOT_LIVE=1 flutter test test/live/hotspot_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/hotspot.dart';

Future<String> run(String command) async {
  final r = await Process.run('powershell.exe', [
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', 'assets/hotspot.ps1', command, '-OwnerPid', '$pid',
  ]);
  return r.stdout as String;
}

void main() {
  final live = Platform.environment['HOTSPOT_LIVE'] == '1';

  test('start, count clients, stop through the Dart wrapper', () async {
    final h = Hotspot(run);
    final info = await h.start();
    addTearDown(h.stop);
    expect(info.ssid, startsWith('LANShare-'));
    expect(info.pass.length, 12);
    expect(info.ip, '192.168.137.1');
    expect(info.owned, isTrue);
    expect(wifiQrString(info.ssid, info.pass), startsWith('WIFI:T:WPA;S:LANShare-'));
    expect(await h.clients(), 0);
    await h.stop();
    // second stop is a no-op and the state file is gone
    await h.stop();
    final state = File('${Platform.environment['LOCALAPPDATA']}\\LANShare\\hotspot_state.json');
    expect(state.existsSync(), isFalse);
  }, skip: live ? false : 'set HOTSPOT_LIVE=1 to run against the real hotspot');

  test('recover leaves a hotspot alone while its owner is still running', () async {
    final h = Hotspot(run);
    await h.start();
    addTearDown(h.stop);
    await h.recover(); // owner pid = this test process, which is alive
    final status = await run('status');
    expect(status, contains('"on":true'));
    await h.stop();
  }, skip: live ? false : 'set HOTSPOT_LIVE=1 to run against the real hotspot');
}
