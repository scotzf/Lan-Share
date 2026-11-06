import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/identity.dart';
import 'package:lan_share/core/receiver_client.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';

void main() {
  late Directory src, dest, idDir;
  late Identity id;
  late SenderServer s;
  setUp(() async {
    src = Directory.systemTemp.createTempSync('ts_');
    dest = Directory.systemTemp.createTempSync('td_');
    idDir = Directory.systemTemp.createTempSync('ti_');
    id = await loadOrCreateIdentity(idDir);
    final f = File('${src.path}/a.txt')..writeAsStringSync('secret');
    s = SenderServer([f], TokenStore(),
        bindAddress: InternetAddress.loopbackIPv4, identity: id);
  });
  tearDown(() async {
    await s.stop();
    for (final d in [src, dest, idDir]) {
      d.deleteSync(recursive: true);
    }
  });

  test('link is https and carries the fingerprint', () async {
    final link = await s.start();
    expect(link.scheme, 'https');
    expect(link.queryParameters['fp'], id.fingerprint);
  });

  test('receive works when the pinned fingerprint matches', () async {
    final link = await s.start();
    await ReceiverClient().receive(link, dest);
    expect(File('${dest.path}/a.txt').readAsStringSync(), 'secret');
  });

  test('wrong fingerprint is refused and nothing is written', () async {
    final link = await s.start();
    final bad = link.replace(queryParameters: {'fp': 'a' * 64});
    await expectLater(ReceiverClient().receive(bad, dest), throwsA(isA<TransferException>()));
    expect(dest.listSync(), isEmpty);
  });

  test('https link without a fingerprint is refused', () async {
    final link = await s.start();
    final bare = link.replace(queryParameters: {});
    await expectLater(ReceiverClient().receive(bare, dest), throwsA(isA<TransferException>()));
  });

  test('plain http is refused unless explicitly allowed', () async {
    await expectLater(
        ReceiverClient().receive(Uri.parse('http://127.0.0.1:9/x'), dest),
        throwsA(isA<TransferException>()));
  });

  test('pairing code is the same on both sides and download works', () async {
    final link = await s.start();
    final req = s.pairRequests.first;
    final session = await ReceiverClient()
        .requestPair(link.host, link.port, poll: const Duration(milliseconds: 20));
    final r = await req;
    expect(session.code, r.code);
    s.approve(r.id);
    final approved = await session.approval;
    await ReceiverClient().receive(approved!, dest);
    expect(File('${dest.path}/a.txt').readAsStringSync(), 'secret');
  });
}
