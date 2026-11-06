import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/hotspot.dart';
import 'package:lan_share/core/qr_payload.dart';

final link = Uri.parse('https://192.168.1.3:53270/abcdef0123?fp=${'a' * 64}');

void main() {
  test('without a hotspot the QR is just the normal link', () {
    expect(qrPayload(link), link.toString());
  });

  test('with a hotspot the link gains a fragment browsers ignore', () {
    final text = qrPayload(link, hotspot: const HotspotInfo('LANShare-x28r', 'ccVHpZkSvJqL', '192.168.137.1', true));
    expect(text, startsWith(link.toString()));
    final u = Uri.parse(text);
    expect(u.hasFragment, isTrue);
    expect(text.substring(0, text.indexOf('#')), link.toString(),
        reason: 'everything before the fragment is unchanged');
    expect(u.path, link.path);
    expect(u.queryParameters['fp'], 'a' * 64);
  });

  test('round trip', () {
    const hs = HotspotInfo('LANShare-x28r', 'ccVHpZkSvJqL', '192.168.137.1', true);
    final back = parseQrPayload(qrPayload(link, hotspot: hs))!;
    expect(back.link.toString(), link.toString());
    expect(back.hotspot!.ssid, 'LANShare-x28r');
    expect(back.hotspot!.pass, 'ccVHpZkSvJqL');
    expect(back.hotspot!.ip, '192.168.137.1');
    expect(back.hotspotLink!.host, '192.168.137.1');
    expect(back.hotspotLink!.port, 53270);
    expect(back.hotspotLink!.path, link.path);
    expect(back.hotspotLink!.queryParameters['fp'], 'a' * 64);
  });

  test('names and passwords with awkward characters survive', () {
    for (final (ssid, pass) in [
      ('My Net & Co #1', 'p=ss&w#rd 100%+é'),
      ('名前', 'пароль'),
      ('a;b,c:d\e"f', '"quoted"'),
    ]) {
      final back = parseQrPayload(qrPayload(link, hotspot: HotspotInfo(ssid, pass, '192.168.137.1', true)))!;
      expect(back.hotspot!.ssid, ssid);
      expect(back.hotspot!.pass, pass);
    }
  });

  test('a plain link parses with no hotspot', () {
    final back = parseQrPayload(link.toString())!;
    expect(back.hotspot, isNull);
    expect(back.hotspotLink, isNull);
    expect(back.link.toString(), link.toString());
  });

  test('anything else is not ours', () {
    expect(parseQrPayload(''), isNull);
    expect(parseQrPayload('hello'), isNull);
    expect(parseQrPayload('WIFI:T:WPA;S:x;P:y;;'), isNull);
    expect(parseQrPayload('https://'), isNull);
    expect(parseQrPayload('ftp://192.168.1.3/x'), isNull);
  });

  test('a fragment with a half-filled hotspot is ignored, not trusted', () {
    final u = '${link.toString()}#hs=onlyname';
    final back = parseQrPayload(u)!;
    expect(back.hotspot, isNull);
  });
}
