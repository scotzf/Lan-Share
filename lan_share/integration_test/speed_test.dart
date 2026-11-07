// Measures real transfer speed with the real UI running, encrypted and in Fast mode.
// Run:  flutter test integration_test/speed_test.dart -d windows
// Writes the numbers to %TEMP%/lanshare_speed.txt.
// WARNING: this builds a test-harness exe; rebuild with `flutter build windows --debug` after.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lan_share/core/settings.dart';
import 'package:lan_share/ui/send_screen.dart';
import 'package:lan_share/ui/send_view.dart';
import 'package:lan_share/ui/theme.dart';

/// Downloads the first file behind a QR link on its own thread; returns MB/s.
/// Works for both https (self-signed accepted) and plain http links.
Future<double> download(String link) async {
  final uri = Uri.parse(link);
  final c = HttpClient()..badCertificateCallback = (_, __, ___) => true;
  final m = jsonDecode(await utf8.decodeStream(await (await c.getUrl(uri)).close())) as Map;
  final url = ((m['files'] as List).first as Map)['url'] as String;
  final sw = Stopwatch()..start();
  var n = 0;
  await for (final b in await (await c.getUrl(uri.resolve(url))).close()) {
    n += b.length;
  }
  c.close();
  return n / (1 << 20) / (sw.elapsedMilliseconds / 1000);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = File('${Directory.systemTemp.path}/lanshare_speed.txt');
  setUpAll(() {
    if (report.existsSync()) report.deleteSync();
  });

  Future<void> measure(WidgetTester t, {required bool fast}) async {
    final dir = Directory.systemTemp.createTempSync('sp_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final big = File('${dir.path}/big.bin');
    final sink = big.openWrite();
    final chunk = List<int>.filled(1 << 20, 9);
    for (var i = 0; i < 300; i++) {
      sink.add(chunk);
    }
    await sink.close();

    await t.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: SendScreen(files: [big], settings: Settings(hotspotAssist: false, fastMode: fast))));
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (find.byKey(const Key('qr')).evaluate().isEmpty && DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 200));
    }
    final link = t.widget<QrBox>(find.byType(QrBox)).data;
    expect(link.startsWith(fast ? 'http://' : 'https://'), isTrue, reason: 'link matches the mode: $link');
    expect(find.byKey(const Key('fastBadge')), fast ? findsOneWidget : findsNothing);
    final job = Isolate.run(() => download(link));
    var done = false;
    double? mbps;
    job.then((v) {
      mbps = v;
      done = true;
    });
    while (!done) {
      await t.pump(const Duration(milliseconds: 16)); // keep rendering frames like the real app
    }
    report.writeAsStringSync('${fast ? "FAST (plain)" : "ENCRYPTED"}: ${mbps!.toStringAsFixed(1)} MB/s\n', mode: FileMode.append);
    expect(mbps, greaterThan(0));
  }

  testWidgets('encrypted: speed with the real UI running', (t) => measure(t, fast: false),
      timeout: const Timeout(Duration(minutes: 4)));
  testWidgets('fast mode: speed with the real UI running', (t) => measure(t, fast: true),
      timeout: const Timeout(Duration(minutes: 4)));
}
