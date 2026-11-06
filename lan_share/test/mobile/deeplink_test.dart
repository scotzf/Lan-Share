import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/hotspot.dart';
import 'package:lan_share/core/qr_payload.dart';
import 'package:lan_share/mobile/mobile_app.dart';

void main() {
  final link = Uri.parse('https://192.168.1.3:53270/tok?fp=${'a' * 64}');
  final text = qrPayload(link, hotspot: const HotspotInfo('LANShare-x28r', 'ccVH pS&', '192.168.137.1', true));

  test('a receive route carries the QR text back out intact', () {
    final route = Uri(path: '/receive', queryParameters: {'u': text}).toString();
    expect(shareFromRoute(route), text);
  });

  test('the full lanshare:// link from the Android launcher also works', () {
    final deep = Uri(scheme: 'lanshare', host: 'receive', queryParameters: {'u': text});
    // Flutter passes path + query of the deep link as the route
    final route = '/receive?${deep.query}';
    expect(shareFromRoute(route), text);
  });

  test('anything else is not a share', () {
    expect(shareFromRoute('/'), isNull);
    expect(shareFromRoute('/receive'), isNull);
    expect(shareFromRoute('/receive?u='), isNull);
    expect(shareFromRoute('/other?u=x'), isNull);
    expect(shareFromRoute('::bad::'), isNull);
  });
}
