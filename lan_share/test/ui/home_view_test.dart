import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/ui/home_view.dart';
import 'package:lan_share/ui/theme.dart';

Widget host(Widget w, {ThemeData? theme}) =>
    MaterialApp(theme: theme ?? appTheme(), home: Scaffold(body: w));

void setSize(WidgetTester t, double w, double h) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// The real Roboto font, so text widths in these tests match what a person sees
/// (the test default is a wide placeholder font).
Future<void> loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final fonts = '$root/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-bold.ttf', 'roboto-black.ttf', 'roboto-medium.ttf']) {
    final file = File('$fonts/$f');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(file.readAsBytesSync()))));
  }
  await loader.load();
}

void main() {
  setUpAll(loadRoboto);
  labelTests();
  testWidgets('drop card, Choose button, Receive tile are all there and work', (t) async {
    var picked = 0, received = 0;
    await t.pumpWidget(host(HomeView(
        dragging: false, onPick: () => picked++, onReceive: () => received++)));
    expect(find.byKey(const Key('drop')), findsOneWidget);
    await t.tap(find.byKey(const Key('choose')));
    await t.tap(find.byKey(const Key('receive')));
    expect(picked, 1, reason: 'the visible Choose button is a real way in, not just decoration');
    expect(received, 1);
    expect(find.text('Drop or choose'), findsOneWidget);
    expect(find.text('Choose'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
  });

  testWidgets('clicking the card itself also opens the picker', (t) async {
    var picked = 0;
    await t.pumpWidget(host(HomeView(dragging: false, onPick: () => picked++)));
    await t.tapAt(t.getTopLeft(find.byKey(const Key('drop'))) + const Offset(24, 24));
    expect(picked, 1);
  });

  testWidgets('dragging: the zone says Drop, switches colour and icon', (t) async {
    await t.pumpWidget(host(const HomeView(dragging: false)));
    expect(find.text('Drop or choose'), findsOneWidget);
    expect(find.byIcon(Icons.north_rounded), findsOneWidget);
    await t.pumpWidget(host(const HomeView(dragging: true)));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Drop'), findsOneWidget);
    expect(find.text('Drop or choose'), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('phone-app tile only appears when the Android app is available', (t) async {
    var taps = 0;
    await t.pumpWidget(host(const HomeView(dragging: false)));
    expect(find.byKey(const Key('phoneApp')), findsNothing);
    await t.pumpWidget(host(HomeView(dragging: false, showPhoneApp: true, onPhoneApp: () => taps++)));
    expect(find.text('Phone app'), findsOneWidget);
    await t.tap(find.byKey(const Key('phoneApp')));
    expect(taps, 1);
  });

  testWidgets('status chips: hotspot assist toggles, address shows the network', (t) async {
    var toggles = 0;
    await t.pumpWidget(host(HomeView(
        dragging: false, assistOn: true, onToggleAssist: () => toggles++, address: '192.168.1.3')));
    expect(find.text('192.168.1.3'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_tethering), findsOneWidget);
    await t.tap(find.byKey(const Key('assist')));
    expect(toggles, 1);
    await t.pumpWidget(host(HomeView(dragging: false, assistOn: false, onToggleAssist: () {}, address: null)));
    expect(find.byIcon(Icons.wifi_tethering_off), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
  });

  testWidgets('every text is at most three words, in both themes', (t) async {
    for (final theme in [appTheme(), lightTheme()]) {
      await t.pumpWidget(host(
          HomeView(dragging: false, showPhoneApp: true, assistOn: true, address: '192.168.1.3'),
          theme: theme));
      for (final w in t.widgetList<Text>(find.byType(Text))) {
        expect((w.data ?? '').trim().split(RegExp(r'\s+')).length, lessThanOrEqualTo(3), reason: w.data);
      }
    }
  });

  testWidgets('fluid layout: no overflow from quarter-snap to 4K, and the content stays in a column', (t) async {
    for (final (w, h) in [(360.0, 640.0), (480.0, 780.0), (640.0, 480.0), (1280.0, 800.0), (1920.0, 1080.0), (3840.0, 2160.0)]) {
      setSize(t, w, h);
      for (final theme in [appTheme(), lightTheme()]) {
        await t.pumpWidget(host(
            HomeView(dragging: false, showPhoneApp: true, assistOn: true, address: '192.168.1.3'),
            theme: theme));
        await t.pump(const Duration(milliseconds: 500));
        expect(t.takeException(), isNull, reason: '${w}x$h');
        final card = t.getSize(find.byKey(const Key('drop')));
        expect(card.width, lessThanOrEqualTo(560), reason: 'content column is capped at ${w}x$h');
        expect(card.height, greaterThan(160), reason: 'not squashed');
        expect(card.height, lessThanOrEqualTo(360), reason: 'never a huge empty zone');
      }
    }
  });

  testWidgets('a short window scrolls instead of overflowing', (t) async {
    setSize(t, 480, 420);
    await t.pumpWidget(host(HomeView(dragging: false, showPhoneApp: true, assistOn: true, address: '192.168.1.3')));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
  });

  testWidgets('light theme renders with the light surface', (t) async {
    await t.pumpWidget(host(const HomeView(dragging: false), theme: lightTheme()));
    expect(Pal.of(t.element(find.byKey(const Key('drop')))).bg, Pal.light.bg);
  });
}

void labelTests() {
  testWidgets('tile labels are never cut off, even in a very narrow window', (t) async {
    for (final w in [320.0, 360.0, 420.0, 560.0, 1280.0]) {
      t.view.physicalSize = Size(w, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(HomeView(dragging: false, showPhoneApp: true, address: '192.168.1.3', assistOn: true, onToggleAssist: () {})));
      await t.pump(const Duration(milliseconds: 400));
      for (final label in ['Receive', 'Phone app']) {
        // the text as rendered (real font, real inherited style): is all of it inside its box?
        final paragraph = t.renderObject<RenderParagraph>(find.text(label));
        final needed = paragraph.getMaxIntrinsicWidth(double.infinity);
        expect(paragraph.size.width, greaterThanOrEqualTo(needed - 1), reason: '"$label" is clipped at width $w');
      }
      expect(t.takeException(), isNull, reason: 'width $w');
    }
  });
}
