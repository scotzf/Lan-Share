import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/receiver_client.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';

Future<Map> getJson(Uri u) async {
  final c = HttpClient();
  final r = await (await c.getUrl(u)).close();
  final m = jsonDecode(await utf8.decodeStream(r)) as Map;
  c.close();
  return m;
}

void main() {
  receiverPairTests();
  late Directory dir;
  late SenderServer s;
  late Uri base;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('pr_');
    final f = File('${dir.path}/a.txt')..writeAsStringSync('hi');
    s = SenderServer([f], TokenStore(), bindAddress: InternetAddress.loopbackIPv4);
    base = (await s.start()).replace(path: '/');
  });
  tearDown(() async {
    await s.stop();
    dir.deleteSync(recursive: true);
  });

  test('pair request emits a 4-digit code, approve yields a working link', () async {
    final req = s.pairRequests.first;
    final created = await getJson(base.resolve('/pair'));
    final r = await req;
    expect(r.code, matches(RegExp(r'^\d{4}$')));
    expect(created['code'], r.code);
    expect((await getJson(base.resolve('/pair/${created['id']}')))['status'], 'pending');
    s.approve(r.id);
    final done = await getJson(base.resolve('/pair/${created['id']}'));
    expect(done['status'], 'approved');
    final m = await getJson(base.resolve(done['link'] as String));
    expect((m['files'] as List).length, 1);
  });

  test('deny gives denied and no link', () async {
    final req = s.pairRequests.first;
    final created = await getJson(base.resolve('/pair'));
    s.deny((await req).id);
    final st = await getJson(base.resolve('/pair/${created['id']}'));
    expect(st['status'], 'denied');
    expect(st['link'], isNull);
  });
}

void receiverPairTests() {
  test('ReceiverClient.requestPair returns code and resolves link on approve', () async {
    final dir = Directory.systemTemp.createTempSync('rp_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/a.txt')..writeAsStringSync('hi');
    final s = SenderServer([f], TokenStore(), bindAddress: InternetAddress.loopbackIPv4);
    addTearDown(s.stop);
    final u = await s.start();
    s.pairRequests.listen((r) => s.approve(r.id));
    final session = await ReceiverClient(allowInsecure: true).requestPair(u.host, u.port, secure: false,
        poll: const Duration(milliseconds: 20));
    expect(session.code, matches(RegExp(r'^\d{4}$')));
    final link = await session.approval;
    expect(link, isNotNull);
    final dest = Directory.systemTemp.createTempSync('rpd_');
    addTearDown(() => dest.deleteSync(recursive: true));
    await ReceiverClient(allowInsecure: true).receive(link!, dest);
    expect(File('${dest.path}/a.txt').readAsStringSync(), 'hi');
  });
}
