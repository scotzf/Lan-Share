// Renders every phone screen state to PNG for visual review.
// Run:  GALLERY_OUT=<dir> flutter test test/gallery/mobile_gallery_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/mobile/receive_flow.dart';
import 'package:lan_share/mobile/receive_view.dart';
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

  testWidgets('render phone gallery', (t) async {
    if (out == null || root == null) return;
    final fonts = '$root/bin/cache/artifacts/material_fonts';
    await _font('MaterialIcons', ['$fonts/materialicons-regular.otf']);
    await _font('Roboto', ['$fonts/roboto-regular.ttf', '$fonts/roboto-bold.ttf', '$fonts/roboto-black.ttf', '$fonts/roboto-medium.ttf']);
    Directory(out).createSync(recursive: true);
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);

    void noop() {}
    const names = ['Holiday photo.png', 'Trip video.mp4', 'Report.pdf'];
    final states = <String, Widget Function()>{
      'm_home': () => MobileHomeView(onScan: noop),
      'm_connecting': () => ReceiveView(phase: FlowPhase.connecting, onClose: noop),
      'm_joining': () => ReceiveView(phase: FlowPhase.joining, onClose: noop),
      'm_downloading': () => ReceiveView(phase: FlowPhase.downloading, fraction: .62, speedMBps: 12.4, onClose: noop),
      'm_done': () => ReceiveView(phase: FlowPhase.done, fraction: 1, names: names, fileCount: 3, totalBytes: 12 * 1024 * 1024, onOpen: noop, onDone: noop, onClose: noop),
      'm_failed': () => ReceiveView(phase: FlowPhase.failed, problem: FlowProblem.unreachable, onScan: noop, onClose: noop),
      'm_join_refused': () => ReceiveView(phase: FlowPhase.failed, problem: FlowProblem.join, onScan: noop, onClose: noop),
      'm_offline': () => ReceiveView(phase: FlowPhase.offline, onScan: noop, onClose: noop),
      'm_invalid': () => ReceiveView(phase: FlowPhase.invalid, onScan: noop, onClose: noop),
    };

    for (final theme in {'dark': appTheme(), 'light': lightTheme()}.entries) {
      for (final s in states.entries) {
        final key = GlobalKey();
        await t.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.value,
          home: Scaffold(body: RepaintBoundary(key: key, child: s.value())),
        ));
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 1000));
        await t.runAsync(() async {
          final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: 1);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/${theme.key}_${s.key}.png').writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
    }
  });
}
