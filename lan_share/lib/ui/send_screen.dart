import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_file.dart';
import '../core/discovery.dart';
import '../core/hotspot.dart';
import '../core/hotspot_runner.dart';
import '../core/identity.dart';
import '../core/lan_address.dart';
import '../core/qr_payload.dart';
import '../core/sender_server.dart';
import '../core/settings.dart';
import '../core/token_store.dart';
import 'send_view.dart';
import 'transfer_ring.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({
    super.key,
    required this.files,
    this.closeApp = false,
    this.hotspotRunner,
    this.settings,
  });
  final List<File> files;

  /// Started from the Windows share menu: closing ends the app.
  final bool closeApp;

  /// Runs the hotspot script; tests swap it to fake a joined phone.
  final ScriptRunner? hotspotRunner;

  /// Tests pass their own settings; they are then not saved to disk.
  final Settings? settings;

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
  double? _speed;
  int _lastBytes = 0;
  DateTime _lastAt = DateTime.now();
  PairRequest? _pair;
  bool _manual = false;

  late final Hotspot _hotspot;
  late Settings _settings;
  Directory? _supportDir;
  HotspotInfo? _hsInfo; // set while the hotspot is up
  bool _hsBusy = false; // hotspot starting in the background
  bool _joinView = false; // showing the Wi-Fi join QR instead of the link QR
  Timer? _hsPoll;
  bool _polling = false;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _hotspot = Hotspot(widget.hotspotRunner ?? powershellRunner);
    _settings = widget.settings ?? Settings();
    // closing the window must not leave the hotspot on
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      await _hotspot.stop();
      return AppExitResponse.exit;
    });
    _init();
  }

  Future<void> _init() async {
    _supportDir = await getApplicationSupportDirectory();
    if (widget.settings == null) _settings = await Settings.load(_supportDir!);
    await _start();
    // hotspot assist: the Android app can join it when the phone is not on this Wi-Fi.
    // A hotspot left on by a crashed run is cleaned up first, one step after the other.
    if (mounted && _settings.hotspotAssist && Platform.isWindows && _phase == Phase.waiting) {
      await _hotspot.recover();
      if (mounted && _phase == Phase.waiting) unawaited(_beginHotspot());
    }
  }

  Future<void> _saveSettings() async {
    if (widget.settings != null || _supportDir == null) return;
    await _settings.save(_supportDir!);
  }

  Future<void> _start() async {
    await _teardownServer();
    setState(() {
      _phase = Phase.waiting;
      _fraction = 0;
      _speed = null;
      _lastBytes = 0;
      _lastAt = DateTime.now();
      _pair = null;
      _link = null;
      _manual = false;
    });
    // No Wi-Fi or LAN: a QR pointing at this machine alone would be useless.
    if (_hsInfo == null && (await pickLanAddress()).isLoopback) {
      if (mounted) setState(() => _phase = Phase.offline);
      return;
    }
    try {
      final identity = await loadOrCreateIdentity(await getApplicationSupportDirectory());
      // listens on every network, so the same QR works on the home Wi-Fi and on the hotspot
      final server = SenderServer(widget.files, TokenStore(), identity: identity, bindAll: true, apk: bundledApk());
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
          _fraction = p.overallFraction;
          final now = DateTime.now();
          final dt = now.difference(_lastAt).inMilliseconds;
          if (dt >= 500) {
            final inst = (p.overallSent - _lastBytes) / (1 << 20) / (dt / 1000);
            _speed = _speed == null ? inst : _speed! * .6 + inst * .4;
            _lastBytes = p.overallSent;
            _lastAt = now;
          }
        case TransferState.done:
          _phase = Phase.done;
          _releaseHotspot();
        case TransferState.failed:
          _phase = Phase.failed;
      }
    });
  }

  // --- hotspot -----------------------------------------------------------

  /// Starts the hotspot quietly: the QR stays on screen and gains the join hint when it is up.
  Future<void> _beginHotspot({bool manual = false}) async {
    if (_hsInfo != null || _hsBusy) return;
    setState(() => _hsBusy = true);
    try {
      final info = await _hotspot.start();
      if (!mounted) {
        await _hotspot.stop();
        return;
      }
      if (_phase == Phase.done || _phase == Phase.expired) {
        await _hotspot.stop(); // the share ended while the hotspot was starting
        setState(() => _hsBusy = false);
        return;
      }
      setState(() {
        _hsInfo = info;
        _hsBusy = false;
      });
    } on HotspotException catch (e) {
      if (!mounted) return;
      setState(() {
        _hsBusy = false;
        // a background start that fails stays silent; the LAN QR still works
        if (manual && (e.reason.startsWith('offline') || e.reason.startsWith('unavailable'))) {
          _phase = Phase.offline;
        }
      });
    }
  }

  /// The hotspot button: turns it on or off, and remembers the choice.
  Future<void> _toggleHotspot() async {
    if (_hsInfo != null) {
      _settings.hotspotAssist = false;
      unawaited(_saveSettings());
      await _stopHotspot();
    } else {
      _settings.hotspotAssist = true;
      unawaited(_saveSettings());
      await _beginHotspot(manual: true);
    }
  }

  /// Swaps the link QR for the Wi-Fi join QR (for a browser phone that is not on the LAN).
  void _toggleJoin() {
    setState(() {
      _joinView = !_joinView;
      _manual = false;
    });
    if (_joinView) {
      _pollClients();
    } else {
      _hsPoll?.cancel();
    }
  }

  /// While the join QR shows, switch back to the link QR once a phone has joined.
  void _pollClients() {
    _hsPoll?.cancel();
    _hsPoll = Timer.periodic(const Duration(milliseconds: 1500), (t) async {
      if (_polling) return;
      if (!mounted || !_joinView) return t.cancel();
      _polling = true;
      final n = await _hotspot.clients();
      _polling = false;
      if (n > 0 && mounted && _joinView) {
        t.cancel();
        setState(() => _joinView = false);
      }
    });
  }

  /// Turn the hotspot off for good: transfer finished or the code expired.
  void _releaseHotspot() {
    _hsPoll?.cancel();
    if (_hsInfo == null) return;
    _hsInfo = null;
    _joinView = false;
    unawaited(_hotspot.stop());
  }

  Future<void> _stopHotspot() async {
    _hsPoll?.cancel();
    setState(() {
      _hsInfo = null;
      _joinView = false;
    });
    await _hotspot.stop();
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
  Widget build(BuildContext context) {
    final up = _hsInfo != null;
    return Scaffold(
      body: SendView(
        phase: _phase,
        link: _link,
        fileCount: widget.files.length,
        fileNames: [for (final f in widget.files) f.uri.pathSegments.last],
        remaining: _remaining,
        fraction: _fraction,
        speedMBps: _speed,
        pairCode: _pair?.code,
        accessCode: _server?.accessCode,
        manualAddress: _server?.shortAddress,
        showManual: _manual,
        hotspot: !up ? HotspotUi.off : (_joinView ? HotspotUi.joining : HotspotUi.ready),
        hotspotBusy: _hsBusy,
        qrData: up && _link != null ? qrPayload(_link!, hotspot: _hsInfo) : null,
        wifiQr: up ? wifiQrString(_hsInfo!.ssid, _hsInfo!.pass) : null,
        hotspotName: _hsInfo?.ssid,
        hotspotPass: _hsInfo?.pass,
        onToggleHotspot: Platform.isWindows ? _toggleHotspot : null,
        onToggleJoin: up ? _toggleJoin : null,
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
}
