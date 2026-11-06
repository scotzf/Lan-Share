import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'identity.dart';
import 'lan_address.dart';
import 'pairing.dart';
import 'token_store.dart';
import 'transfer_progress.dart';
import 'web_pages.dart';

export 'transfer_progress.dart';

class PairRequest {
  const PairRequest(this.id, this.code);
  final String id;
  final String code;
}

/// Temporary server that serves only the chosen files, once.
class SenderServer {
  SenderServer(
    this.files,
    this.tokens, {
    this.idle = const Duration(minutes: 5),
    this.bindAddress,
    this.preferredPort,
    this.identity,
    this.pairingCode,
    this.httpRedirectPort = 80,
  });

  final List<File> files;
  final TokenStore tokens;
  final Duration idle;
  final InternetAddress? bindAddress;
  final int? preferredPort;
  final Identity? identity;
  final String? pairingCode;

  /// Plain-http port that bounces to the secure code page, so a typed
  /// address works. 80 means the browser default; 0 picks any free port.
  final int httpRedirectPort;

  HttpServer? _server;
  HttpServer? _redirect;
  Uri? _link;
  InternetAddress? _addr;
  Timer? _idleTimer;
  String? _session;
  String? _token;
  final String accessCode =
      (Random.secure().nextInt(900000) + 100000).toString();
  int _badCodes = 0;
  final Set<int> _finished = {};
  int _sentTotal = 0;
  int? _grand;

  int _grandTotal() => _grand ??= files.fold<int>(0, (a, f) => a + (f.existsSync() ? f.lengthSync() : 0));
  final _progress = StreamController<TransferProgress>.broadcast();
  final _pairReq = StreamController<PairRequest>.broadcast();
  final Map<String, String> _pairStatus = {};
  final Map<String, String> _pairLink = {};

  Stream<PairRequest> get pairRequests => _pairReq.stream;

  void approve(String id) {
    if (_pairStatus[id] != 'pending') return;
    _pairStatus[id] = 'approved';
    _pairLink[id] = '/${tokens.issue()}';
  }

  void deny(String id) {
    if (_pairStatus[id] == 'pending') _pairStatus[id] = 'denied';
  }

  Stream<TransferProgress> get progress => _progress.stream;

  /// The link a QR code carries; null before [start].
  Uri? get link => _link;

  Future<Uri> start() async {
    final addr = bindAddress ?? await pickLanAddress();
    _server = await _bind(addr);
    _server!.listen(_handle);
    _addr = addr;
    if (identity != null) await _startRedirect(addr);
    _token = tokens.issue();
    _resetIdle();
    final base = '${addr.address}:${_server!.port}/$_token';
    return _link = identity == null
        ? Uri.parse('http://$base')
        : Uri.parse('https://$base?fp=${identity!.fingerprint}');
  }

  Future<void> _startRedirect(InternetAddress addr) async {
    try {
      _redirect = await HttpServer.bind(addr, httpRedirectPort);
    } on SocketException {
      // port taken: fall back to any free port; the address then shows it
      _redirect = await HttpServer.bind(addr, 0);
    }
    _redirect!.listen((req) async {
      _resetIdle();
      req.response.statusCode = HttpStatus.found;
      req.response.headers.set('location', 'https://${addr.address}:${_server?.port}/');
      await req.response.close();
    });
  }

  /// Plain-http entry that redirects to the secure page; null without TLS.
  Uri? get httpUri => _redirect == null
      ? null
      : Uri(scheme: 'http', host: _addr!.address, port: _redirect!.port);

  /// What a person types on a phone: the address, with the port only if needed.
  String get shortAddress {
    final r = _redirect;
    if (r == null) return '${_addr?.address}:${_server?.port}';
    return r.port == 80 ? _addr!.address : '${_addr!.address}:${r.port}';
  }

