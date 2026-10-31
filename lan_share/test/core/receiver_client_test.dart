import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/receiver_client.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';

void main() {
  late Directory src, dest;
  setUp(() {
    src = Directory.systemTemp.createTempSync('src_');
    dest = Directory.systemTemp.createTempSync('dst_');
  });
  tearDown(() {
    src.deleteSync(recursive: true);
    dest.deleteSync(recursive: true);
  });

  Future<(SenderServer, Uri)> sender(List<File> f, {String? code}) async {
    final s = SenderServer(f, TokenStore(),
        bindAddress: InternetAddress.loopbackIPv4, pairingCode: code);
    addTearDown(s.stop);
    return (s, await s.start());
  }

  test('receive writes files to dest only', () async {
    final a = File('${src.path}/a b 写.txt')..writeAsStringSync('AAA');
    final (_, link) = await sender([a]);
    await ReceiverClient().receive(link, dest);
    expect(File('${dest.path}/a b 写.txt').readAsStringSync(), 'AAA');
    expect(dest.listSync().length, 1);
  });

  test('same-named files are both kept', () async {
    final sub = Directory('${src.path}/s')..createSync();
    final a = File('${src.path}/d.txt')..writeAsStringSync('1');
    final b = File('${sub.path}/d.txt')..writeAsStringSync('2');
    final (_, link) = await sender([a, b]);
    await ReceiverClient().receive(link, dest);
    expect(File('${dest.path}/d.txt').readAsStringSync(), '1');
    expect(File('${dest.path}/d (2).txt').readAsStringSync(), '2');
  });

  test('wrong pairing code aborts and writes nothing', () async {
    final a = File('${src.path}/a.txt')..writeAsStringSync('x');
    final (_, link) = await sender([a], code: '1234');
    await expectLater(
        ReceiverClient().receive(link, dest, pairingCode: '9999'),
        throwsA(isA<TransferException>()));
    expect(dest.listSync(), isEmpty);
  });

  test('right pairing code succeeds', () async {
    final a = File('${src.path}/a.txt')..writeAsStringSync('x');
    final (_, link) = await sender([a], code: '1234');
    await ReceiverClient().receive(link, dest, pairingCode: '1234');
    expect(File('${dest.path}/a.txt').existsSync(), isTrue);
  });
}
