// Large, empty, oddly named and interrupted transfers over real TLS.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/identity.dart';
import 'package:lan_share/core/receiver_client.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';

Future<String> hashOf(File f) async => (await sha256.bind(f.openRead()).first).toString();

void main() {
  late Directory work, dest, idDir;
  late Identity id;
  setUpAll(() async {
    idDir = Directory.systemTemp.createTempSync('fid_');
    id = await loadOrCreateIdentity(idDir);
  });
  setUp(() {
    work = Directory.systemTemp.createTempSync('fsrc_');
    dest = Directory.systemTemp.createTempSync('fdst_');
  });
  tearDown(() {
    work.deleteSync(recursive: true);
    dest.deleteSync(recursive: true);
  });
  tearDownAll(() => idDir.deleteSync(recursive: true));

  Future<Uri> serve(List<File> files) async {
    final s = SenderServer(files, TokenStore(), identity: id, bindAddress: InternetAddress.loopbackIPv4, httpRedirectPort: 0);
    addTearDown(s.stop);
    return s.start();
  }

  test('a 400 MB file arrives intact without loading it into memory', () async {
    final big = File('${work.path}/big.bin');
    final sink = big.openWrite();
    final chunk = List<int>.generate(1 << 20, (i) => (i * 31) & 0xff);
    for (var i = 0; i < 400; i++) {
      sink.add(chunk);
    }
    await sink.close();
    final before = ProcessInfo.currentRss;
    final link = await serve([big]);
    final sw = Stopwatch()..start();
    await ReceiverClient().receive(link, dest);
    sw.stop();
    final grown = (ProcessInfo.maxRss - before) / (1 << 20);
    final mbps = 400 / (sw.elapsedMilliseconds / 1000);
    // ignore: avoid_print
    print('400 MB in ${sw.elapsedMilliseconds} ms (${mbps.toStringAsFixed(0)} MB/s), memory grew ${grown.toStringAsFixed(0)} MB');
    expect(await hashOf(File('${dest.path}/big.bin')), await hashOf(big));
    expect(grown, lessThan(150), reason: 'must stream, not buffer');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('empty file, odd names and duplicates all arrive', () async {
    final names = [
      'empty.txt',
      "it's 100% #1 & more+.txt",
      'ünïcödé 写真 🙂.txt',
      '${'long' * 40}.txt',
      'dup.txt',
    ];
    final files = <File>[];
    for (final n in names) {
      files.add(File('${work.path}/$n')..writeAsStringSync(n == 'empty.txt' ? '' : 'content of $n'));
    }
    final sub = Directory('${work.path}/sub')..createSync();
    files.add(File('${sub.path}/dup.txt')..writeAsStringSync('second dup'));
    final link = await serve(files);
    await ReceiverClient().receive(link, dest);
    for (final n in names) {
      final got = File('${dest.path}/$n');
      expect(got.existsSync(), isTrue, reason: n);
      expect(got.readAsStringSync(), n == 'empty.txt' ? '' : 'content of $n', reason: n);
    }
    expect(File('${dest.path}/dup (2).txt').readAsStringSync(), 'second dup');
  });

  test('60 files in one share', () async {
    final files = [
      for (var i = 0; i < 60; i++) File('${work.path}/f$i.txt')..writeAsStringSync('file $i')
    ];
    await ReceiverClient().receive(await serve(files), dest);
    expect(dest.listSync().length, 60);
    expect(File('${dest.path}/f59.txt').readAsStringSync(), 'file 59');
  });

  test('a phone that drops mid-download can retry the same file', () async {
    final f = File('${work.path}/retry.bin')..writeAsBytesSync(List.generate(20 << 20, (i) => i & 0xff));
    final link = await serve([f]);
    final c = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    final req = await c.getUrl(link);
    final m = await (await req.close()).transform(const SystemEncoding().decoder).join();
    final url = RegExp(r'"url":"([^"]+)"').firstMatch(m)!.group(1)!;
    // start downloading, then hang up after the first chunk
    final res = await (await c.getUrl(link.resolve(url))).close();
    final firstChunk = Completer<void>();
    final sub = res.listen((_) {
      if (!firstChunk.isCompleted) firstChunk.complete();
    });
    await firstChunk.future;
    await sub.cancel();
    c.close(force: true);
    // retry on a fresh connection: the session is still valid and bytes are complete
    final c2 = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    final res2 = await (await c2.getUrl(link.resolve(url))).close();
    var n = 0;
    try {
      await for (final chunk in res2) {
        n += chunk.length;
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('second download failed after $n bytes: $e');
      rethrow;
    }
    c2.close();
    expect(n, 20 << 20);
  });

  test('a file deleted while sharing ends as a clear failure, server stays up', () async {
    final a = File('${work.path}/a.txt')..writeAsStringSync('a');
    final gone = File('${work.path}/gone.txt')..writeAsStringSync('g');
    final link = await serve([a, gone]);
    gone.deleteSync();
    await expectLater(ReceiverClient().receive(link, dest), throwsA(isA<TransferException>()));
    // the other file was not corrupted or half-written under a bad name
    expect(dest.listSync().whereType<File>().every((x) => x.lengthSync() == 1 || x.path.endsWith('a.txt')), isTrue);
  });
}
