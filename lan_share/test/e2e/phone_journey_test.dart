// End-to-end journeys as a phone would take them, against the real server over real TLS.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/identity.dart';
import 'package:lan_share/core/receiver_client.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';

/// A phone browser: accepts the self-signed certificate (the "Advanced > Proceed" tap).
HttpClient phone() => HttpClient()..badCertificateCallback = (_, __, ___) => true;

Future<(int, String, Map<String, String>)> browse(HttpClient c, Uri u, {bool follow = true}) async {
  var url = u;
  for (var hops = 0; hops < 6; hops++) {
    final req = await c.getUrl(url);
    req.followRedirects = false;
    req.headers.set('Accept', 'text/html');
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    final loc = res.headers.value('location');
    if (follow && res.statusCode == 302 && loc != null) {
      url = url.resolve(loc);
      continue;
    }
    return (res.statusCode, body, {'url': url.toString()});
  }
  throw StateError('too many redirects');
}

Future<List<int>> fetchBytes(HttpClient c, Uri u) async {
  final res = await (await c.getUrl(u)).close();
  final b = BytesBuilder();
  await for (final chunk in res) {
    b.add(chunk);
  }
  return b.takeBytes();
}

void main() {
  late Directory work, idDir;
  late Identity id;
  setUpAll(() async {
    idDir = Directory.systemTemp.createTempSync('e2e_id_');
    id = await loadOrCreateIdentity(idDir);
  });
  setUp(() => work = Directory.systemTemp.createTempSync('e2e_'));
  tearDown(() => work.deleteSync(recursive: true));
  tearDownAll(() => idDir.deleteSync(recursive: true));

  File make(String name, List<int> bytes) => File('${work.path}/$name')..writeAsBytesSync(bytes);

  Future<SenderServer> serve(List<File> files) async {
    final s = SenderServer(files, TokenStore(),
        identity: id, bindAddress: InternetAddress.loopbackIPv4, httpRedirectPort: 0);
    addTearDown(s.stop);
    await s.start();
    return s;
  }

  test('typed-address journey: http -> code page -> code -> download page -> every file', () async {
    final a = make('Holiday photo.png', List.generate(5000, (i) => i % 251));
    final b = make('notes ✓ 写.txt', utf8.encode('héllo wörld'));
    final s = await serve([a, b]);
    final c = phone();

    // 1. the phone types the short address into the browser (plain http)
    final landing = await browse(c, s.httpUri!);
    expect(landing.$1, 200);
    expect(landing.$3['url'], startsWith('https://'));
    expect(landing.$2, contains('inputmode="numeric"'));

    // 2. wrong code: red state, still no files
    final wrong = await browse(c, Uri.parse(landing.$3['url']!).resolve('/join?code=000000'), follow: false);
    expect(wrong.$1, anyOf(403, 302));
    if (wrong.$1 == 403) expect(wrong.$2, contains('class="err"'));

    // 3. right code: lands on the download page listing both files
    final ok = await browse(c, Uri.parse(landing.$3['url']!).resolve('/join?code=${s.accessCode}'));
    expect(ok.$1, 200);
    expect(ok.$2, contains('Holiday photo.png'));
    expect(ok.$2, contains('notes ✓ 写.txt'));
    expect(ok.$2, contains('Save all'));

    // 4. tapping each download link returns the exact bytes
    final base = Uri.parse(ok.$3['url']!);
    final hrefs = RegExp(r'href="(/s/[^"]+)"').allMatches(ok.$2).map((m) => m.group(1)!).toList();
    expect(hrefs.length, 2);
    expect(await fetchBytes(c, base.resolve(hrefs[0])), a.readAsBytesSync());
    expect(await fetchBytes(c, base.resolve(hrefs[1])), b.readAsBytesSync());
    c.close();
  });

  test('QR journey with the app receiver: pinned TLS, bytes identical', () async {
    final f = make('report.pdf', List.generate(300000, (i) => (i * 7) % 256));
    final s = await serve([f]);
    final dest = Directory.systemTemp.createTempSync('e2e_dst_');
    addTearDown(() => dest.deleteSync(recursive: true));
    final qr = Uri.parse(await _qrLink(s)); // https + token + fingerprint, as scanned
    await ReceiverClient().receive(qr, dest);
    expect(File('${dest.path}/report.pdf').readAsBytesSync(), f.readAsBytesSync());
  });

  test('a QR link works exactly once', () async {
    final f = make('once.txt', utf8.encode('x'));
    final s = await serve([f]);
    final qr = Uri.parse(await _qrLink(s));
    final c = phone();
    expect((await browse(c, qr)).$1, 200);
    expect((await browse(c, qr)).$1, 403);
    c.close();
  });

  test('five wrong codes lock the page; the right code no longer works', () async {
    final f = make('lock.txt', utf8.encode('x'));
    final s = await serve([f]);
    final base = Uri.parse(await _qrLink(s)).replace(path: '/', query: '');
    final c = phone();
    final wrong = s.accessCode == '000000' ? '111111' : '000000';
    for (var i = 0; i < 5; i++) {
      await browse(c, base.resolve('/join?code=$wrong'), follow: false);
    }
    final locked = await browse(c, base.resolve('/join?code=${s.accessCode}'), follow: false);
    expect(locked.$1, 429);
    expect(locked.$2, contains('lock'));
    c.close();
  });

  test('nobody can reach a file without the session', () async {
    final f = make('secret.txt', utf8.encode('top secret'));
    final s = await serve([f]);
    final base = Uri.parse(await _qrLink(s)).replace(path: '/', query: '');
    final c = phone();
    for (final path in ['/s/abc/f/0', '/s/0/f/0', '/f/0', '/secret.txt', '/../secret.txt', '/s//f/0']) {
      final r = await browse(c, base.resolve(path), follow: false);
      expect(r.$1, anyOf(403, 404), reason: path);
      expect(r.$2, isNot(contains('top secret')), reason: path);
    }
    c.close();
  });

  test('the nearby-list journey: pair request, same code both sides, approve, download', () async {
    final f = make('nearby.txt', utf8.encode('over the air'));
    final s = await serve([f]);
    final qr = Uri.parse(await _qrLink(s));
    final req = s.pairRequests.first;
    final session = await ReceiverClient().requestPair(qr.host, qr.port, poll: const Duration(milliseconds: 20));
    final r = await req;
    expect(session.code, r.code);
    s.approve(r.id);
    final dest = Directory.systemTemp.createTempSync('e2e_nb_');
    addTearDown(() => dest.deleteSync(recursive: true));
    await ReceiverClient().receive((await session.approval)!, dest);
    expect(File('${dest.path}/nearby.txt').readAsStringSync(), 'over the air');
  });

  test('a denied pair request gives no link', () async {
    final f = make('d.txt', utf8.encode('x'));
    final s = await serve([f]);
    final qr = Uri.parse(await _qrLink(s));
    final req = s.pairRequests.first;
    final session = await ReceiverClient().requestPair(qr.host, qr.port, poll: const Duration(milliseconds: 20));
    s.deny((await req).id);
    expect(await session.approval, isNull);
  });

  test('server shuts down by itself after the last file', () async {
    final f = make('bye.txt', utf8.encode('x'));
    final s = await serve([f]);
    final qr = Uri.parse(await _qrLink(s));
    final dest = Directory.systemTemp.createTempSync('e2e_bye_');
    addTearDown(() => dest.deleteSync(recursive: true));
    await ReceiverClient().receive(qr.replace(queryParameters: {'fp': id.fingerprint}), dest);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await expectLater(phone().getUrl(qr).then((r) => r.close()), throwsA(isA<SocketException>()));
  });
}

/// The secure link a QR would carry (https, token, fingerprint).
Future<String> _qrLink(SenderServer s) async => s.link!.toString();

String sha(List<int> b) => sha256.convert(b).toString();
