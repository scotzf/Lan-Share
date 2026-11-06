// Measures real transfer speed with the real UI running (animations, progress ring).
// Run:  flutter test integration_test/speed_test.dart -d windows
// WARNING: this builds a test-harness exe; rebuild with `flutter build windows --debug` after.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lan_share/ui/send_screen.dart';
import 'package:lan_share/ui/send_view.dart';
import 'package:lan_share/ui/theme.dart';

/// Downloads the first file behind a QR link on its own thread; returns MB/s.
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

  testWidgets('real app transfer speed with the UI running', (t) async {
    final dir = Directory.systemTemp.createTempSync('sp_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final big = File('${dir.path}\\big.bin');
    final sink = big.openWrite();
    final chunk = List<int>.filled(1 << 20, 9);
    for (var i = 0; i < 300; i++) {
      sink.add(chunk);
    }
    await sink.close();

    await t.pumpWidget(MaterialApp(theme: appTheme(), home: SendScreen(files: [big])));
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (find.byKey(const Key('qr')).evaluate().isEmpty && DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 200));
    }
    final link = t.widget<QrBox>(find.byType(QrBox)).data;
    final job = Isolate.run(() => download(link));
    var done = false;
    double? mbps;
    unawaited2(job.then((v) {
      mbps = v;
      done = true;
    }));
    while (!done) {
      await t.pump(const Duration(milliseconds: 16)); // keep rendering frames like the real app
    }
    File('${Directory.systemTemp.path}/lanshare_speed.txt')
        .writeAsStringSync('${mbps!.toStringAsFixed(1)} MB/s (300 MB, real UI running)');
    expect(mbps, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 4)));
}

void unawaited2(Future<void> f) {}
