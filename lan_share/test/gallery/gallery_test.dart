// Renders every screen state to PNG for visual review.
// Run:  GALLERY_OUT=<dir> flutter test test/gallery
// Without GALLERY_OUT the test does nothing.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/ui/home_view.dart';
import 'package:lan_share/ui/send_view.dart';
import 'package:lan_share/ui/theme.dart';
import 'package:lan_share/ui/transfer_ring.dart';

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

  testWidgets('render gallery', (t) async {
    if (out == null || root == null) return;
    final fonts = '$root/bin/cache/artifacts/material_fonts';
    await _font('MaterialIcons', ['$fonts/materialicons-regular.otf']);
    await _font('Roboto', [
      '$fonts/roboto-regular.ttf',
      '$fonts/roboto-bold.ttf',
      '$fonts/roboto-black.ttf',
      '$fonts/roboto-light.ttf',
    ]);
    Directory(out).createSync(recursive: true);
    t.view.physicalSize = const Size(420 * 2, 760 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);

    final link = Uri.parse('https://192.168.1.3:53270/abc?fp=${'a' * 64}');
    const names = ['Holiday photo.png', 'Trip video.mp4', 'Report.pdf'];
    void noop() {}
    final states = <String, Widget Function()>{
      'home': () => const HomeView(dragging: false),
      'home_drag': () => const HomeView(dragging: true),
      'qr': () => SendView(phase: Phase.waiting, link: link, fileCount: 3, fileNames: names, accessCode: '482915', remaining: .7, onToggleManual: noop, onClose: noop),
      'manual': () => SendView(phase: Phase.waiting, link: link, fileCount: 3, fileNames: names, accessCode: '482915', manualAddress: '192.168.1.3', showManual: true, onToggleManual: noop, onClose: noop),
      'pair': () => SendView(phase: Phase.waiting, link: link, fileCount: 3, fileNames: names, pairCode: '4821', onApprove: noop, onDeny: noop, onClose: noop),
      'active': () => SendView(phase: Phase.active, link: link, fileCount: 3, fileNames: names, fraction: .62, onClose: noop),
      'done': () => SendView(phase: Phase.done, link: null, fileCount: 3, fileNames: names, onClose: noop),
      'failed': () => SendView(phase: Phase.failed, link: null, fileCount: 3, fileNames: names, onRetry: noop, onClose: noop),
      'expired': () => SendView(phase: Phase.expired, link: null, fileCount: 3, fileNames: names, onRefresh: noop, onClose: noop),
      'hs_starting': () => SendView(phase: Phase.waiting, link: link, fileCount: 3, fileNames: names, accessCode: '482915', hotspot: HotspotUi.starting, onToggleHotspot: noop, onToggleManual: noop, onClose: noop),
      'hs_join': () => SendView(phase: Phase.waiting, link: link, fileCount: 3, fileNames: names, accessCode: '482915', hotspot: HotspotUi.joining, wifiQr: 'WIFI:T:WPA;S:LANShare-58U3;P:ccVHpZkSvJqL;;', hotspotName: 'LANShare-58U3', hotspotPass: 'ccVHpZkSvJqL', onToggleHotspot: noop, onToggleManual: noop, onClose: noop),
      'hs_wifi': () => SendView(phase: Phase.waiting, link: link, fileCount: 3, fileNames: names, accessCode: '482915', showManual: true, hotspot: HotspotUi.joining, wifiQr: 'x', hotspotName: 'LANShare-58U3', hotspotPass: 'ccVHpZkSvJqL', onToggleHotspot: noop, onToggleManual: noop, onClose: noop),
      'hs_ready': () => SendView(phase: Phase.waiting, link: link, fileCount: 3, fileNames: names, accessCode: '482915', remaining: .9, hotspot: HotspotUi.ready, onToggleHotspot: noop, onToggleManual: noop, onClose: noop),
      'offline': () => SendView(phase: Phase.offline, link: null, fileCount: 3, fileNames: names, onRetry: noop, onClose: noop),
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
        await t.pump(const Duration(milliseconds: 900));
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
