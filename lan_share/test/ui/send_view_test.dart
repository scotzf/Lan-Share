import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/ui/send_view.dart';
import 'package:lan_share/ui/theme.dart';
import 'package:lan_share/ui/transfer_ring.dart';

Widget host(Widget w) => MaterialApp(theme: appTheme(), home: Scaffold(body: w));
final link = Uri.parse('http://192.168.1.5:4000/abc');

void main() {
  testWidgets('QR shown while waiting', (t) async {
    await t.pumpWidget(host(SendView(phase: Phase.waiting, link: link, fileCount: 2)));
    expect(find.byKey(const Key('qr')), findsOneWidget);
  });
  testWidgets('pair code shown with approve and deny', (t) async {
    await t.pumpWidget(host(SendView(phase: Phase.waiting, link: link, fileCount: 1, pairCode: '4821')));
    expect(find.text('4821'), findsOneWidget);
    expect(find.byKey(const Key('approve')), findsOneWidget);
    expect(find.byKey(const Key('deny')), findsOneWidget);
  });
  testWidgets('done shows check and Done', (t) async {
    await t.pumpWidget(host(const SendView(phase: Phase.done, link: null, fileCount: 1)));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });
  testWidgets('expired shows Refresh', (t) async {
    await t.pumpWidget(host(const SendView(phase: Phase.expired, link: null, fileCount: 1)));
    expect(find.text('Refresh'), findsOneWidget);
  });
  testWidgets('failed shows Retry', (t) async {
    await t.pumpWidget(host(const SendView(phase: Phase.failed, link: null, fileCount: 1)));
    expect(find.text('Retry'), findsOneWidget);
  });
  testWidgets('no visible text longer than 3 words', (t) async {
    for (final p in Phase.values) {
      await t.pumpWidget(host(SendView(phase: p, link: link, fileCount: 3)));
      for (final w in t.widgetList<Text>(find.byType(Text))) {
        expect((w.data ?? '').trim().split(RegExp(r'\s+')).length, lessThanOrEqualTo(3));
      }
    }
  });
}
