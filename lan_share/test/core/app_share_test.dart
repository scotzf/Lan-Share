import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/app_share.dart';
import 'package:lan_share/core/identity.dart';

HttpClient phone() => HttpClient()..badCertificateCallback = (_, __, ___) => true;

void main() {
  late Directory dir, idDir;
  late Identity id;
  setUpAll(() async {
    idDir = Directory.systemTemp.createTempSync('as_id_');
    id = await loadOrCreateIdentity(idDir);
  });
  tearDownAll(() => idDir.deleteSync(recursive: true));
  setUp(() => dir = Directory.systemTemp.createTempSync('as_'));
  tearDown(() => dir.deleteSync(recursive: true));

  File apk([List<int>? bytes]) => File('${dir.path}/lanshare.apk')..writeAsBytesSync(bytes ?? List.generate(40000, (i) => i % 251));

  test('start gives a secure link to the app file and the file downloads intact', () async {
    final f = apk();
    final share = AppShare(f, id, bindAddress: InternetAddress.loopbackIPv4);
    addTearDown(share.stop);
    final url = await share.start();
    expect(url.scheme, 'https');
    expect(url.path, '/app.apk');
    final c = phone();
    final r = await (await c.getUrl(url)).close();
    expect(r.statusCode, 200);
    final b = BytesBuilder();
    await for (final chunk in r) {
      b.add(chunk);
    }
    expect(b.takeBytes(), f.readAsBytesSync());
    c.close();
  });

  test('the same link comes back if started twice (no second server)', () async {
    final share = AppShare(apk(), id, bindAddress: InternetAddress.loopbackIPv4);
    addTearDown(share.stop);
    final a = await share.start();
    final b = await share.start();
    expect(b.toString(), a.toString());
  });

  test('stop closes it: nothing answers afterwards', () async {
    final share = AppShare(apk(), id, bindAddress: InternetAddress.loopbackIPv4);
    final url = await share.start();
    await share.stop();
    await expectLater(phone().getUrl(url).then((r) => r.close()), throwsA(isA<SocketException>()));
    await share.stop(); // safe twice
  });

  test('can start again after stopping', () async {
    final share = AppShare(apk(), id, bindAddress: InternetAddress.loopbackIPv4);
    addTearDown(share.stop);
    await share.start();
    await share.stop();
    final url = await share.start();
    final r = await (await phone().getUrl(url)).close();
    await r.drain<void>();
    expect(r.statusCode, 200);
  });

  test('without the app file there is nothing to share', () async {
    final share = AppShare(File('${dir.path}/missing.apk'), id, bindAddress: InternetAddress.loopbackIPv4);
    await expectLater(share.start(), throwsA(isA<StateError>()));
  });
}
