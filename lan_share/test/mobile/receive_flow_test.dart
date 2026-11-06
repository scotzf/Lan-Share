import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/hotspot.dart';
import 'package:lan_share/core/qr_payload.dart';
import 'package:lan_share/core/transfer_progress.dart';
import 'package:lan_share/mobile/receive_flow.dart';

final lan = Uri.parse('https://192.168.1.3:53270/tok123?fp=${'a' * 64}');
const hs = HotspotInfo('LANShare-x28r', 'ccVHpZkSvJqL', '192.168.137.1', true);
final withHotspot = qrPayload(lan, hotspot: hs);
final plain = lan.toString();

class FakeWifi implements WifiJoiner {
  FakeWifi({this.joinResult = true});
  bool joinResult;
  final calls = <String>[];
  @override
  Future<bool> join(String ssid, String pass) async {
    calls.add('join:$ssid:$pass');
    return joinResult;
  }

  @override
  Future<void> leave() async => calls.add('leave');
}

class Rig {
  Rig({Set<String>? reachable, this.wifi}) : reachable = reachable ?? {};
  final Set<String> reachable; // hosts whose /ping answers
  FakeWifi? wifi;
  final probed = <Uri>[];
  final downloaded = <Uri>[];
  final saved = <String>[];
  Object? downloadError, saveError;
  int joinedAfterProbes = 0; // hotspot answers only after this many probes of it

  late final ReceiveFlow flow = ReceiveFlow(
    probe: (u) async {
      probed.add(u);
      if (u.host == '192.168.137.1') {
        final n = probed.where((p) => p.host == '192.168.137.1').length;
        return reachable.contains(u.host) && n > joinedAfterProbes;
      }
      return reachable.contains(u.host);
    },
    wifi: wifi ??= FakeWifi(),
    download: (u, onProgress) async {
      downloaded.add(u);
      if (downloadError != null) throw downloadError!;
      onProgress(const TransferProgress(TransferState.active, overallSent: 50, overallTotal: 100));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      onProgress(const TransferProgress(TransferState.active, overallSent: 100, overallTotal: 100));
      return [DownloadedFile('a.png', 60, '/tmp/a.png'), DownloadedFile('b.pdf', 40, '/tmp/b.pdf')];
    },
    save: (f) async {
      if (saveError != null) throw saveError!;
      saved.add(f.name);
    },
    waitForHotspot: const Duration(milliseconds: 400),
    retryEvery: const Duration(milliseconds: 40),
  );
}

void main() {
  test('same Wi-Fi: downloads from the link, never touches Wi-Fi', () async {
    final r = Rig(reachable: {'192.168.1.3'});
    await r.flow.run(withHotspot);
    expect(r.flow.phase, FlowPhase.done);
    expect(r.downloaded.single.toString(), lan.toString());
    expect(r.wifi!.calls, isEmpty);
    expect(r.saved, ['a.png', 'b.pdf']);
    expect(r.flow.fileCount, 2);
    expect(r.flow.totalBytes, 100);
    expect(r.flow.fraction, 1);
  });

  test('not on the Wi-Fi: joins the hotspot, downloads from its address, then leaves', () async {
    final r = Rig(reachable: {'192.168.137.1'})..joinedAfterProbes = 2;
    final phases = <FlowPhase>[];
    r.flow.addListener(() => phases.add(r.flow.phase));
    await r.flow.run(withHotspot);
    expect(r.flow.phase, FlowPhase.done);
    expect(r.wifi!.calls.first, 'join:LANShare-x28r:ccVHpZkSvJqL');
    expect(r.wifi!.calls.last, 'leave');
    expect(r.downloaded.single.host, '192.168.137.1');
    expect(r.downloaded.single.port, 53270);
    expect(r.downloaded.single.path, '/tok123');
    expect(r.downloaded.single.queryParameters['fp'], 'a' * 64);
    expect(phases, containsAllInOrder([FlowPhase.connecting, FlowPhase.joining, FlowPhase.downloading, FlowPhase.done]));
  });

  test('no Wi-Fi match and no hotspot hint: offline, nothing joined', () async {
    final r = Rig();
    await r.flow.run(plain);
    expect(r.flow.phase, FlowPhase.offline);
    expect(r.wifi!.calls, isEmpty);
    expect(r.downloaded, isEmpty);
  });

  test('the phone refuses the Wi-Fi prompt: failed, cleaned up', () async {
    final r = Rig(wifi: FakeWifi(joinResult: false));
    await r.flow.run(withHotspot);
    expect(r.flow.phase, FlowPhase.failed);
    expect(r.flow.problem, FlowProblem.join);
    expect(r.downloaded, isEmpty);
    expect(r.wifi!.calls.last, 'leave');
  });

  test('joined but the laptop never answers: failed and the hotspot is released', () async {
    final r = Rig(); // nothing reachable at all
    await r.flow.run(withHotspot);
    expect(r.flow.phase, FlowPhase.failed);
    expect(r.flow.problem, FlowProblem.unreachable);
    expect(r.wifi!.calls, ['join:LANShare-x28r:ccVHpZkSvJqL', 'leave']);
    expect(r.probed.where((u) => u.host == '192.168.137.1').length, greaterThan(2), reason: 'it retried');
  });

  test('not our QR code', () async {
    for (final text in ['', 'hello', 'WIFI:T:WPA;S:x;P:y;;', 'https://']) {
      final r = Rig(reachable: {'192.168.1.3'});
      await r.flow.run(text);
      expect(r.flow.phase, FlowPhase.invalid, reason: text);
      expect(r.probed, isEmpty);
    }
  });

  test('a failing download is reported, and Wi-Fi is released if it was joined', () async {
    final r = Rig(reachable: {'192.168.137.1'})..downloadError = Exception('boom');
    await r.flow.run(withHotspot);
    expect(r.flow.phase, FlowPhase.failed);
    expect(r.flow.problem, FlowProblem.transfer);
    expect(r.wifi!.calls.last, 'leave');
  });

  test('a failure while saving to Downloads is reported', () async {
    final r = Rig(reachable: {'192.168.1.3'})..saveError = Exception('no space');
    await r.flow.run(plain);
    expect(r.flow.phase, FlowPhase.failed);
    expect(r.flow.problem, FlowProblem.save);
  });

  test('progress rises while downloading and the speed is reported', () async {
    final r = Rig(reachable: {'192.168.1.3'});
    final seen = <double>[];
    r.flow.addListener(() {
      if (r.flow.phase == FlowPhase.downloading) seen.add(r.flow.fraction);
    });
    await r.flow.run(plain);
    expect(seen, isNotEmpty);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
    expect(seen.last, closeTo(1.0, 1e-9));
  });

  test('cancel while joining releases the Wi-Fi and goes back to idle', () async {
    final r = Rig(reachable: {'192.168.137.1'})..joinedAfterProbes = 1000;
    final running = r.flow.run(withHotspot);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await r.flow.cancel();
    await running;
    expect(r.flow.phase, FlowPhase.idle);
    expect(r.wifi!.calls.last, 'leave');
    expect(r.downloaded, isEmpty);
  });

  test('running again starts clean', () async {
    final r = Rig(reachable: {'192.168.1.3'});
    await r.flow.run(plain);
    expect(r.flow.phase, FlowPhase.done);
    await r.flow.run('nonsense');
    expect(r.flow.phase, FlowPhase.invalid);
    expect(r.flow.fileCount, 0);
    expect(r.flow.fraction, 0);
  });
}
