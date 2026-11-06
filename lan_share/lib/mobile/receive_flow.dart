import 'package:flutter/foundation.dart';

import '../core/qr_payload.dart';
import '../core/transfer_progress.dart';

enum FlowPhase { idle, connecting, joining, downloading, done, failed, offline, invalid }

/// Why a run failed, so the screen can show the right icon.
enum FlowProblem { none, join, unreachable, transfer, save }

/// Joins and leaves the laptop's hotspot (Android system Wi-Fi API).
abstract class WifiJoiner {
  /// True once the phone is on the network.
  Future<bool> join(String ssid, String pass);
  Future<void> leave();
}

class DownloadedFile {
  const DownloadedFile(this.name, this.size, this.path);
  final String name;
  final int size;
  final String path;
}

/// Is the laptop's server answering at this link? (never uses the one-time token)
typedef Probe = Future<bool> Function(Uri link);

/// Downloads every file behind [link]; reports progress as it goes.
typedef Download = Future<List<DownloadedFile>> Function(Uri link, void Function(TransferProgress) onProgress);

/// Puts a downloaded file where the user finds it (Downloads).
typedef Save = Future<void> Function(DownloadedFile file);

/// The receiving side, start to finish: read the QR, try the home Wi-Fi, fall back to the
/// laptop's hotspot, download, save, and always hand the phone's Wi-Fi back.
class ReceiveFlow extends ChangeNotifier {
  ReceiveFlow({
    required this.probe,
    required this.wifi,
    required this.download,
    required this.save,
    this.waitForHotspot = const Duration(seconds: 8),
    this.retryEvery = const Duration(milliseconds: 500),
  });

  final Probe probe;
  final WifiJoiner wifi;
  final Download download;
  final Save save;
  final Duration waitForHotspot;
  final Duration retryEvery;

  FlowPhase phase = FlowPhase.idle;
  FlowProblem problem = FlowProblem.none;
  double fraction = 0;
  double? speedMBps;
  int fileCount = 0;
  int totalBytes = 0;
  List<String> names = const [];

  int _runId = 0;
  bool _joined = false;
  int _lastBytes = 0;
  DateTime _lastAt = DateTime.now();

  bool _stale(int id) => id != _runId;

  void _set(FlowPhase p, {FlowProblem why = FlowProblem.none}) {
    phase = p;
    problem = why;
    notifyListeners();
  }

  void _reset() {
    phase = FlowPhase.idle;
    problem = FlowProblem.none;
    fraction = 0;
    speedMBps = null;
    fileCount = 0;
    totalBytes = 0;
    names = const [];
    _lastBytes = 0;
    _lastAt = DateTime.now();
  }

  /// Runs one share from the text of a scanned QR code.
  Future<void> run(String qrText) async {
    final id = ++_runId;
    _reset();
    final payload = parseQrPayload(qrText);
    if (payload == null) {
      _set(FlowPhase.invalid);
      return;
    }
    _set(FlowPhase.connecting);
    try {
      if (await probe(payload.link)) {
        if (_stale(id)) return;
        await _transfer(payload.link, id);
        return;
      }
      if (_stale(id)) return;
      final h = payload.hotspot;
      if (h == null) {
        _set(FlowPhase.offline);
        return;
      }
      _set(FlowPhase.joining);
      _joined = true;
      final ok = await wifi.join(h.ssid, h.pass);
      if (_stale(id)) return;
      if (!ok) {
        _set(FlowPhase.failed, why: FlowProblem.join);
        return;
      }
      final hotspotLink = payload.hotspotLink!;
      if (!await _waitFor(hotspotLink, id)) {
        if (!_stale(id)) _set(FlowPhase.failed, why: FlowProblem.unreachable);
        return;
      }
      await _transfer(hotspotLink, id);
    } catch (_) {
      if (!_stale(id)) _set(FlowPhase.failed, why: FlowProblem.transfer);
    } finally {
      if (_joined) {
        _joined = false;
        await wifi.leave();
      }
    }
  }

  /// The hotspot address can take a moment to answer after the phone joins.
  Future<bool> _waitFor(Uri link, int id) async {
    final end = DateTime.now().add(waitForHotspot);
    while (DateTime.now().isBefore(end)) {
      if (_stale(id)) return false;
      if (await probe(link)) return true;
      await Future<void>.delayed(retryEvery);
    }
    return false;
  }

  Future<void> _transfer(Uri link, int id) async {
    _set(FlowPhase.downloading);
    final List<DownloadedFile> files;
    try {
      files = await download(link, (p) => _onProgress(p, id));
    } catch (_) {
      if (!_stale(id)) _set(FlowPhase.failed, why: FlowProblem.transfer);
      return;
    }
    if (_stale(id)) return;
    try {
      for (final f in files) {
        await save(f);
      }
    } catch (_) {
      if (!_stale(id)) _set(FlowPhase.failed, why: FlowProblem.save);
      return;
    }
    fileCount = files.length;
    totalBytes = files.fold<int>(0, (a, f) => a + f.size);
    names = [for (final f in files) f.name];
    fraction = 1;
    _set(FlowPhase.done);
  }

  void _onProgress(TransferProgress p, int id) {
    if (_stale(id)) return;
    fraction = p.overallFraction;
    final now = DateTime.now();
    final dt = now.difference(_lastAt).inMilliseconds;
    if (dt >= 500 && p.overallSent > 0) {
      final inst = (p.overallSent - _lastBytes) / (1 << 20) / (dt / 1000);
      speedMBps = speedMBps == null ? inst : speedMBps! * .6 + inst * .4;
      _lastBytes = p.overallSent;
      _lastAt = now;
    }
    notifyListeners();
  }

  /// Stops a run in progress and hands the Wi-Fi back.
  Future<void> cancel() async {
    _runId++;
    _reset();
    notifyListeners();
    if (_joined) {
      _joined = false;
      await wifi.leave();
    }
  }
}
