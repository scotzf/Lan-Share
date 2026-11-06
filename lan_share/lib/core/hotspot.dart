import 'dart:convert';

/// Join-Wi-Fi QR payload understood by Android and iPhone cameras.
String wifiQrString(String ssid, String pass) {
  String esc(String s) => s.replaceAllMapped(RegExp(r'[\\;,:"]'), (m) => '\\${m[0]}');
  return 'WIFI:T:WPA;S:${esc(ssid)};P:${esc(pass)};;';
}

class HotspotInfo {
  const HotspotInfo(this.ssid, this.pass, this.ip, this.owned);
  final String ssid;
  final String pass;

  /// Address of this laptop on the hotspot network.
  final String ip;

  /// True when LAN Share turned the hotspot on (and so turns it off again).
  final bool owned;
}

class HotspotException implements Exception {
  HotspotException(this.reason);
  final String reason;
  @override
  String toString() => 'HotspotException: $reason';
}

/// Runs one hotspot script command and returns its stdout.
typedef ScriptRunner = Future<String> Function(String command);

/// Windows Mobile Hotspot for the length of one transfer.
class Hotspot {
  Hotspot(this._run);
  final ScriptRunner _run;
  bool _ours = false;

  Future<HotspotInfo> start() async {
    final j = await _json('start');
    if (j['ok'] != true) throw HotspotException('${j['error'] ?? 'failed'}');
    final owned = j['owned'] == true;
    _ours = owned;
    return HotspotInfo(
      '${j['ssid']}',
      '${j['pass']}',
      '${j['ip'] ?? '192.168.137.1'}',
      owned,
    );
  }

  /// Turns the hotspot off and restores the user's settings. Only acts on a
  /// hotspot this object started; safe to call more than once.
  Future<void> stop() async {
    if (!_ours) return;
    _ours = false;
    await _json('stop');
  }

  Future<int> clients() async {
    try {
      return (await _json('clients'))['clients'] as int? ?? 0;
    } on HotspotException {
      return 0;
    }
  }

  /// Cleans up after a crash: a hotspot we left on is turned off.
  Future<void> recover() async {
    try {
      await _json('recover');
    } on HotspotException {
      // nothing to recover
    }
  }

  Future<Map<String, Object?>> _json(String command) async {
    final out = await _run(command);
    final line = const LineSplitter()
        .convert(out)
        .map((l) => l.trim())
        .lastWhere((l) => l.startsWith('{'), orElse: () => '');
    if (line.isEmpty) throw HotspotException('no answer');
    try {
      return (jsonDecode(line) as Map).cast<String, Object?>();
    } catch (_) {
      throw HotspotException('bad answer');
    }
  }
}
