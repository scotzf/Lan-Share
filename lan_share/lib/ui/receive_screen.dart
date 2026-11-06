import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import '../core/discovery.dart';
import '../core/receiver_client.dart';
import '../core/transfer_progress.dart';
import 'pulse.dart';
import 'theme.dart';
import 'transfer_ring.dart';

Future<Directory> _inbox() async {
  final base = await getDownloadsDirectory() ??
      await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  return Directory('${base.path}${Platform.pathSeparator}LAN Share').create(recursive: true);
}

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});
  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  Discovery? _discovery;
  List<NearbySender> _nearby = [];
  String? _code;
  Phase? _phase;
  double _fraction = 0;
  final _client = ReceiverClient();

  bool get _canScan => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _client.progress.listen((p) {
      if (!mounted) return;
      setState(() {
        _fraction = p.fraction;
        _phase = switch (p.state) {
          TransferState.active => Phase.active,
          TransferState.done => Phase.done,
          TransferState.failed => Phase.failed,
        };
      });
    });
    _listen();
  }

  Future<void> _listen() async {
    try {
      _discovery = Discovery(await UdpBeaconTransport.open());
      _discovery!.nearby().listen((l) {
        if (mounted) setState(() => _nearby = l);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _discovery?.stop();
    super.dispose();
  }

  Future<void> _fetch(Uri link) async {
    setState(() => _phase = Phase.active);
    try {
      await _client.receive(link, await _inbox());
    } catch (_) {
      if (mounted) setState(() => _phase = Phase.failed);
    }
  }

  Future<void> _pairWith(NearbySender s) async {
    try {
      final session = await _client.requestPair(s.host, s.port);
      setState(() => _code = session.code);
      final link = await session.approval;
      setState(() => _code = null);
      if (link == null) return;
      await _fetch(link);
    } catch (_) {
      if (mounted) {
        setState(() {
          _code = null;
          _phase = Phase.failed;
        });
      }
    }
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _ScanPage()));
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) await _fetch(uri);
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_code != null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_code!,
              style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800, letterSpacing: 8)),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ]),
      );
    } else if (_phase != null) {
      body = Center(child: TransferRing(phase: _phase!, fraction: _fraction, size: 220));
    } else {
      body = ListView(padding: const EdgeInsets.all(16), children: [
        if (_nearby.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Pulse(
                color: C.violet,
                size: 280,
                child: Icon(Icons.radar, size: 96, color: C.violet),
              ),
            ),
          ),
        for (final s in _nearby)
          Card(
            color: Pal.of(context).card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: C.violet.withValues(alpha: .25), shape: BoxShape.circle),
                child: const Icon(Icons.devices, color: C.violet),
              ),
              title: Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.south_rounded, color: C.blue),
              onTap: () => _pairWith(s),
            ),
          ),
      ]);
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      ),
      body: body,
      floatingActionButton: _canScan && _code == null && _phase == null
          ? FloatingActionButton.large(
              backgroundColor: C.blue,
              onPressed: _scan,
              child: const Icon(Icons.qr_code_scanner, size: 40))
          : null,
    );
  }
}

class _ScanPage extends StatelessWidget {
  const _ScanPage();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: MobileScanner(
          onDetect: (capture) {
            final v = capture.barcodes.firstOrNull?.rawValue;
            if (v != null) Navigator.of(context).pop(v);
          },
        ),
      );
}
