import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/identity.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';
import 'package:lan_share/core/transfer_progress.dart';
import 'package:lan_share/mobile/net.dart';

void main() {
  late Directory work, idDir;
  late Identity id;
  late SenderServer server;
  late Uri link;
  setUpAll(() async {
    idDir = Directory.systemTemp.createTempSync('nt_id_');
    id = await loadOrCreateIdentity(idDir);
  });
  tearDownAll(() => idDir.deleteSync(recursive: true));
  setUp(() async {
    work = Directory.systemTemp.createTempSync('nt_');
    final a = File('${work.path}/photo one.png')..writeAsBytesSync(List.filled(2 << 20, 1));
    final b = File('${work.path}/doc.pdf')..writeAsBytesSync(List.filled(1 << 20, 2));
    server = SenderServer([a, b], TokenStore(),
        identity: id, bindAddress: InternetAddress.loopbackIPv4, httpRedirectPort: 0);
    link = await server.start();
  });
  tearDown(() async {
    await server.stop();
    work.deleteSync(recursive: true);
  });

  group('probeLink', () {
    test('answers true for our laptop, without using the one-time token', () async {
      expect(await probeLink(link), isTrue);
      expect(await probeLink(link), isTrue);
      final dest = Directory.systemTemp.createTempSync('nt_d_');
      addTearDown(() => dest.deleteSync(recursive: true));
      final files = await downloadLink(link, (_) {}, dest);
      expect(files.length, 2, reason: 'token still worked after probing');
    });

    test('false when the certificate is not the one in the QR', () async {
      final wrong = link.replace(queryParameters: {'fp': 'b' * 64});
      expect(await probeLink(wrong), isFalse);
    });

    test('false without a fingerprint (never trust an unpinned laptop)', () async {
      expect(await probeLink(link.replace(query: '')), isFalse);
    });

    test('false, and quickly, when nothing is listening', () async {
      final sw = Stopwatch()..start();
      final dead = Uri(scheme: 'https', host: '127.0.0.1', port: 1, path: '/x', queryParameters: {'fp': id.fingerprint});
      expect(await probeLink(dead), isFalse);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('false for an address that never answers, within the timeout', () async {
      final sw = Stopwatch()..start();
      // TEST-NET-1: guaranteed unroutable
      final void_ = Uri(scheme: 'https', host: '192.0.2.1', port: 443, path: '/x', queryParameters: {'fp': id.fingerprint});
      expect(await probeLink(void_), isFalse);
      expect(sw.elapsed, lessThan(const Duration(seconds: 6)));
    });
  });

  group('downloadLink', () {
    test('returns every file with its size and path, and reports overall progress', () async {
      final dest = Directory.systemTemp.createTempSync('nt_d2_');
      addTearDown(() => dest.deleteSync(recursive: true));
      final seen = <TransferProgress>[];
      final files = await downloadLink(link, seen.add, dest);
      expect(files.map((f) => f.name), ['photo one.png', 'doc.pdf']);
      expect(files.map((f) => f.size), [2 << 20, 1 << 20]);
      for (final f in files) {
        expect(File(f.path).lengthSync(), f.size);
        expect(f.path, startsWith(dest.path));
      }
      final active = seen.where((e) => e.state == TransferState.active);
      expect(active.last.overallTotal, 3 << 20);
      expect(active.last.overallSent, 3 << 20);
    });

    test('a link with the wrong fingerprint is refused and nothing is written', () async {
      final dest = Directory.systemTemp.createTempSync('nt_d3_');
      addTearDown(() => dest.deleteSync(recursive: true));
      await expectLater(downloadLink(link.replace(queryParameters: {'fp': 'c' * 64}), (_) {}, dest), throwsA(anything));
      expect(dest.listSync(), isEmpty);
    });
  });
}
