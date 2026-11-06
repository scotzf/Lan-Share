import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:path_provider/path_provider.dart';

import '../core/discovery.dart';
import '../core/identity.dart';
import '../core/sender_server.dart';
import '../core/token_store.dart';
import 'send_view.dart';
import 'transfer_ring.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, required this.files});
  final List<File> files;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  SenderServer? _server;
  Discovery? _discovery;
  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _expiry;
  Uri? _link;
  Phase _phase = Phase.waiting;
  double _fraction = 0;
  PairRequest? _pair;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _teardown();
    setState(() {
      _phase = Phase.waiting;
      _fraction = 0;
      _pair = null;
      _link = null;
    });
    try {
      final identity = await loadOrCreateIdentity(await getApplicationSupportDirectory());
      final server = SenderServer(widget.files, TokenStore(), identity: identity);
      final link = await server.start();
      _server = server;
      _subs.add(server.progress.listen(_onProgress));
      _subs.add(server.pairRequests.listen((r) {
        if (mounted) setState(() => _pair = r);
      }));
      try {
        _discovery = Discovery(await UdpBeaconTransport.open());
        await _discovery!.advertise(Platform.localHostname, link.port);
      } catch (_) {
        // QR still works without nearby discovery
      }
      _expiry = Timer(const Duration(minutes: 5), () {
        if (mounted && _phase == Phase.waiting) setState(() => _phase = Phase.expired);
      });
      if (mounted) setState(() => _link = link);
    } catch (_) {
      if (mounted) setState(() => _phase = Phase.failed);
    }
  }

  void _onProgress(TransferProgress p) {
    if (!mounted) return;
    setState(() {
      _pair = null;
      switch (p.state) {
        case TransferState.active:
          _phase = Phase.active;
          _fraction = p.fraction;
        case TransferState.done:
          _phase = Phase.done;
        case TransferState.failed:
          _phase = Phase.failed;
      }
    });
  }

  Future<void> _teardown() async {
    _expiry?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _discovery?.stop();
    _discovery = null;
    await _server?.stop();
    _server = null;
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SendView(
          phase: _phase,
          link: _link,
          fileCount: widget.files.length,
          fraction: _fraction,
          pairCode: _pair?.code,
          onApprove: () {
            _server?.approve(_pair!.id);
            setState(() => _pair = null);
          },
          onDeny: () {
            _server?.deny(_pair!.id);
            setState(() => _pair = null);
          },
          onRefresh: _start,
          onRetry: _start,
          onClose: () => Navigator.of(context).pop(),
        ),
      );
}
