import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/discovery.dart';

class FakeBus implements BeaconTransport {
  static final _c = StreamController<Beacon>.broadcast(sync: true);
  @override
  void send(Beacon b) => _c.add(b);
  @override
  Stream<Beacon> get incoming => _c.stream;
  @override
  Future<void> close() async {}
}

void main() {
  test('advertised sender appears in nearby list', () async {
    final tx = Discovery(FakeBus(), interval: const Duration(milliseconds: 20));
    final rx = Discovery(FakeBus(), interval: const Duration(milliseconds: 20));
    await tx.advertise('Laptop', 4242);
    final list = await rx.nearby().firstWhere((l) => l.isNotEmpty);
    expect(list.first.name, 'Laptop');
    expect(list.first.port, 4242);
    await tx.stop();
    await rx.stop();
  });

  test('sender disappears after stop', () async {
    final tx = Discovery(FakeBus(), interval: const Duration(milliseconds: 20));
    final rx = Discovery(FakeBus(),
        interval: const Duration(milliseconds: 20),
        expiry: const Duration(milliseconds: 120));
    await tx.advertise('Laptop', 1);
    await rx.nearby().firstWhere((l) => l.isNotEmpty);
    await tx.stop();
    final empty = await rx.nearby().firstWhere((l) => l.isEmpty)
        .timeout(const Duration(seconds: 2));
    expect(empty, isEmpty);
    await rx.stop();
  });
}
