import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'identity.dart';
import 'pairing.dart';
import 'safe_name.dart';
import 'transfer_progress.dart';

class TransferException implements Exception {
  TransferException(this.message);
  final String message;
  @override
  String toString() => 'TransferException: $message';
}

class PairSession {
  PairSession(this.code, this.approval);
  final String code;

  /// Resolves to the download link once approved; null if denied.
  final Future<Uri?> approval;
}

class ReceiverClient {
  /// [allowInsecure] permits plain http links; tests only.
  ReceiverClient({this.allowInsecure = false});
  final bool allowInsecure;

  final _progress = StreamController<TransferProgress>.broadcast();
  Stream<TransferProgress> get progress => _progress.stream;

  /// Accepts only a certificate whose SHA-256 equals [fingerprint].
  HttpClient _pinned(String fingerprint) => HttpClient()
    ..badCertificateCallback =
        (cert, _, __) => sha256Hex(cert.der) == fingerprint;

  /// Starts pairing with a nearby sender. The code is computed here from the
  /// certificate this connection actually presented, so a man in the middle
  /// shows a different code than the real sender.
  Future<PairSession> requestPair(String host, int port,
      {Duration poll = const Duration(milliseconds: 500), bool secure = true}) async {
    final base = Uri(scheme: secure ? 'https' : 'http', host: host, port: port);
    String? seenFp;
    List<int>? seenDer;

    Future<Map> getJson(Uri u) async {
      final c = HttpClient()
        ..badCertificateCallback = (cert, _, __) {
          // First contact: record the certificate; later calls must match it.
          if (seenFp == null) {
            seenDer = cert.der;
            seenFp = sha256Hex(cert.der);
            return true;
          }
          return sha256Hex(cert.der) == seenFp;
        };
      try {
        final r = await (await c.getUrl(u)).close();
        if (secure && r.certificate != null) {
          seenDer ??= r.certificate!.der;
          seenFp ??= sha256Hex(seenDer!);
        }
        return jsonDecode(await utf8.decodeStream(r)) as Map;
      } finally {
        c.close();
      }
    }

    final created = await getJson(base.resolve('/pair'));
    final id = created['id'] as String;
    final code = secure ? sasCode(seenDer!, id) : created['code'] as String;

    Future<Uri?> wait() async {
      for (var i = 0; i < 240; i++) {
        final st = await getJson(base.resolve('/pair/$id'));
        if (st['status'] == 'approved') {
          final link = base.resolve(st['link'] as String);
          return secure ? link.replace(queryParameters: {'fp': seenFp!}) : link;
        }
        if (st['status'] == 'denied') return null;
        await Future<void>.delayed(poll);
      }
      return null;
    }

    return PairSession(code, wait());
  }

  Future<void> receive(Uri link, Directory dest, {String? pairingCode}) async {
    HttpClient? client;
    try {
      if (link.scheme == 'https') {
        final fp = link.queryParameters['fp'];
        if (fp == null || fp.length != 64) {
          throw TransferException('no fingerprint');
        }
        client = _pinned(fp);
      } else if (allowInsecure) {
        client = HttpClient();
      } else {
        throw TransferException('insecure link');
      }
      final qp = {...link.queryParameters, if (pairingCode != null) 'code': pairingCode};
      final first = link.replace(queryParameters: qp);
      final res = await (await client.getUrl(first)).close();
      if (res.statusCode != 200) {
        await res.drain();
        throw TransferException('refused ${res.statusCode}');
      }
      final m = jsonDecode(await utf8.decodeStream(res)) as Map;
      final taken = <String>{};
      for (final f in (m['files'] as List).cast<Map>()) {
        final name = safeName(f['name'] as String, taken);
        taken.add(name);
        await _download(client, link.resolve(f['url'] as String),
            File('${dest.path}${Platform.pathSeparator}$name'), name);
      }
      _progress.add(const TransferProgress(TransferState.done));
    } on TransferException {
      _progress.add(const TransferProgress(TransferState.failed));
      rethrow;
    } catch (e) {
      _progress.add(const TransferProgress(TransferState.failed));
      throw TransferException('$e');
    } finally {
      client?.close();
    }
  }

  Future<void> _download(HttpClient c, Uri url, File out, String name) async {
    final res = await (await c.getUrl(url)).close();
    if (res.statusCode != 200) {
      await res.drain();
      throw TransferException('file ${res.statusCode}');
    }
    final total = res.contentLength;
    var got = 0;
    var lastEmit = -1000;
    final clock = Stopwatch()..start();
    final sink = out.openWrite();
    var ok = false;
    try {
      await sink.addStream(res.map((chunk) {
        got += chunk.length;
        if (clock.elapsedMilliseconds - lastEmit >= 100) {
          lastEmit = clock.elapsedMilliseconds;
          _progress.add(TransferProgress(TransferState.active,
              sent: got, total: total, name: name));
        }
        return chunk;
      }));
      ok = true;
    } finally {
      await sink.close();
      if (!ok && out.existsSync()) out.deleteSync();
    }
  }
}
