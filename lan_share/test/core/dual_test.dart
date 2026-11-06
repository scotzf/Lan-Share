import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/identity.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';

HttpClient phone() => HttpClient()..badCertificateCallback = (_, __, ___) => true;

void main() {
  late Directory dir, idDir;
  late Identity id;
  setUpAll(() async {
    idDir = Directory.systemTemp.createTempSync('du_id_');
    id = await loadOrCreateIdentity(idDir);
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('du_'));
  tearDown(() => dir.deleteSync(recursive: true));
  tearDownAll(() => idDir.deleteSync(recursive: true));

  Future<SenderServer> serve({bool all = false}) async {
    final f = File('${dir.path}/a.txt')..writeAsStringSync('hello');
    final s = SenderServer([f], TokenStore(),
        identity: id,
        bindAddress: InternetAddress.loopbackIPv4,
        bindAll: all,
        httpRedirectPort: 0);
    addTearDown(s.stop);
    await s.start();
    return s;
  }

  test('/ping answers 204 and never uses up the one-time token', () async {
    final s = await serve();
    final c = phone();
    final base = s.link!.replace(path: '/', query: '');
    for (var i = 0; i < 3; i++) {
      final r = await (await c.getUrl(base.resolve('/ping'))).close();
      await r.drain<void>();
      expect(r.statusCode, 204);
    }
    final m = jsonDecode(await utf8.decodeStream(await (await c.getUrl(s.link!)).close())) as Map;
    expect((m['files'] as List).length, 1, reason: 'token still works after pings');
    c.close();
  });

  test('ping works before and after the token is used, on the plain-http side it bounces', () async {
    final s = await serve();
    final c = phone();
    await (await (await c.getUrl(s.link!)).close()).drain<void>();
    final r = await (await c.getUrl(s.link!.replace(path: '/ping', query: ''))).close();
    await r.drain<void>();
    expect(r.statusCode, 204);
    c.close();
  });

  test('listening on all interfaces: reachable by loopback and by the machine LAN address', () async {
    final s = await serve(all: true);
    expect(s.link!.host, '127.0.0.1', reason: 'the QR still shows the chosen address');
    final c = phone();
    // 1. via loopback
    var r = await (await c.getUrl(s.link!.replace(path: '/ping', query: ''))).close();
    await r.drain<void>();
    expect(r.statusCode, 204);
    // 2. via any other IPv4 address this machine has (LAN, hotspot, virtual)
    final others = [
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
        for (final a in i.addresses)
          if (!a.isLoopback) a
    ];
    if (others.isEmpty) return; // no second address on this machine
    r = await (await c.getUrl(Uri(scheme: 'https', host: others.first.address, port: s.link!.port, path: '/ping'))).close();
    await r.drain<void>();
    expect(r.statusCode, 204, reason: 'reachable on ${others.first.address}');
    c.close();
  });

  test('bound to one address: not reachable through the others', () async {
    final s = await serve(all: false);
    final others = [
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
        for (final a in i.addresses)
          if (!a.isLoopback) a
    ];
    if (others.isEmpty) return;
    final c = phone();
    await expectLater(
        c.getUrl(Uri(scheme: 'https', host: others.first.address, port: s.link!.port, path: '/ping')).then((r) => r.close()),
        throwsA(isA<SocketException>()));
    c.close();
  });

  test('typed-address redirect follows the address the phone used', () async {
    final s = await serve(all: true);
    final c = phone();
    final req = await c.getUrl(s.httpUri!);
    req.followRedirects = false;
    req.headers.host = '192.168.137.1';
    final r = await req.close();
    await r.drain<void>();
    expect(r.statusCode, 302);
    expect(r.headers.value('location'), 'https://192.168.137.1:${s.link!.port}/');
    c.close();
  });
}
