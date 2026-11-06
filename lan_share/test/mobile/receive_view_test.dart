import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/mobile/receive_flow.dart';
import 'package:lan_share/mobile/receive_view.dart';
import 'package:lan_share/ui/theme.dart';

Widget host(Widget w, {ThemeData? theme}) =>
    MaterialApp(theme: theme ?? appTheme(), home: Scaffold(body: w));

const names = ['Holiday photo.png', 'Trip video.mp4', 'Report.pdf'];

void main() {
  testWidgets('home: one hero and one big Scan button', (t) async {
    var taps = 0;
    await t.pumpWidget(host(MobileHomeView(onScan: () => taps++)));
    expect(find.byKey(const Key('hero')), findsOneWidget);
    await t.tap(find.byKey(const Key('scan')));
    expect(taps, 1);
    expect(find.text('Scan'), findsOneWidget);
    final size = t.getSize(find.byKey(const Key('scan')));
    expect(size.height, greaterThanOrEqualTo(48), reason: 'comfortable tap target');
    // the main action sits in the bottom third of the screen
    final y = t.getCenter(find.byKey(const Key('scan'))).dy;
    expect(y, greaterThan(t.view.physicalSize.height / t.view.devicePixelRatio * .66));
  });

  testWidgets('connecting and joining show a spinning ring, no buttons', (t) async {
    for (final p in [FlowPhase.connecting, FlowPhase.joining]) {
      await t.pumpWidget(host(ReceiveView(phase: p)));
      expect(find.byKey(const Key('ring')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.byKey(const Key('open')), findsNothing);
      expect(find.byKey(const Key('scan')), findsNothing);
    }
  });

  testWidgets('downloading: big percentage in the ring and the speed under it', (t) async {
    await t.pumpWidget(host(const ReceiveView(phase: FlowPhase.downloading, fraction: .62, speedMBps: 12.46)));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('12.5 MB/s'), findsOneWidget);
    await t.pumpWidget(host(const ReceiveView(phase: FlowPhase.downloading, fraction: .999)));
    expect(find.text('99%'), findsOneWidget, reason: 'never claims 100% before it is done');
    expect(find.textContaining('MB/s'), findsNothing);
  });

  testWidgets('done: green check, no percentage, files and size, Open and Done', (t) async {
    var opened = 0, done = 0;
    await t.pumpWidget(host(ReceiveView(
      phase: FlowPhase.done, fraction: 1, names: names, fileCount: 3, totalBytes: 12 * 1024 * 1024,
      onOpen: () => opened++, onDone: () => done++,
    )));
    await t.pump(const Duration(milliseconds: 900));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.textContaining('%'), findsNothing, reason: 'no numbers in a success state');
    expect(find.text('3'), findsOneWidget);
    expect(find.text('12.0 MB'), findsOneWidget);
    await t.tap(find.byKey(const Key('open')));
    await t.tap(find.byKey(const Key('done')));
    expect((opened, done), (1, 1));
  });

  testWidgets('failures show a different icon for each cause and one Scan button', (t) async {
    final icons = <FlowProblem, IconData>{
      FlowProblem.join: Icons.wifi_password_rounded,
      FlowProblem.unreachable: Icons.portable_wifi_off_rounded,
      FlowProblem.transfer: Icons.close_rounded,
      FlowProblem.save: Icons.folder_off_rounded,
    };
    for (final e in icons.entries) {
      var scans = 0;
      await t.pumpWidget(host(ReceiveView(phase: FlowPhase.failed, problem: e.key, onScan: () => scans++)));
      expect(find.byIcon(e.value), findsOneWidget, reason: '${e.key}');
      await t.tap(find.byKey(const Key('scan')));
      expect(scans, 1);
    }
  });

  testWidgets('offline and not-our-code states each have their own icon and Scan', (t) async {
    await t.pumpWidget(host(const ReceiveView(phase: FlowPhase.offline)));
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.byKey(const Key('scan')), findsOneWidget);
    await t.pumpWidget(host(const ReceiveView(phase: FlowPhase.invalid)));
    expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
    expect(find.byKey(const Key('scan')), findsOneWidget);
  });

  testWidgets('every state keeps all text to three words, in both themes', (t) async {
    for (final theme in [appTheme(), lightTheme()]) {
      for (final p in FlowPhase.values) {
        await t.pumpWidget(host(
          ReceiveView(phase: p, problem: FlowProblem.join, fraction: .4, speedMBps: 3, names: names, fileCount: 3, totalBytes: 5000),
          theme: theme,
        ));
        for (final w in t.widgetList<Text>(find.byType(Text))) {
          expect((w.data ?? '').trim().split(RegExp(r'\s+')).length, lessThanOrEqualTo(3), reason: '$p');
        }
      }
    }
  });

  testWidgets('fits a small 360x640 phone without overflow', (t) async {
    t.view.physicalSize = const Size(360 * 2, 640 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    for (final p in FlowPhase.values) {
      await t.pumpWidget(host(ReceiveView(
          phase: p, fraction: .5, speedMBps: 9, names: names, fileCount: 3, totalBytes: 12 << 20)));
      await t.pump(const Duration(milliseconds: 800));
      expect(t.takeException(), isNull, reason: '$p');
    }
    await t.pumpWidget(host(const MobileHomeView()));
    expect(t.takeException(), isNull);
  });
}
