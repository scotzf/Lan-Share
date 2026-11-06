import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  final _progress = StreamController<TransferProgress>.broadcast();
  Stream<TransferProgress> get progress => _progress.stream;

  Future<PairSession> requestPair(String host, int port,
      {Duration poll = const Duration(milliseconds: 500)}) async {
    final base = Uri(scheme: 'http', host: host, port: port);
    Future<Map> getJson(Uri u) async {
      final c = HttpClient();
      try {
        final r = await (await c.getUrl(u)).close();
        return jsonDecode(await utf8.decodeStream(r)) as Map;
      } finally {
        c.close();
      }
    }

    final created = await getJson(base.resolve('/pair'));
    final id = created['id'] as String;
    Future<Uri?> wait() async {
      for (var i = 0; i < 240; i++) {
        final st = await getJson(base.resolve('/pair/$id'));
        if (st['status'] == 'approved') {
          return base.resolve(st['link'] as String);
        }
        if (st['status'] == 'denied') return null;
        await Future<void>.delayed(poll);
      }
      return null;
    }

    return PairSession(created['code'] as String, wait());
  }

  Future<void> receive(Uri link, Directory dest, {String? pairingCode}) async {
    final client = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    try {
      final first = pairingCode == null
          ? link
          : link.replace(queryParameters: {'code': pairingCode});
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
      client.close();
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
    final sink = out.openWrite();
    try {
      await sink.addStream(res.map((chunk) {
        got += chunk.length;
        _progress.add(TransferProgress(TransferState.active,
            sent: got, total: total, name: name));
        return chunk;
      }));
    } finally {
      await sink.close();
    }
  }
}
