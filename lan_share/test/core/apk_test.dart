import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/identity.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';
import 'package:lan_share/core/web_pages.dart';

HttpClient phone() => HttpClient()..badCertificateCallback = (_, __, ___) => true;

void main() {
  late Directory dir, idDir;
  late Identity id;
  setUpAll(() async {
    idDir = Directory.systemTemp.createTempSync('ak_id_');
    id = await loadOrCreateIdentity(idDir);
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('ak_'));
  tearDown(() => dir.deleteSync(recursive: true));
  tearDownAll(() => idDir.deleteSync(recursive: true));

  Future<SenderServer> serve({File? apk}) async {
    final f = File('${dir.path}/a.txt')..writeAsStringSync('hello');
    final s = SenderServer([f], TokenStore(),
        identity: id, bindAddress: InternetAddress.loopbackIPv4, httpRedirectPort: 0, apk: apk);
    addTearDown(s.stop);
    await s.start();
    return s;
  }

  test('/app.apk serves the app file with the Android package type', () async {
    final apk = File('${dir.path}/lanshare.apk')..writeAsBytesSync(List.generate(50000, (i) => i % 251));
    final s = await serve(apk: apk);
    final c = phone();
    final r = await (await c.getUrl(s.link!.replace(path: '/app.apk', query: ''))).close();
    expect(r.statusCode, 200);
    expect(r.headers.contentType?.mimeType, 'application/vnd.android.package-archive');
    expect(r.headers.value('content-disposition'), contains('lanshare.apk'));
    final b = BytesBuilder();
    await for (final chunk in r) {
      b.add(chunk);
    }
    expect(b.takeBytes(), apk.readAsBytesSync());
    c.close();
  });

  test('the app file needs no token, so a phone can still get it after the share was opened', () async {
    final apk = File('${dir.path}/lanshare.apk')..writeAsBytesSync([1, 2, 3]);
    final s = await serve(apk: apk);
    final c = phone();
    await (await (await c.getUrl(s.link!)).close()).drain<void>(); // token used up
    final r = await (await c.getUrl(s.link!.replace(path: '/app.apk', query: ''))).close();
    await r.drain<void>();
    expect(r.statusCode, 200);
    c.close();
  });

  test('without an app file, /app.apk is a 404', () async {
    final s = await serve();
    final c = phone();
    final r = await (await c.getUrl(s.link!.replace(path: '/app.apk', query: ''))).close();
    await r.drain<void>();
    expect(r.statusCode, 404);
    c.close();
  });

  test('a missing app file on disk is a 404 and does not crash the server', () async {
    final s = await serve(apk: File('${dir.path}/nope.apk'));
    final c = phone();
    final r = await (await c.getUrl(s.link!.replace(path: '/app.apk', query: ''))).close();
    await r.drain<void>();
    expect(r.statusCode, 404);
    final ping = await (await c.getUrl(s.link!.replace(path: '/ping', query: ''))).close();
    await ping.drain<void>();
    expect(ping.statusCode, 204);
    c.close();
  });

  test('the download page shows an Android app button only when the app is available', () async {
    final apk = File('${dir.path}/lanshare.apk')..writeAsBytesSync([1]);
    final s = await serve(apk: apk);
    final c = phone();
    final req = await c.getUrl(s.link!);
    req.headers.set('Accept', 'text/html');
    final html = await utf8.decodeStream(await req.close());
    expect(html, contains('Android app'));
    expect(html, contains('href="/app.apk"'));
    c.close();
    expect(downloadPage(const [WebFile('a.txt', 5, '/s/x/f/0')]), isNot(contains('Android app')));
    expect(downloadPage(const [WebFile('a.txt', 5, '/s/x/f/0')], appLink: '/app.apk'), contains('Android app'));
  });
}
