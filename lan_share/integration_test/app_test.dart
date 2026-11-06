// Drives the real app on Windows: real server, real TLS, real Windows hotspot.
// Run:  flutter test integration_test/app_test.dart -d windows
// Turns the Windows Mobile Hotspot on and off.
// WARNING: this builds a test-harness exe; rebuild with `flutter build windows --debug` after.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lan_share/core/qr_payload.dart';
import 'package:lan_share/core/settings.dart';
import 'package:lan_share/ui/send_screen.dart';
import 'package:lan_share/ui/send_view.dart';
import 'package:lan_share/ui/theme.dart';

/// Pumps real time until [finder] matches, or fails after [seconds].
Future<void> until(WidgetTester t, Finder finder, {int seconds = 40, String? why}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for ${why ?? finder.description}');
}

/// Pumps real time until [test] is true.
Future<void> untilTrue(WidgetTester t, bool Function() test, {int seconds = 40, String why = 'condition'}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (test()) return;
  }
  fail('timed out waiting for $why');
}

Future<void> wait(WidgetTester t, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

const script = 'assets/hotspot.ps1';

Future<String> hotspotStatus() async {
  final r = await Process.run('powershell.exe', [
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', '${Directory.current.path}/$script', 'status',
  ]);
  return r.stdout as String;
}

/// Flips to true when the test wants a phone to appear on the hotspot.
bool phoneJoined = false;

/// The real hotspot script, except that `clients` reports a joined phone on cue.
Future<String> scriptWithPhone(String command) async {
  if (command == 'clients') return '{"ok":true,"clients":${phoneJoined ? 1 : 0}}';
  final r = await Process.run('powershell.exe', [
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', '${Directory.current.path}/$script', command, '-OwnerPid', '$pid',
  ]);
  return r.stdout as String;
}

String currentQr(WidgetTester t) => t.widget<QrBox>(find.byType(QrBox)).data;

HttpClient phone() => HttpClient()..badCertificateCallback = (_, __, ___) => true;

Future<int> ping(HttpClient c, Uri link) async {
  final r = await (await c.getUrl(link.replace(path: '/ping', query: ''))).close();
  await r.drain<void>();
  return r.statusCode;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late List<File> files;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('it_');
    files = [
      File('${dir.path}/Holiday photo.png')..writeAsBytesSync(List.generate(80000, (i) => i % 251)),
      File('${dir.path}/movie clip.mp4')..writeAsBytesSync(List.generate(3 << 20, (i) => (i * 3) & 0xff)),
      File('${dir.path}/Report Q3.pdf')..writeAsStringSync('%PDF fake'),
    ];
    phoneJoined = false;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  // never leave the real hotspot on, even when an assertion fails
  Future<void> hotspotOff() => Process.run('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', '${Directory.current.path}/$script', 'stop', '-OwnerPid', '$pid',
      ]);

  testWidgets('assist ON: QR usable at once, then gains the hotspot hint; both addresses work; auto turn-off',
      (t) async {
    addTearDown(hotspotOff);
    expect(await hotspotStatus(), contains('"on":false'));
    await t.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: SendScreen(files: files, hotspotRunner: scriptWithPhone, settings: Settings(hotspotAssist: true))));

    // 1. the LAN QR is there straight away, before the hotspot is up
    await until(t, find.byKey(const Key('qr')), why: 'link QR');
    expect(find.text('3'), findsOneWidget);
    final first = parseQrPayload(currentQr(t))!;
    expect(first.hotspot, isNull, reason: 'no hint until the hotspot is really up');
    expect(first.link.scheme, 'https');

    // 2. a few seconds later the same QR carries the hotspot hint
    await untilTrue(t, () => parseQrPayload(currentQr(t))?.hotspot != null, seconds: 60, why: 'hotspot hint in the QR');
    final qr = parseQrPayload(currentQr(t))!;
    expect(qr.hotspot!.ip, '192.168.137.1');
    expect(qr.hotspot!.ssid, startsWith('LANShare-'));
    expect(qr.link.toString(), first.link.toString(), reason: 'the link itself did not change');
    expect(await hotspotStatus(), contains('"on":true'), reason: 'Windows hotspot really is on');
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Wi-Fi'), findsOneWidget);

    // 3. one server answers on the home Wi-Fi address AND on the hotspot address
    final c = phone();
    expect(await ping(c, qr.link), 204, reason: 'home Wi-Fi address');
    expect(await ping(c, qr.hotspotLink!), 204, reason: 'hotspot address');
    final req = await c.getUrl(Uri(scheme: 'http', host: '192.168.137.1'));
    req.followRedirects = false;
    req.headers.host = '192.168.137.1';
    final bounce = await req.close();
    await bounce.drain<void>();
    expect(bounce.headers.value('location'), startsWith('https://192.168.137.1:'));

    // 4. the Wi-Fi join QR (for a browser phone off the LAN) matches the hint
    await t.tap(find.byKey(const Key('wifiToggle')));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('wifiQr')), findsOneWidget);
    expect(currentQr(t), 'WIFI:T:WPA;S:${qr.hotspot!.ssid};P:${qr.hotspot!.pass};;');
    await t.tap(find.byKey(const Key('wifiToggle')));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('qr')), findsOneWidget);
    await wait(t, 1500);

    // 5. an Android phone off the LAN downloads through the hotspot address, byte for byte
    final manifest = jsonDecode(await utf8.decodeStream(await (await c.getUrl(qr.hotspotLink!)).close())) as Map;
    final listed = (manifest['files'] as List).cast<Map>();
    expect(listed.length, 3);
    for (var i = 0; i < listed.length; i++) {
      final b = BytesBuilder();
      final url = qr.hotspotLink!.replace(path: listed[i]['url'] as String, query: '');
      await for (final chunk in await (await c.getUrl(url)).close()) {
        b.add(chunk);
      }
      expect(b.takeBytes(), files[i].readAsBytesSync(), reason: listed[i]['name'] as String);
    }
    c.close();

    // 6. done, and the hotspot turns itself off
    await until(t, find.text('Done'), seconds: 30, why: 'Done');
    final end = DateTime.now().add(const Duration(seconds: 40));
    var off = false;
    while (DateTime.now().isBefore(end) && !off) {
      await t.pump(const Duration(milliseconds: 500));
      off = (await hotspotStatus()).contains('"on":false');
    }
    expect(off, isTrue, reason: 'hotspot must turn itself off after the transfer');
    await wait(t, 1500);
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('assist OFF: no hotspot by itself; the button starts it, Stop removes it', (t) async {
    addTearDown(hotspotOff);
    await t.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: SendScreen(files: files, hotspotRunner: scriptWithPhone, settings: Settings(hotspotAssist: false))));
    await until(t, find.byKey(const Key('qr')), why: 'link QR');
    await wait(t, 6000);
    expect(await hotspotStatus(), contains('"on":false'), reason: 'assist is off');
    expect(parseQrPayload(currentQr(t))!.hotspot, isNull);
    expect(find.text('Hotspot'), findsOneWidget);
    expect(find.byKey(const Key('wifiToggle')), findsNothing);

    await t.tap(find.byKey(const Key('hotspot')));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.widget<TextButton>(find.byKey(const Key('hotspot'))).onPressed, isNull, reason: 'busy while starting');
    expect(find.byKey(const Key('qr')), findsOneWidget, reason: 'QR never disappears');
    await untilTrue(t, () => parseQrPayload(currentQr(t))?.hotspot != null, seconds: 60, why: 'hint after the button');
    expect(await hotspotStatus(), contains('"on":true'));

    await t.tap(find.byKey(const Key('hotspot')));
    await untilTrue(t, () => parseQrPayload(currentQr(t))?.hotspot == null, seconds: 60, why: 'hint removed after Stop');
    expect(await hotspotStatus(), contains('"on":false'));
    await wait(t, 1000);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
