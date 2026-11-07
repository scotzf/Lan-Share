import 'dart:async';
import 'dart:io';

import '../core/identity.dart';
import '../core/receiver_client.dart';
import '../core/transfer_progress.dart';
import 'receive_flow.dart';

/// Is our laptop answering at [link]? Checks `/ping` (never the one-time token).
///
/// An encrypted (https) link must carry the certificate fingerprint from the QR, and the
/// laptop has to present exactly that certificate, so a stranger at the same address is not
/// trusted. A plain (http) link is what the laptop shows in Fast mode: no certificate exists
/// to check, by the user's choice.
Future<bool> probeLink(Uri link) async {
  final secure = link.scheme == 'https';
  if (!secure && link.scheme != 'http') return false;
  final fp = link.queryParameters['fp'];
  if (secure && (fp == null || fp.length != 64)) return false;
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2)
    ..badCertificateCallback = (cert, _, __) => secure && sha256Hex(cert.der) == fp;
  try {
    final ping = Uri(scheme: link.scheme, host: link.host, port: link.port, path: '/ping');
    final res = await (await client.getUrl(ping)).close().timeout(const Duration(seconds: 3));
    await res.drain<void>();
    return res.statusCode == 204;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Downloads every file behind [link] into [dest]: pinned and encrypted for https links,
/// plain for the http links of Fast mode.
Future<List<DownloadedFile>> downloadLink(
  Uri link,
  void Function(TransferProgress) onProgress,
  Directory dest,
) async {
  final client = ReceiverClient(allowInsecure: link.scheme == 'http');
  final sub = client.progress.listen(onProgress);
  try {
    final files = await client.receive(link, dest);
    return [
      for (final f in files) DownloadedFile(f.uri.pathSegments.last, f.lengthSync(), f.path),
    ];
  } finally {
    await sub.cancel();
  }
}
