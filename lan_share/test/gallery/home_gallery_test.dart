// Renders the laptop home at several window sizes for visual review.
// Run:  GALLERY_OUT=<dir> flutter test test/gallery/home_gallery_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/ui/home_view.dart';
import 'package:lan_share/ui/theme.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(File(f).readAsBytesSync()))));
  }
  await loader.load();
}

void main() {
  final out = Platform.environment['GALLERY_OUT'];
  final root = Platform.environment['FLUTTER_ROOT'];

  testWidgets('render home gallery', (t) async {
    if (out == null || root == null) return;
    final fonts = '$root/bin/cache/artifacts/material_fonts';
    await _font('MaterialIcons', ['$fonts/materialicons-regular.otf']);
    await _font('Roboto', ['$fonts/roboto-regular.ttf', '$fonts/roboto-bold.ttf', '$fonts/roboto-black.ttf', '$fonts/roboto-medium.ttf']);
    Directory(out).createSync(recursive: true);
    addTearDown(t.view.reset);
    t.view.devicePixelRatio = 1;

    void noop() {}
    final sizes = {'wide': const Size(1280, 800), 'snap': const Size(560, 760), 'tiny': const Size(360, 640)};
    final states = <String, HomeView>{
      'idle': HomeView(dragging: false, onPick: noop, onReceive: noop, onPhoneApp: noop, showPhoneApp: true, assistOn: true, onToggleAssist: noop, onToggleFast: noop, address: '192.168.1.3'),
      'fast': HomeView(dragging: false, onPick: noop, onReceive: noop, onPhoneApp: noop, showPhoneApp: true, assistOn: true, onToggleAssist: noop, fastOn: true, onToggleFast: noop, address: '192.168.1.3'),
      'drag': HomeView(dragging: true, onPick: noop, onReceive: noop, onPhoneApp: noop, showPhoneApp: true, assistOn: true, onToggleAssist: noop, address: '192.168.1.3'),
      'offline': HomeView(dragging: false, onPick: noop, onReceive: noop, showPhoneApp: false, assistOn: false, onToggleAssist: noop, address: null),
    };
    for (final theme in {'dark': appTheme(), 'light': lightTheme()}.entries) {
      for (final sz in sizes.entries) {
        for (final st in states.entries) {
          t.view.physicalSize = sz.value;
          final key = GlobalKey();
          await t.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.value,
            home: Scaffold(body: RepaintBoundary(key: key, child: st.value)),
          ));
          await t.runAsync(() async {
            await precacheImage(const AssetImage('assets/logo.png'), key.currentContext!);
          });
          await t.pump(const Duration(milliseconds: 300));
          await t.pump(const Duration(milliseconds: 900));
          await t.runAsync(() async {
            final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final img = await b.toImage(pixelRatio: 1);
            final data = await img.toByteData(format: ui.ImageByteFormat.png);
            File('$out/h_${theme.key}_${sz.key}_${st.key}.png').writeAsBytesSync(data!.buffer.asUint8List());
          });
        }
      }
    }
  });
}
