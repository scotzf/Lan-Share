import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/hotspot.dart';

class FakeScript {
  FakeScript(this.replies);
  final Map<String, String> replies;
  final List<String> calls = [];
  Future<String> call(String command) async {
    calls.add(command);
    return replies[command] ?? '{"ok":true}';
  }
}

const startOk = '{"owned":true,"ok":true,"ssid":"LANShare-58U3","pass":"ccVHpZkSvJqL","ip":"192.168.137.1"}';

void main() {
  closingWhileStartingTests();
  group('wifiQrString', () {
    test('plain names', () {
      expect(wifiQrString('LANShare-58U3', 'ccVHpZkSvJqL'),
          'WIFI:T:WPA;S:LANShare-58U3;P:ccVHpZkSvJqL;;');
    });
    test('special characters are escaped', () {
      expect(wifiQrString(r'a;b,c:d\e"f', r'p;w'),
          r'WIFI:T:WPA;S:a\;b\,c\:d\\e\"f;P:p\;w;;');
    });
  });

  group('Hotspot', () {
    test('start returns the credentials and address', () async {
      final fake = FakeScript({'start': startOk});
      final info = await Hotspot(fake.call).start();
      expect(info.ssid, 'LANShare-58U3');
      expect(info.pass, 'ccVHpZkSvJqL');
      expect(info.ip, '192.168.137.1');
      expect(info.owned, isTrue);
    });

    test('start failure surfaces the reason', () async {
      final fake = FakeScript({'start': '{"ok":false,"error":"offline"}'});
      await expectLater(
          Hotspot(fake.call).start(),
          throwsA(isA<HotspotException>().having((e) => e.reason, 'reason', 'offline')));
    });

    test('warning lines before the JSON are ignored', () async {
      final fake = FakeScript({'start': 'WARNING: something\r\n$startOk\r\n'});
      expect((await Hotspot(fake.call).start()).ssid, 'LANShare-58U3');
    });

    test('unreadable output is a failure, not a crash', () async {
      final fake = FakeScript({'start': 'garbage'});
      await expectLater(Hotspot(fake.call).start(), throwsA(isA<HotspotException>()));
    });

    test('stop turns off a hotspot we started, once', () async {
      final fake = FakeScript({'start': startOk});
      final h = Hotspot(fake.call);
      await h.start();
      await h.stop();
      await h.stop();
      expect(fake.calls.where((c) => c == 'stop').length, 1);
    });

    test("stop never turns off the user's own hotspot", () async {
      final fake = FakeScript({'start': startOk.replaceAll('"owned":true', '"owned":false')});
      final h = Hotspot(fake.call);
      await h.start();
      await h.stop();
      expect(fake.calls, ['start']);
    });

    test('stop without start does nothing', () async {
      final fake = FakeScript({});
      await Hotspot(fake.call).stop();
      expect(fake.calls, isEmpty);
    });

    test('clients reads the count; bad output counts as none', () async {
      expect(await Hotspot(FakeScript({'clients': '{"ok":true,"clients":2}'}).call).clients(), 2);
      expect(await Hotspot(FakeScript({'clients': 'nope'}).call).clients(), 0);
    });

    test('recover asks the script to clean up', () async {
      final fake = FakeScript({});
      await Hotspot(fake.call).recover();
      expect(fake.calls, ['recover']);
    });
  });
}

void closingWhileStartingTests() {
  test('stopping while the hotspot is still starting waits for it, then turns it off', () async {
    final calls = <String>[];
    final startGate = Completer<String>();
    final h = Hotspot((cmd) {
      calls.add(cmd);
      return cmd == 'start' ? startGate.future : Future.value('{"ok":true}');
    });
    final starting = h.start();
    final stopping = h.stop(); // the window is closed right now
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, ['start'], reason: 'stop must wait for the start to finish, not skip it');
    startGate.complete(startOk);
    await starting;
    await stopping;
    expect(calls, ['start', 'stop']);
  });

  test('stopping while a start that then fails does not try to turn anything off', () async {
    final calls = <String>[];
    final gate = Completer<String>();
    final h = Hotspot((cmd) {
      calls.add(cmd);
      return cmd == 'start' ? gate.future : Future.value('{"ok":true}');
    });
    final starting = h.start().catchError((_) => const HotspotInfo('', '', '', false));
    final stopping = h.stop();
    gate.complete('{"ok":false,"error":"offline"}');
    await starting;
    await stopping;
    expect(calls, ['start']);
  });
}
