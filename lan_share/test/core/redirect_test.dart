import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/identity.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';

void main() {
  late Directory src, idDir;
  late SenderServer s;
  late Uri secure;
  setUp(() async {
    src = Directory.systemTemp.createTempSync('rd_');
    idDir = Directory.systemTemp.createTempSync('ri_');
    final f = File('${src.path}/a.txt')..writeAsStringSync('x');
    s = SenderServer([f], TokenStore(),
        bindAddress: InternetAddress.loopbackIPv4,
        identity: await loadOrCreateIdentity(idDir),
        httpRedirectPort: 0);
    secure = await s.start();
  });
  tearDown(() async {
    await s.stop();
    src.deleteSync(recursive: true);
    idDir.deleteSync(recursive: true);
  });

  Future<HttpClientResponse> plain(String path) async {
    final c = HttpClient();
    final req = await c.getUrl(s.httpUri!.resolve(path));
    req.followRedirects = false;
    final r = await req.close();
    await r.drain();
    c.close();
    return r;
  }

  test('plain http is bounced to the secure code page', () async {
    final r = await plain('/');
    expect(r.statusCode, 302);
    expect(r.headers.value('location'), 'https://127.0.0.1:${secure.port}/');
  });

  test('any plain path bounces to the code page, never to a token', () async {
    final r = await plain('/${secure.pathSegments.first}');
    expect(r.statusCode, 302);
    expect(r.headers.value('location'), isNot(contains(secure.pathSegments.first)));
  });

  test('short address omits the port only on port 80', () {
    expect(s.shortAddress, '127.0.0.1:${s.httpUri!.port}');
  });

  test('stop closes the redirect listener too', () async {
    final uri = s.httpUri!;
    await s.stop();
    await expectLater(HttpClient().getUrl(uri).then((r) => r.close()),
        throwsA(isA<SocketException>()));
  });
}
