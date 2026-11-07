import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';

/// Fast mode = no TLS. These are the same journeys a phone takes, over plain HTTP.
Future<(int, String, String?)> get(Uri u, {bool html = false}) async {
  final c = HttpClient();
  final req = await c.getUrl(u);
  req.followRedirects = false;
  if (html) req.headers.set('Accept', 'text/html');
  final r = await req.close();
  final body = await utf8.decodeStream(r);
  final loc = r.headers.value('location');
  c.close();
  return (r.statusCode, body, loc);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('pm_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<SenderServer> plain({File? apk}) async {
    final f = File('${dir.path}/a b.txt')..writeAsStringSync('plain hello');
    final s = SenderServer([f], TokenStore(),
        bindAddress: InternetAddress.loopbackIPv4, redirect: true, httpRedirectPort: 0, apk: apk);
    addTearDown(s.stop);
    await s.start();
    return s;
  }

  test('the link is plain http with no fingerprint (so no browser warning)', () async {
    final s = await plain();
    expect(s.link!.scheme, 'http');
    expect(s.link!.queryParameters.containsKey('fp'), isFalse);
  });

  test('typed address bounces to the plain code page on the address the phone used', () async {
    final s = await plain();
    final c = HttpClient();
    final req = await c.getUrl(s.httpUri!);
    req.followRedirects = false;
    req.headers.host = '192.168.137.1';
    final r = await req.close();
    await r.drain<void>();
    expect(r.statusCode, 302);
    expect(r.headers.value('location'), 'http://192.168.137.1:${s.link!.port}/');
    c.close();
  });

  test('short address omits the port only on port 80, as with TLS', () async {
    final s = await plain();
    expect(s.shortAddress, '127.0.0.1:${s.httpUri!.port}');
  });

  test('the whole phone journey works over http: code page, code, download page, file', () async {
    final s = await plain();
    final base = s.link!.replace(path: '/', query: '');
    final page = await get(base, html: true);
    expect(page.$1, 200);
    expect(page.$2, contains('inputmode="numeric"'));
    final wrong = await get(base.resolve('/join?code=000000'));
    expect(wrong.$1, anyOf(403, 302));
    final join = await get(base.resolve('/join?code=${s.accessCode}'));
    expect(join.$1, 302);
    final list = await get(base.resolve(join.$3!), html: true);
    expect(list.$1, 200);
    expect(list.$2, contains('a b.txt'));
    final href = RegExp(r'href="(/s/[^"]+)"').firstMatch(list.$2)!.group(1)!;
    expect((await get(base.resolve(href))).$2, 'plain hello');
  });

  test('ping and the one-time token behave exactly as with TLS', () async {
    final s = await plain();
    final base = s.link!.replace(path: '/', query: '');
    expect((await get(base.resolve('/ping'))).$1, 204);
    expect((await get(s.link!)).$1, 200);
    expect((await get(s.link!)).$1, 403, reason: 'the token works once');
  });

  test('the Android app file is offered over http too', () async {
    final apk = File('${dir.path}/lanshare.apk')..writeAsBytesSync([1, 2, 3, 4]);
    final s = await plain(apk: apk);
    final r = await get(s.link!.replace(path: '/app.apk', query: ''));
    expect(r.$1, 200);
  });

  test('without redirect: true a plain server starts no extra listener (existing behaviour)', () async {
    final f = File('${dir.path}/x.txt')..writeAsStringSync('x');
    final s = SenderServer([f], TokenStore(), bindAddress: InternetAddress.loopbackIPv4);
    addTearDown(s.stop);
    await s.start();
    expect(s.httpUri, isNull);
  });
}
