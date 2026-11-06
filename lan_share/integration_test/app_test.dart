// Drives the real app on Windows: real server, real TLS, real Windows hotspot.
// Run:  flutter test integration_test/app_test.dart -d windows
// Turns the Windows Mobile Hotspot on and off.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lan_share/ui/send_screen.dart';
import 'package:lan_share/ui/send_view.dart';
import 'package:lan_share/ui/theme.dart';

/// Pumps real time until [finder] matches, or fails after [timeout].
Future<void> until(WidgetTester t, Finder finder, {int seconds = 40, String? why}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for ${why ?? finder.description}');
}

Future<void> wait(WidgetTester t, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<String> hotspotStatus() async {
  final r = await Process.run('powershell.exe', [
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', '${Directory.current.path}\\assets\\hotspot.ps1', 'status',
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
    '-File', '${Directory.current.path}/assets/hotspot.ps1', command, '-OwnerPid', '$pid',
  ]);
  return r.stdout as String;
}

void mark(String s) => stdout.writeln('STEP: $s');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real app: QR, typed code, hotspot on/off, phone download, auto turn-off', (t) async {
    final dir = Directory.systemTemp.createTempSync('it_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final files = [
      File('${dir.path}\\Holiday photo.png')..writeAsBytesSync(List.generate(80000, (i) => i % 251)),
      File('${dir.path}\\movie clip.mp4')..writeAsBytesSync(List.generate(3 << 20, (i) => (i * 3) & 0xff)),
      File('${dir.path}\\Report Q3.pdf')..writeAsStringSync('%PDF fake'),
    ];

    addTearDown(() async {
      // never leave the real hotspot on, even when an assertion fails
      await Process.run('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', '${Directory.current.path}/assets/hotspot.ps1', 'stop', '-OwnerPid', '$pid',
      ]);
    });
    await t.pumpWidget(MaterialApp(theme: appTheme(), home: SendScreen(files: files, hotspotRunner: scriptWithPhone)));

    // 1. QR appears with the right file count and links
    mark('QR');
    await until(t, find.byKey(const Key('qr')), why: 'link QR');
    expect(find.text('3'), findsOneWidget, reason: 'file count chip');
    expect(find.text('No scanner?'), findsOneWidget);
    expect(find.text('Hotspot'), findsOneWidget);
    await wait(t, 1500);

    // 2. typed-code view shows address + 6-digit code, and switches back
    mark('manual');
    await t.tap(find.byKey(const Key('manual')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('manualAddress')), findsOneWidget);
    final code = (t.widget<Text>(find.byKey(const Key('manualCode'))).data ?? '').replaceAll(' ', '');
    expect(code, matches(RegExp(r'^\d{6}$')));
    await wait(t, 1500);
    await t.tap(find.byKey(const Key('manual')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('qr')), findsOneWidget);

    // 3. hotspot on: spinner, then the Wi-Fi QR with the real credentials
    mark('hotspot starting');
    expect(await hotspotStatus(), contains('"on":false'));
    await t.tap(find.byKey(const Key('hotspot')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    await until(t, find.byKey(const Key('wifiQr')), seconds: 60, why: 'Wi-Fi join QR');
    mark('hotspot joining');
    final qr = t.widget<QrBox>(find.byType(QrBox)).data;
    expect(qr, matches(RegExp(r'^WIFI:T:WPA;S:LANShare-[A-Za-z0-9]{4};P:[A-Za-z0-9]{12};;$')));
    expect(await hotspotStatus(), contains('"on":true'), reason: 'Windows hotspot really is on');
    await wait(t, 2500);

    // 4. typed fallback for joining shows the same network name and password
    mark('hotspot credentials');
    await t.tap(find.byKey(const Key('manual')));
    await t.pump(const Duration(milliseconds: 400));
    final ssid = t.widget<Text>(find.byKey(const Key('hotspotName'))).data!;
    final pass = t.widget<Text>(find.byKey(const Key('hotspotPass'))).data!;
    expect(qr, 'WIFI:T:WPA;S:$ssid;P:$pass;;');
    await wait(t, 2500);

    // 5. Stop: hotspot off, user's settings back, normal QR returns
    mark('hotspot stop');
    await t.tap(find.byKey(const Key('hotspot')));
    await until(t, find.byKey(const Key('qr')), seconds: 60, why: 'link QR after Stop');
    expect(await hotspotStatus(), contains('"on":false'));

    // 6. hotspot again, then act as the phone on the hotspot address and download everything
    mark('hotspot again');
    await t.tap(find.byKey(const Key('hotspot')));
    await until(t, find.byKey(const Key('wifiQr')), seconds: 60, why: 'Wi-Fi join QR (2nd)');
    await t.tap(find.byKey(const Key('manual'))); // shows the typed credentials...
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const Key('manual'))); // ...and back
    await t.pump(const Duration(milliseconds: 300));

    // a phone joins (faked); the screen swaps to the download QR on the hotspot address
    mark('phone joined');
    phoneJoined = true;
    await until(t, find.byKey(const Key('qr')), seconds: 30, why: 'download QR after a phone joins');
    final link = Uri.parse(t.widget<QrBox>(find.byType(QrBox)).data);
    expect(link.scheme, 'https');
    expect(link.host, '192.168.137.1', reason: 'server listens on the hotspot address');
    await wait(t, 2500);

    mark('phone journey');
    final phone = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    // typed address: plain http bounces to the secure code page
    final bounceReq = await phone.getUrl(Uri(scheme: 'http', host: '192.168.137.1'));
    bounceReq.followRedirects = false;
    final bounce = await bounceReq.close();
    expect(bounce.statusCode, 302);
    expect(bounce.headers.value('location') ?? '', startsWith('https://192.168.137.1:'));
    await bounce.drain<void>();
    // scanned link: manifest, then every file byte for byte
    final manifest = jsonDecode(await utf8.decodeStream(await (await phone.getUrl(link)).close())) as Map;
    final listed = (manifest['files'] as List).cast<Map>();
    expect(listed.length, 3);
    for (var i = 0; i < listed.length; i++) {
      final b = BytesBuilder();
      await for (final c in await (await phone.getUrl(link.resolve(listed[i]['url'] as String))).close()) {
        b.add(c);
      }
      expect(b.takeBytes(), files[i].readAsBytesSync(), reason: listed[i]['name'] as String);
    }
    phone.close();

    // transfer finished: Done shows, and the hotspot turns itself off
    mark('auto turn-off');
    await until(t, find.text('Done'), seconds: 30, why: 'Done after the last file');
    final end = DateTime.now().add(const Duration(seconds: 40));
    var off = false;
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 500));
      if ((await hotspotStatus()).contains('"on":false')) {
        off = true;
        break;
      }
    }
    expect(off, isTrue, reason: 'hotspot must turn itself off after the transfer');
    await wait(t, 2000);
    mark('DONE');
    return;
  }, timeout: const Timeout(Duration(minutes: 6)));
}
