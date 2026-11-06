import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'lan_address.dart';
import 'pairing.dart';
import 'token_store.dart';
import 'transfer_progress.dart';

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
      if (seg.isNotEmpty && seg[0] == 'pair') return _pair(req, seg);
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

  Future<void> _pair(HttpRequest req, List<String> seg) async {
    Map<String, Object?> body;
    if (seg.length == 1) {
      final id = _randomId();
      final code = newPairingCode();
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

  String _page(List<Map<String, Object>> list) {
    final esc = const HtmlEscape(HtmlEscapeMode.attribute);
    final rows = list.map((f) {
      final mb = ((f['size'] as int) / 1048576).toStringAsFixed(1);
      return '<a class="f" href="${esc.convert(f['url'] as String)}" download>'
          '<span class="i">&#x2B07;</span>'
          '<span class="n">${esc.convert(f['name'] as String)}</span>'
          '<span class="s">$mb MB</span></a>';
    }).join();
    return '<!doctype html><meta charset=utf-8>'
        '<meta name=viewport content="width=device-width,initial-scale=1">'
        '<title>Share</title><style>'
        'body{margin:0;padding:16px;font:16px system-ui;background:#0f172a;color:#f8fafc}'
        '.f{display:flex;align-items:center;gap:12px;padding:16px;margin-bottom:12px;'
        'border-radius:16px;background:#1e293b;color:inherit;text-decoration:none}'
        '.i{display:grid;place-items:center;width:40px;height:40px;border-radius:50%;'
        'background:#22c55e;color:#04210f;font-size:20px}'
        '.n{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}'
        '.s{opacity:.6;font-size:13px}</style>$rows';
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
