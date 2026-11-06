import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/ui/home_view.dart';
import 'package:lan_share/ui/theme.dart';

Widget host(Widget w, {ThemeData? theme}) =>
    MaterialApp(theme: theme ?? appTheme(), home: Scaffold(body: w));

void main() {
  testWidgets('drop zone and receive button are present, tapping works', (t) async {
    var picked = 0, received = 0;
    await t.pumpWidget(host(HomeView(
        dragging: false, onPick: () => picked++, onReceive: () => received++)));
    expect(find.byKey(const Key('drop')), findsOneWidget);
    await t.tap(find.byKey(const Key('drop')));
    await t.tap(find.byKey(const Key('receive')));
    expect(picked, 1);
    expect(received, 1);
  });

  testWidgets('dragging changes the icon so the zone reacts', (t) async {
    await t.pumpWidget(host(const HomeView(dragging: false)));
    expect(find.byIcon(Icons.north_rounded), findsOneWidget);
    await t.pumpWidget(host(const HomeView(dragging: true)));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('no text on the drop zone, receive label is one word', (t) async {
    await t.pumpWidget(host(const HomeView(dragging: false)));
    final texts = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList();
    expect(texts, ['Receive']);
  });

  testWidgets('renders in light theme too', (t) async {
    await t.pumpWidget(host(const HomeView(dragging: false), theme: lightTheme()));
    expect(find.byKey(const Key('drop')), findsOneWidget);
    expect(Pal.of(t.element(find.byKey(const Key('drop')))).bg, Pal.light.bg);
  });
}
