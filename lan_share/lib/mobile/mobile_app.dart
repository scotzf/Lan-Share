import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../ui/theme.dart';
import 'native.dart';
import 'net.dart';
import 'receive_flow.dart';
import 'receive_view.dart';
import 'scan_page.dart';

/// The Android app: scan once, it works out how to reach the laptop and downloads.
class MobileApp extends StatelessWidget {
  const MobileApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LAN Share',
        debugShowCheckedModeBanner: false,
        theme: lightTheme(),
        darkTheme: appTheme(),
        themeMode: ThemeMode.system,
        // lanshare://receive?u=<qr text> opens straight into a share (links, tests)
        onGenerateInitialRoutes: (name) {
          final routes = <Route<dynamic>>[MaterialPageRoute(builder: (_) => const _MobileHome())];
          final text = shareFromRoute(name);
          if (text != null) {
            routes.add(MaterialPageRoute(builder: (_) => MobileReceiveScreen(qrText: text)));
          }
          return routes;
        },
      );
}

/// The QR text carried by a `/receive?u=...` route, or null for any other route.
String? shareFromRoute(String route) {
  final u = Uri.tryParse(route);
  if (u == null || u.path != '/receive') return null;
  final text = u.queryParameters['u'];
  return text == null || text.isEmpty ? null : text;
}

class _MobileHome extends StatelessWidget {
  const _MobileHome();

  /// Scan, receive, and loop back to the scanner when the screen asks to scan again.
  Future<void> _scan(BuildContext context) async {
    var again = true;
    while (again && context.mounted) {
      final text = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
      if (text == null || !context.mounted) return;
      final result = await Navigator.of(context)
          .push<String>(MaterialPageRoute(builder: (_) => MobileReceiveScreen(qrText: text)));
      again = result == 'scan';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: MobileHomeView(onScan: () => _scan(context)));
}

/// Runs one share with the real network and Android helpers.
class MobileReceiveScreen extends StatefulWidget {
  const MobileReceiveScreen({super.key, required this.qrText});
  final String qrText;

  @override
  State<MobileReceiveScreen> createState() => _MobileReceiveScreenState();
}

class _MobileReceiveScreenState extends State<MobileReceiveScreen> {
  late final NativeBridge _native = NativeBridge();
  late final ReceiveFlow _flow;
  Directory? _cache;
  FlowPhase _last = FlowPhase.idle;

  @override
  void initState() {
    super.initState();
    _flow = ReceiveFlow(
      probe: probeLink,
      wifi: _native,
      download: (link, onProgress) async {
        _cache = await Directory('${(await getTemporaryDirectory()).path}/lanshare_rx')
            .create(recursive: true);
        return downloadLink(link, onProgress, _cache!);
      },
      save: _native.saveToDownloads,
    )..addListener(_changed);
    _flow.run(widget.qrText);
  }

  void _changed() {
    if (!mounted) return;
    if (_flow.phase != _last) {
      // the peak moment: a firm tick when the files are in
      if (_flow.phase == FlowPhase.done) HapticFeedback.heavyImpact();
      if (_flow.phase == FlowPhase.failed) HapticFeedback.vibrate();
      if (_flow.phase == FlowPhase.done || _flow.phase == FlowPhase.failed) _clearCache();
      _last = _flow.phase;
    }
    setState(() {});
  }

  /// The copies in the app's cache are no longer needed once saved to Downloads.
  void _clearCache() {
    final c = _cache;
    if (c != null && c.existsSync()) {
      try {
        c.deleteSync(recursive: true);
      } catch (_) {
        // the system cleans the cache folder anyway
      }
    }
  }

  @override
  void dispose() {
    _flow.removeListener(_changed);
    _flow.cancel();
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ReceiveView(
          phase: _flow.phase,
          problem: _flow.problem,
          fraction: _flow.fraction,
          speedMBps: _flow.speedMBps,
          names: _flow.names,
          fileCount: _flow.fileCount,
          totalBytes: _flow.totalBytes,
          onOpen: _native.openDownloads,
          onDone: () => Navigator.of(context).pop(),
          onScan: () => Navigator.of(context).pop('scan'),
          onClose: () => Navigator.of(context).pop(),
        ),
      );
}
