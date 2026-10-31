import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'lan_address.dart';
import 'pairing.dart';
import 'token_store.dart';
import 'transfer_progress.dart';

export 'transfer_progress.dart';

/// Temporary server that serves only the chosen files, once.
class SenderServer {
  SenderServer(
    this.files,
    this.tokens, {
    this.idle = const Duration(minutes: 5),
    this.bindAddress,
    this.preferredPort,
    this.securityContext,
    this.pairingCode,
  });

  final List<File> files;
  final TokenStore tokens;
  final Duration idle;
  final InternetAddress? bindAddress;
  final int? preferredPort;
  final SecurityContext? securityContext;
  final String? pairingCode;

  HttpServer? _server;
  Timer? _idleTimer;
  String? _session;
  String? _token;
  final Set<int> _finished = {};
  final _progress = StreamController<TransferProgress>.broadcast();

  Stream<TransferProgress> get progress => _progress.stream;

  Future<Uri> start() async {
    final addr = bindAddress ?? await pickLanAddress();
    _server = await _bind(addr);
    _server!.listen(_handle);
    _token = tokens.issue();
    _resetIdle();
    final scheme = securityContext == null ? 'http' : 'https';
    return Uri.parse('$scheme://${addr.address}:${_server!.port}/$_token');
  }

  Future<HttpServer> _bind(InternetAddress addr) async {
    Future<HttpServer> b(int port) => securityContext == null
        ? HttpServer.bind(addr, port)
        : HttpServer.bindSecure(addr, port, securityContext!);
    if (preferredPort != null) {
      try {
        return await b(preferredPort!);
      } on SocketException {
        // fall through to any free port
      }
    }
    return b(0);
  }

  void _resetIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idle, stop);
  }

  Future<void> stop() async {
    _idleTimer?.cancel();
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    _resetIdle();
    final seg = req.uri.pathSegments;
    try {
      if (seg.length == 1 && seg[0].isNotEmpty) {
        final want = pairingCode;
        if (want != null &&
            !codesMatch(want, req.uri.queryParameters['code'] ?? '')) {
          unawaited(stop());
          return _reply(req, 403);
        }
        if (!tokens.consume(seg[0])) return _reply(req, 403);
        _session = _randomId();
        return _manifest(req);
      }
      if (seg.length == 4 && seg[0] == 's' && seg[2] == 'f' && seg[1] == _session) {
        final i = int.tryParse(seg[3]);
        if (i != null && i >= 0 && i < files.length) return _file(req, i);
      }
      return _reply(req, 404);
    } catch (_) {
      return _reply(req, 500);
    }
  }

  Future<void> _manifest(HttpRequest req) async {
    final list = [
      for (var i = 0; i < files.length; i++)
        {
          'name': files[i].uri.pathSegments.last,
          'size': files[i].lengthSync(),
          'url': '/s/$_session/f/$i',
        }
    ];
    req.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'session': _session, 'files': list}));
    await req.response.close();
  }

  Future<void> _file(HttpRequest req, int i) async {
    final f = files[i];
    final name = f.uri.pathSegments.last;
    if (!f.existsSync()) {
      _progress.add(TransferProgress(TransferState.failed, name: name));
      return _reply(req, 404);
    }
    final total = f.lengthSync();
    var sent = 0;
    req.response
      ..headers.contentType = ContentType.binary
      ..headers.set('Content-Disposition',
          'attachment; filename*=UTF-8\'\'${Uri.encodeComponent(name)}')
      ..contentLength = total;
    try {
      await req.response.addStream(f.openRead().map((c) {
        sent += c.length;
        _progress.add(TransferProgress(TransferState.active,
            sent: sent, total: total, name: name));
        return c;
      }));
      await req.response.close();
    } catch (_) {
      _progress.add(TransferProgress(TransferState.failed, name: name));
      return;
    }
    _finished.add(i);
    if (_finished.length == files.length) {
      _progress.add(const TransferProgress(TransferState.done));
      unawaited(Future.delayed(const Duration(milliseconds: 200), stop));
    }
  }

  Future<void> _reply(HttpRequest req, int code) async {
    req.response.statusCode = code;
    await req.response.close();
  }

  String _randomId() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
