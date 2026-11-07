import 'dart:io';

import 'identity.dart';
import 'sender_server.dart';
import 'token_store.dart';

/// Serves just the Android app file for a few minutes, so a phone can scan a QR and install it.
/// Nothing else is shared; the server stops by itself after [idle].
class AppShare {
  AppShare(this.apk, this.identity, {this.bindAddress, this.idle = const Duration(minutes: 5)});

  final File apk;
  /// null = Fast mode: a plain http link, no certificate.
  final Identity? identity;
  final InternetAddress? bindAddress;
  final Duration idle;

  SenderServer? _server;
  Uri? _url;

  /// The link to put in the QR code. Starting twice returns the same link.
  Future<Uri> start() async {
    if (!apk.existsSync()) throw StateError('no app file at ${apk.path}');
    if (_server != null && _url != null) return _url!;
    final server = SenderServer(
      const [],
      TokenStore(),
      identity: identity,
      apk: apk,
      bindAll: bindAddress == null,
      bindAddress: bindAddress,
      idle: idle,
      httpRedirectPort: 0,
    );
    final link = await server.start();
    _server = server;
    return _url = Uri(scheme: link.scheme, host: link.host, port: link.port, path: '/app.apk');
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _url = null;
    await s?.stop();
  }
}
