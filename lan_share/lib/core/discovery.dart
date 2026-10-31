import 'dart:async';
import 'dart:convert';
import 'dart:io';

class Beacon {
  const Beacon(this.name, this.port, this.host);
  final String name;
  final int port;
  final String host;
}

class NearbySender {
  const NearbySender(this.name, this.host, this.port);
  final String name;
  final String host;
  final int port;
}

abstract class BeaconTransport {
  void send(Beacon b);
  Stream<Beacon> get incoming;
  Future<void> close();
}

/// UDP broadcast beacons on the LAN (pure Dart; works on Windows and Android).
class UdpBeaconTransport implements BeaconTransport {
  UdpBeaconTransport._(this._socket, this._broadcast);
  static const port = 53318;
  final RawDatagramSocket _socket;
  final InternetAddress _broadcast;

  static Future<UdpBeaconTransport> open() async {
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port,
        reuseAddress: true, reusePort: !Platform.isWindows);
    s.broadcastEnabled = true;
    return UdpBeaconTransport._(s, InternetAddress('255.255.255.255'));
  }

  @override
  void send(Beacon b) => _socket.send(
      utf8.encode(jsonEncode({'app': 'lanshare', 'name': b.name, 'port': b.port})),
      _broadcast,
      port);

  @override
  Stream<Beacon> get incoming => _socket.expand((e) {
        if (e != RawSocketEvent.read) return const <Beacon>[];
        final d = _socket.receive();
        if (d == null) return const <Beacon>[];
        try {
          final m = jsonDecode(utf8.decode(d.data)) as Map;
          if (m['app'] != 'lanshare') return const <Beacon>[];
          return [Beacon(m['name'] as String, m['port'] as int, d.address.address)];
        } catch (_) {
          return const <Beacon>[];
        }
      });

  @override
  Future<void> close() async => _socket.close();
}

class Discovery {
  Discovery(this._transport,
      {this.interval = const Duration(seconds: 1),
      this.expiry = const Duration(seconds: 4)});

  final BeaconTransport _transport;
  final Duration interval;
  final Duration expiry;
  Timer? _beat;
  final Map<String, (NearbySender, DateTime)> _seen = {};
  final _out = StreamController<List<NearbySender>>.broadcast();
  StreamSubscription<Beacon>? _sub;
  Timer? _sweep;

  Future<void> advertise(String deviceName, int port) async {
    _beat?.cancel();
    void beat() => _transport.send(Beacon(deviceName, port, ''));
    beat();
    _beat = Timer.periodic(interval, (_) => beat());
  }

  Stream<List<NearbySender>> nearby() {
    _sub ??= _transport.incoming.listen((b) {
      _seen['${b.host}:${b.port}'] = (NearbySender(b.name, b.host, b.port), DateTime.now());
      _emit();
    });
    _sweep ??= Timer.periodic(interval, (_) {
      final cutoff = DateTime.now().subtract(expiry);
      final before = _seen.length;
      _seen.removeWhere((_, v) => v.$2.isBefore(cutoff));
      if (_seen.length != before) _emit();
    });
    return _out.stream;
  }

  void _emit() => _out.add(_seen.values.map((v) => v.$1).toList());

  Future<void> stop() async {
    _beat?.cancel();
    _sweep?.cancel();
    await _sub?.cancel();
    await _transport.close();
  }
}
