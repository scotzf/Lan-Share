import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/ui/app_qr_dialog.dart';
import 'package:lan_share/ui/send_view.dart';
import 'package:lan_share/ui/theme.dart';

final url = Uri.parse('https://192.168.1.3:50123/app.apk');

Widget host(Widget w, {ThemeData? theme}) => MaterialApp(theme: theme ?? appTheme(), home: Scaffold(body: w));

void main() {
  testWidgets('shows a QR of the app link and the short address', (t) async {
    await t.pumpWidget(host(AppQrDialog(url: url)));
    expect(t.widget<QrBox>(find.byType(QrBox)).data, url.toString());
    expect(find.text('192.168.1.3:50123'), findsOneWidget);
    expect(find.byIcon(Icons.phone_android_rounded), findsOneWidget);
  });

  testWidgets('the close button closes the dialog', (t) async {
    await t.pumpWidget(host(Builder(
      builder: (context) => TextButton(
        key: const Key('open'),
        onPressed: () => showDialog<void>(context: context, builder: (_) => AppQrDialog(url: url)),
        child: const Text('x'),
      ),
    )));
    await t.tap(find.byKey(const Key('open')));
    await t.pumpAndSettle();
    expect(find.byType(AppQrDialog), findsOneWidget);
    await t.tap(find.byKey(const Key('close')));
    await t.pumpAndSettle();
    expect(find.byType(AppQrDialog), findsNothing);
  });

  testWidgets('fits a small window and both themes, text stays short', (t) async {
    t.view.physicalSize = const Size(360, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    for (final theme in [appTheme(), lightTheme()]) {
      await t.pumpWidget(host(AppQrDialog(url: url), theme: theme));
      expect(t.takeException(), isNull);
      for (final w in t.widgetList<Text>(find.byType(Text))) {
        expect((w.data ?? '').trim().split(RegExp(r'\s+')).length, lessThanOrEqualTo(3));
      }
    }
  });
}
