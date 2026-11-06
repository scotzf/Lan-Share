import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/ui/file_chips.dart';
import 'package:lan_share/ui/send_view.dart';
import 'package:lan_share/ui/theme.dart';
import 'package:lan_share/ui/transfer_ring.dart';

Widget host(Widget w) => MaterialApp(theme: appTheme(), home: Scaffold(body: w));

void main() {
  manualTests();
  test('file types get their own icon and colour', () {
    expect(fileLook('a.PNG').$2, C.violet);
    expect(fileLook('a.mp4').$2, C.red);
    expect(fileLook('a.pdf').$1, Icons.picture_as_pdf_rounded);
    expect(fileLook('a.zip').$2, C.amber);
    expect(fileLook('noext').$1, Icons.insert_drive_file_rounded);
    expect(fileLook('a.docx').$2, C.blue);
  });

  testWidgets('chips show at most three tiles and the full count', (t) async {
    await t.pumpWidget(host(const FileChips(
        names: ['a.png', 'b.mp4', 'c.pdf', 'd.zip', 'e.txt'], count: 5, color: C.blue)));
    expect(find.text('5'), findsOneWidget);
    expect(find.byIcon(Icons.image_rounded), findsOneWidget);
    expect(find.byIcon(Icons.folder_zip_rounded), findsNothing);
  });

  testWidgets('waiting QR renders with names and low remaining time', (t) async {
    await t.pumpWidget(host(SendView(
      phase: Phase.waiting,
      link: Uri.parse('https://192.168.1.5:4000/abc?fp=${'a' * 64}'),
      fileCount: 2,
      fileNames: const ['x.png', 'y.pdf'],
      remaining: .1,
    )));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('qr')), findsOneWidget);
    expect(tester(t), isNull);
  });
}

Object? tester(WidgetTester t) => t.takeException();

void manualTests() {
  testWidgets('manual mode shows address and grouped code, toggle hidden when no code', (t) async {
    final link = Uri.parse('https://192.168.1.5:4000/abc?fp=${'a' * 64}');
    await t.pumpWidget(host(SendView(
      phase: Phase.waiting, link: link, fileCount: 1, accessCode: '123456', showManual: true)));
    expect(find.text('192.168.1.5:4000'), findsOneWidget);
    expect(find.text('123 456'), findsOneWidget);
    expect(find.byKey(const Key('qr')), findsNothing);
    expect(find.byKey(const Key('manual')), findsOneWidget);
    expect(find.text('Scan QR'), findsOneWidget);
    await t.pumpWidget(host(SendView(
      phase: Phase.waiting, link: link, fileCount: 1, accessCode: '123456')));
    expect(find.text('No scanner?'), findsOneWidget);
    await t.pumpWidget(host(SendView(phase: Phase.waiting, link: link, fileCount: 1)));
    expect(find.byKey(const Key('manual')), findsNothing);
  });
}
