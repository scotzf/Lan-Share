import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/receiver_client.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';

void main() {
  receiverTests();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('pg_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('progress covers all files together and is throttled', () async {
    final a = File('${dir.path}/a.bin')..writeAsBytesSync(List.filled(12 << 20, 1));
    final b = File('${dir.path}/b.bin')..writeAsBytesSync(List.filled(18 << 20, 2));
    final s = SenderServer([a, b], TokenStore(), bindAddress: InternetAddress.loopbackIPv4);
    addTearDown(s.stop);
    final events = <TransferProgress>[];
    s.progress.listen(events.add);
    final link = await s.start();
    final dest = Directory.systemTemp.createTempSync('pgd_');
    addTearDown(() => dest.deleteSync(recursive: true));
    await ReceiverClient(allowInsecure: true).receive(link, dest);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final active = events.where((e) => e.state == TransferState.active).toList();
    expect(active, isNotEmpty);
    expect(active.last.overallTotal, 30 << 20);
    expect(active.last.overallSent, 30 << 20, reason: 'last update reports everything sent');
    // overall progress never goes backwards, even when the second file starts
    for (var i = 1; i < active.length; i++) {
      expect(active[i].overallSent, greaterThanOrEqualTo(active[i - 1].overallSent));
    }
    // 30 MB in 64 KB chunks is ~480 chunks; throttled updates are far fewer
    expect(active.length, lessThan(120), reason: 'progress must not fire per chunk');
    expect(active.last.overallFraction, closeTo(1.0, 1e-9));
  });

  test('overallFraction falls back to per-file when overall totals are unknown', () {
    const p = TransferProgress(TransferState.active, sent: 5, total: 10);
    expect(p.overallFraction, 0.5);
  });
}

void receiverTests() {
  test('receiver reports overall progress and returns the files it saved', () async {
    final dir = Directory.systemTemp.createTempSync('pr_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final a = File('${dir.path}/a.bin')..writeAsBytesSync(List.filled(3 << 20, 1));
    final b = File('${dir.path}/b.bin')..writeAsBytesSync(List.filled(5 << 20, 2));
    final s = SenderServer([a, b], TokenStore(), bindAddress: InternetAddress.loopbackIPv4);
    addTearDown(s.stop);
    final link = await s.start();
    final dest = Directory.systemTemp.createTempSync('prd_');
    addTearDown(() => dest.deleteSync(recursive: true));
    final client = ReceiverClient(allowInsecure: true);
    final seen = <TransferProgress>[];
    client.progress.listen(seen.add);
    final files = await client.receive(link, dest);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(files.map((f) => f.uri.pathSegments.last), ['a.bin', 'b.bin']);
    expect(files.map((f) => f.lengthSync()), [3 << 20, 5 << 20]);
    final active = seen.where((e) => e.state == TransferState.active).toList();
    expect(active.last.overallTotal, 8 << 20);
    expect(active.last.overallSent, 8 << 20);
    for (var i = 1; i < active.length; i++) {
      expect(active[i].overallSent, greaterThanOrEqualTo(active[i - 1].overallSent));
    }
  });
}
