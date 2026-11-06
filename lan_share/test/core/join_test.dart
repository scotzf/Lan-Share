import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';

Future<(int, String, String?)> fetch(Uri u, {bool html = false}) async {
  final c = HttpClient();
  final req = await c.getUrl(u);
  req.followRedirects = false;
  if (html) req.headers.set('Accept', 'text/html');
  final r = await req.close();
  final body = await utf8.decodeStream(r);
  c.close();
  return (r.statusCode, body, r.headers.value('location'));
}

void main() {
  late Directory dir;
  late SenderServer s;
  late Uri base;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('jn_');
    final f = File('${dir.path}/a.txt')..writeAsStringSync('hi');
    s = SenderServer([f], TokenStore(), bindAddress: InternetAddress.loopbackIPv4);
    base = (await s.start()).replace(path: '/', query: '');
  });
  tearDown(() async {
    await s.stop();
    dir.deleteSync(recursive: true);
  });

  test('access code is 6 digits', () {
    expect(s.accessCode, matches(RegExp(r'^\d{6}$')));
  });

  test('root serves a page with a numeric code input', () async {
    final r = await fetch(base, html: true);
    expect(r.$1, 200);
    expect(r.$2, contains('inputmode="numeric"'));
  });

  test('right code redirects to the download page', () async {
    final j = await fetch(base.resolve('/join?code=${s.accessCode}'));
    expect(j.$1, 302);
    final page = await fetch(base.resolve(j.$3!), html: true);
    expect(page.$1, 200);
    expect(page.$2, contains('a.txt'));
  });

  test('wrong code is refused', () async {
    final wrong = s.accessCode == '000000' ? '111111' : '000000';
    expect((await fetch(base.resolve('/join?code=$wrong'))).$1, 403);
  });

  test('five wrong tries lock out even the right code', () async {
    final wrong = s.accessCode == '000000' ? '111111' : '000000';
    for (var i = 0; i < 5; i++) {
      await fetch(base.resolve('/join?code=$wrong'));
    }
    expect((await fetch(base.resolve('/join?code=${s.accessCode}'))).$1, 429);
  });
}
