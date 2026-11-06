import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/discovery.dart';
import '../core/hotspot.dart';
import '../core/hotspot_runner.dart';
import '../core/identity.dart';
import '../core/lan_address.dart';
import '../core/sender_server.dart';
import '../core/token_store.dart';
import 'send_view.dart';
import 'transfer_ring.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, required this.files, this.closeApp = false, this.hotspotRunner});
  final List<File> files;

  /// Runs the hotspot script; tests swap it to fake a joined phone.
  final ScriptRunner? hotspotRunner;

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
  bool _manual = false;

  late final Hotspot _hotspot;
  HotspotUi _hsUi = HotspotUi.off;
  HotspotInfo? _hsInfo;
  Timer? _hsPoll;
  bool _polling = false;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _hotspot = Hotspot(widget.hotspotRunner ?? powershellRunner);
    // closing the window must not leave the hotspot on
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      await _hotspot.stop();
      return AppExitResponse.exit;
    });
    _start();
  }

  Future<void> _start() async {
    await _teardownServer();
    setState(() {
      _phase = Phase.waiting;
      _fraction = 0;
      _pair = null;
      _link = null;
      _manual = false;
    });
    final onHotspot = _hsInfo != null;
    // No Wi-Fi or LAN: a QR pointing at this machine alone would be useless.
    if (!onHotspot && (await pickLanAddress()).isLoopback) {
      if (mounted) setState(() => _phase = Phase.offline);
      return;
    }
    try {
      final identity = await loadOrCreateIdentity(await getApplicationSupportDirectory());
      final server = SenderServer(
        widget.files,
        TokenStore(),
        identity: identity,
        bindAddress: onHotspot ? InternetAddress(_hsInfo!.ip) : null,
      );
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
          if (left <= Duration.zero) {
            _phase = Phase.expired;
            _releaseHotspot();
          }
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
          _releaseHotspot();
        case TransferState.failed:
          _phase = Phase.failed;
      }
    });
  }

  // --- hotspot -----------------------------------------------------------

  Future<void> _toggleHotspot() async {
    if (_hsUi != HotspotUi.off) return _stopHotspot();
    setState(() {
      _hsUi = HotspotUi.starting;
      _manual = false;
    });
    try {
      final info = await _hotspot.start();
      if (!mounted) {
        await _hotspot.stop();
        return;
      }
      _hsInfo = info;
      // the server must listen on the hotspot address; the address can lag a moment
      for (var i = 0; i < 6; i++) {
        await _start();
        if (!mounted) return;
        if (_phase != Phase.failed) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (_phase == Phase.failed) {
        _hsInfo = null;
        setState(() => _hsUi = HotspotUi.off);
        await _hotspot.stop(); // never leave the hotspot on after a failure
        return;
      }
      setState(() => _hsUi = HotspotUi.joining);
      _pollClients();
    } on HotspotException catch (e) {
      if (!mounted) return;
      _hsInfo = null;
      setState(() {
        _hsUi = HotspotUi.off;
        final noNet = e.reason.startsWith('offline') || e.reason.startsWith('unavailable');
        _phase = noNet ? Phase.offline : Phase.failed;
      });
    }
  }

  /// Watches for the phone joining, then switches from the Wi-Fi QR to the download QR.
  void _pollClients() {
    _hsPoll?.cancel();
    _hsPoll = Timer.periodic(const Duration(milliseconds: 1500), (t) async {
      if (_polling) return;
      if (!mounted || _hsUi != HotspotUi.joining) return t.cancel();
      _polling = true;
      final n = await _hotspot.clients();
      _polling = false;
      if (n > 0 && mounted && _hsUi == HotspotUi.joining) {
        t.cancel();
        setState(() => _hsUi = HotspotUi.ready);
      }
    });
  }

  /// Turn the hotspot off for good: transfer finished or the code expired.
  void _releaseHotspot() {
    _hsPoll?.cancel();
    if (_hsUi == HotspotUi.off) return;
    _hsUi = HotspotUi.off;
    _hsInfo = null;
    unawaited(_hotspot.stop());
  }

  /// User switched the hotspot off: back to the normal Wi-Fi QR.
  Future<void> _stopHotspot() async {
    _hsPoll?.cancel();
    setState(() => _hsUi = HotspotUi.off);
    _hsInfo = null;
    await _hotspot.stop();
    if (mounted && _phase == Phase.waiting) await _start();
  }

  // -----------------------------------------------------------------------

  Future<void> _teardownServer() async {
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
      await _teardownServer();
      await _hotspot.stop();
      exit(0);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _hsPoll?.cancel();
    _lifecycle?.dispose();
    unawaited(_hotspot.stop());
    _teardownServer();
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
          accessCode: _server?.accessCode,
          manualAddress: _server?.shortAddress,
          showManual: _manual,
          hotspot: _hsUi,
          wifiQr: _hsInfo == null ? null : wifiQrString(_hsInfo!.ssid, _hsInfo!.pass),
          hotspotName: _hsInfo?.ssid,
          hotspotPass: _hsInfo?.pass,
          onToggleHotspot: Platform.isWindows ? _toggleHotspot : null,
          onToggleManual: () => setState(() => _manual = !_manual),
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
