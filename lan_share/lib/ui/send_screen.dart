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
  const SendScreen({super.key, required this.files, this.closeApp = false});
  final List<File> files;

  /// Started from the Windows share menu: closing ends the app.
  final bool closeApp;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  SenderServer? _server;
  Discovery? _discovery;
  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _expiry;
  DateTime _expiresAt = DateTime.now();
  double _remaining = 1;
  static const _ttl = Duration(minutes: 5);
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
      _expiresAt = DateTime.now().add(_ttl);
      _remaining = 1;
      _expiry = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _phase != Phase.waiting) return;
        final left = _expiresAt.difference(DateTime.now());
        setState(() {
          _remaining = left.inMilliseconds / _ttl.inMilliseconds;
          if (left <= Duration.zero) _phase = Phase.expired;
        });
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

  Future<void> _close() async {
    if (widget.closeApp) {
      await _teardown();
      exit(0);
    }
    if (mounted) Navigator.of(context).pop();
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
          fileNames: [for (final f in widget.files) f.uri.pathSegments.last],
          remaining: _remaining,
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
          onClose: _close,
        ),
      );
}