  Future<HttpServer> _bind(InternetAddress addr) async {
    Future<HttpServer> b(int port) => identity == null
        ? HttpServer.bind(addr, port)
        : HttpServer.bindSecure(addr, port, identity!.context);
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

  /// Stops listening. [force] ends running downloads too; without it the
  /// server stops taking new connections and lets running downloads finish
  /// (forced anyway after two minutes).
  Future<void> stop({bool force = true}) async {
    _idleTimer?.cancel();
    final s = _server;
    final r = _redirect;
    _server = null;
    _redirect = null;
    await r?.close(force: true);
    if (force) {
      await s?.close(force: true);
    } else if (s != null) {
      unawaited(s.close());
      Timer(const Duration(minutes: 2), () => s.close(force: true));
    }
  }

  Future<void> _handle(HttpRequest req) async {
    _resetIdle();
    final seg = req.uri.pathSegments;
    try {
      if (seg.isEmpty || (seg.length == 1 && seg[0].isEmpty)) return await _joinPage(req);
      if (seg.length == 1 && seg[0] == 'join') return await _join(req);
      if (seg.isNotEmpty && seg[0] == 'pair') return await _pair(req, seg);
      if (seg.length == 1 && seg[0].isNotEmpty) {
        final want = pairingCode;
        if (want != null &&
            !codesMatch(want, req.uri.queryParameters['code'] ?? '')) {
          unawaited(stop());
          return await _reply(req, 403);
        }
        if (!tokens.consume(seg[0])) return await _reply(req, 403);
        _session = _randomId();
        return await _manifest(req);
      }
      if (seg.length == 4 && seg[0] == 's' && seg[2] == 'f' && seg[1] == _session) {
        final i = int.tryParse(seg[3]);
        if (i != null && i >= 0 && i < files.length) return await _file(req, i);
      }
      return await _reply(req, 404);
    } catch (_) {
      // a failure while answering (e.g. a file vanished) must never leave the phone waiting
      try {
        await _reply(req, 500);
      } catch (_) {
        // response already started or closed
      }
    }
  }

  /// Typed-code entry for phones that cannot scan the QR.
  Future<void> _joinPage(HttpRequest req, [JoinState state = JoinState.fresh, int code = 200]) async {
    req.response
      ..statusCode = code
      ..headers.contentType = ContentType.html
      ..write(joinPage(state));
    await req.response.close();
  }

  Future<void> _join(HttpRequest req) async {
    if (_badCodes >= 5) return _joinPage(req, JoinState.locked, 429);
    final code = req.uri.queryParameters['code'] ?? '';
    if (!codesMatch(accessCode, code)) {
      _badCodes++;
      return _joinPage(req, JoinState.wrong, 403);
    }
    req.response.statusCode = HttpStatus.found;
    req.response.headers.set('location', '/$_token');
    await req.response.close();
  }

  Future<void> _pair(HttpRequest req, List<String> seg) async {
    Map<String, Object?> body;
    if (seg.length == 1) {
      final id = _randomId();
      final code = identity == null ? newPairingCode() : sasCode(identity!.der, id);
      _pairStatus[id] = 'pending';
      _pairReq.add(PairRequest(id, code));
      body = {'id': id, 'code': code};
    } else if (seg.length == 2 && _pairStatus.containsKey(seg[1])) {
      final id = seg[1];
      body = {'status': _pairStatus[id], 'link': _pairLink[id]};
    } else {
      return _reply(req, 404);
    }
    req.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }

  Future<void> _manifest(HttpRequest req) async {
    final List<Map<String, Object>> list = [
      for (var i = 0; i < files.length; i++)
        {
          'name': files[i].uri.pathSegments.last,
          'size': files[i].lengthSync(),
          'url': '/s/$_session/f/$i',
        }
    ];
    final wantsHtml =
        (req.headers.value('accept') ?? '').contains('text/html');
    if (wantsHtml) {
      req.response
        ..headers.contentType = ContentType.html
        ..write(_page(list));
    } else {
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'session': _session, 'files': list}));
    }
    await req.response.close();
  }

  String _page(List<Map<String, Object>> list) => downloadPage([
        for (final f in list)
          WebFile(f['name'] as String, f['size'] as int, f['url'] as String)
      ]);

  Future<void> _file(HttpRequest req, int i) async {
    final f = files[i];
    final name = f.uri.pathSegments.last;
    if (!f.existsSync()) {
      _progress.add(TransferProgress(TransferState.failed, name: name));
      return _reply(req, 404);
    }
    final total = f.lengthSync();
    final grand = _grandTotal();
    var sent = 0;
    var lastEmit = -1000;
    final clock = Stopwatch()..start();
    void emit() {
      _progress.add(TransferProgress(TransferState.active,
          sent: sent,
          total: total,
          name: name,
          overallSent: _sentTotal > grand ? grand : _sentTotal,
          overallTotal: grand));
    }

    req.response
      ..headers.contentType = ContentType.binary
      ..headers.set('Content-Disposition',
          'attachment; filename*=UTF-8''${Uri.encodeComponent(name)}')
      ..contentLength = total;
    try {
      await req.response.addStream(f.openRead().map((c) {
        sent += c.length;
        _sentTotal += c.length;
        // a screen cannot use thousands of updates a second; ten is plenty
        if (clock.elapsedMilliseconds - lastEmit >= 100) {
          lastEmit = clock.elapsedMilliseconds;
          emit();
        }
        return c;
      }));
      await req.response.close();
      emit(); // final figure for this file
    } catch (_) {
      _progress.add(TransferProgress(TransferState.failed, name: name));
      return;
    }
    _finished.add(i);
    if (_finished.length == files.length) {
      _progress.add(const TransferProgress(TransferState.done));
      // the phone may still be receiving the tail of the last file: stop gently
      unawaited(Future.delayed(const Duration(milliseconds: 200), () => stop(force: false)));
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
