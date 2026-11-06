import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/ui/send_view.dart';
import 'package:lan_share/ui/theme.dart';
import 'package:lan_share/ui/transfer_ring.dart';

Widget host(Widget w) => MaterialApp(theme: appTheme(), home: Scaffold(body: w));
final link = Uri.parse('https://192.168.137.1:4000/abc?fp=${'a' * 64}');
const wifi = 'WIFI:T:WPA;S:LANShare-58U3;P:ccVHpZkSvJqL;;';

SendView view({
  HotspotUi hs = HotspotUi.off,
  bool manual = false,
  VoidCallback? toggle,
}) =>
    SendView(
      phase: Phase.waiting,
      link: link,
      fileCount: 1,
      accessCode: '123456',
      manualAddress: '192.168.137.1',
      showManual: manual,
      hotspot: hs,
      wifiQr: wifi,
      hotspotName: 'LANShare-58U3',
      hotspotPass: 'ccVHpZkSvJqL',
      onToggleHotspot: toggle,
      onToggleManual: () {},
    );

void main() {
  assistTests();
  testWidgets('off: Hotspot button shown and tappable', (t) async {
    var taps = 0;
    await t.pumpWidget(host(view(toggle: () => taps++)));
    expect(find.text('Hotspot'), findsOneWidget);
    await t.tap(find.byKey(const Key('hotspot')));
    expect(taps, 1);
    expect(find.byKey(const Key('qr')), findsOneWidget);
  });

  testWidgets('button hidden when there is no handler', (t) async {
    await t.pumpWidget(host(view()));
    expect(find.byKey(const Key('hotspot')), findsNothing);
  });

  testWidgets('starting: spinner, no QR, button disabled', (t) async {
    await t.pumpWidget(host(view(hs: HotspotUi.starting, toggle: () {})));
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.byKey(const Key('qr')), findsNothing);
    expect(find.byKey(const Key('wifiQr')), findsNothing);
    final b = t.widget<TextButton>(find.byKey(const Key('hotspot')));
    expect(b.onPressed, isNull);
  });

  testWidgets('joining: the QR is the Wi-Fi join code', (t) async {
    await t.pumpWidget(host(view(hs: HotspotUi.joining, toggle: () {})));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('wifiQr')), findsOneWidget);
    expect(find.byKey(const Key('qr')), findsNothing);
    expect(t.widget<QrBox>(find.byType(QrBox)).data, wifi);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('joining + manual: network name and password are shown', (t) async {
    await t.pumpWidget(host(view(hs: HotspotUi.joining, manual: true, toggle: () {})));
    expect(find.text('LANShare-58U3'), findsOneWidget);
    expect(find.text('ccVHpZkSvJqL'), findsOneWidget);
    expect(find.byKey(const Key('manualCode')), findsNothing);
  });

  testWidgets('ready: back to the download QR, address and code in manual', (t) async {
    await t.pumpWidget(host(view(hs: HotspotUi.ready, toggle: () {})));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('qr')), findsOneWidget);
    expect(t.widget<QrBox>(find.byType(QrBox)).data, link.toString());
    await t.pumpWidget(host(view(hs: HotspotUi.ready, manual: true, toggle: () {})));
    expect(find.text('192.168.137.1'), findsOneWidget);
    expect(find.text('123 456'), findsOneWidget);
  });

  testWidgets('hotspot states keep every text to three words', (t) async {
    for (final hs in HotspotUi.values) {
      for (final manual in [false, true]) {
        await t.pumpWidget(host(view(hs: hs, manual: manual, toggle: () {})));
        for (final w in t.widgetList<Text>(find.byType(Text))) {
          expect((w.data ?? '').trim().split(RegExp(r'\s+')).length, lessThanOrEqualTo(3));
        }
      }
    }
  });
}

void assistTests() {
  testWidgets('assist starting in the background keeps the QR visible and the button busy', (t) async {
    await t.pumpWidget(host(SendView(
      phase: Phase.waiting, link: link, fileCount: 1, accessCode: '123456',
      hotspotBusy: true, onToggleHotspot: () {}, onToggleManual: () {},
    )));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('qr')), findsOneWidget, reason: 'LAN users can scan straight away');
    final b = t.widget<TextButton>(find.byKey(const Key('hotspot')));
    expect(b.onPressed, isNull);
  });

  testWidgets('the QR shows the payload given, not just the link', (t) async {
    await t.pumpWidget(host(SendView(
      phase: Phase.waiting, link: link, fileCount: 1, accessCode: '123456',
      hotspot: HotspotUi.ready, qrData: '${link.toString()}#hs=x&hp=y&hip=192.168.137.1',
      onToggleHotspot: () {}, onToggleManual: () {},
    )));
    await t.pump(const Duration(milliseconds: 600));
    expect(t.widget<QrBox>(find.byType(QrBox)).data, endsWith('#hs=x&hp=y&hip=192.168.137.1'));
  });

  testWidgets('Wi-Fi button appears while the hotspot is up and swaps views', (t) async {
    var taps = 0;
    await t.pumpWidget(host(SendView(
      phase: Phase.waiting, link: link, fileCount: 1, accessCode: '123456',
      hotspot: HotspotUi.ready, wifiQr: wifi, onToggleHotspot: () {}, onToggleJoin: () => taps++,
      onToggleManual: () {},
    )));
    expect(find.text('Wi-Fi'), findsOneWidget);
    await t.tap(find.byKey(const Key('wifiToggle')));
    expect(taps, 1);
    await t.pumpWidget(host(SendView(
      phase: Phase.waiting, link: link, fileCount: 1, accessCode: '123456',
      hotspot: HotspotUi.joining, wifiQr: wifi, onToggleHotspot: () {}, onToggleJoin: () {},
      onToggleManual: () {},
    )));
    expect(find.text('Link'), findsOneWidget);
    // and it is hidden when the hotspot is off
    await t.pumpWidget(host(SendView(
      phase: Phase.waiting, link: link, fileCount: 1, accessCode: '123456',
      onToggleHotspot: () {}, onToggleJoin: () {}, onToggleManual: () {},
    )));
    expect(find.byKey(const Key('wifiToggle')), findsNothing);
  });
}
