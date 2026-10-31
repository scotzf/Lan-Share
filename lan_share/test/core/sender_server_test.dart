import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';

Future<(int, String)> get(Uri u) async {
  final c = HttpClient();
  final r = await (await c.getUrl(u)).close();
  final body = await utf8.decodeStream(r);
  c.close();
  return (r.statusCode, body);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ls_'));
  tearDown(() => dir.deleteSync(recursive: true));

  File mk(String name, String content, [String sub = '']) {
    final d = sub.isEmpty ? dir : Directory('${dir.path}/$sub')..createSync();
    return File('${d.path}/$name')..writeAsStringSync(content);
  }

  Future<SenderServer> up(List<File> f,
      {Duration idle = const Duration(minutes: 5), int? port}) async {
    final s = SenderServer(f, TokenStore(),
        idle: idle, bindAddress: InternetAddress.loopbackIPv4, preferredPort: port);
    addTearDown(s.stop);
    return s;
  }

  Future<Map> manifest(Uri link) async =>
      jsonDecode((await get(link)).$2) as Map;

  test('valid token downloads file bytes', () async {
    final s = await up([mk('a.txt', 'hello')]);
    final link = await s.start();
    final m = await manifest(link);
    final f = (m['files'] as List).first as Map;
    expect(f['name'], 'a.txt');
    final r = await get(link.resolve(f['url'] as String));
    expect(r.$1, 200);
    expect(r.$2, 'hello');
  });

  test('token reuse returns 403', () async {
    final s = await up([mk('a.txt', 'x')]);
    final link = await s.start();
    await manifest(link);
    expect((await get(link)).$1, 403);
  });

  test('path outside selection returns 404', () async {
    final s = await up([mk('a.txt', 'x')]);
    final link = await s.start();
    final m = await manifest(link);
    final base = link.resolve('/s/${m['session']}/f/');
    expect((await get(base.resolve('99'))).$1, 404);
    expect((await get(link.resolve('/../etc/passwd'))).$1, 404);
    expect((await get(base.resolve('..%2f..%2fa.txt'))).$1, 404);
  });

  test('duplicate names are both served', () async {
    final s = await up([mk('d.txt', 'one'), mk('d.txt', 'two', 'sub')]);
    final link = await s.start();
    final files = (await manifest(link))['files'] as List;
    final bodies = <String>[];
    for (final f in files) {
      bodies.add((await get(link.resolve((f as Map)['url'] as String))).$2);
    }
    expect(bodies, ['one', 'two']);
  });

  test('idle timeout stops server', () async {
    final s = await up([mk('a.txt', 'x')], idle: const Duration(milliseconds: 150));
    final link = await s.start();
    await Future.delayed(const Duration(milliseconds: 500));
    expect(() => get(link), throwsA(isA<SocketException>()));
  });

  test('occupied preferred port falls back to another', () async {
    final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(blocker.close);
    final s = await up([mk('a.txt', 'x')], port: blocker.port);
    final link = await s.start();
    expect(link.port, isNot(blocker.port));
  });

  test('file deleted before transfer ends in failed state', () async {
    final f = mk('gone.txt', 'x');
    final s = await up([f]);
    final link = await s.start();
    final states = <TransferState>[];
    s.progress.listen((p) => states.add(p.state));
    final m = await manifest(link);
    f.deleteSync();
    final url = ((m['files'] as List).first as Map)['url'] as String;
    final r = await get(link.resolve(url));
    expect(r.$1, 404);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(states, contains(TransferState.failed));
  });
}
