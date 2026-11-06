import 'dart:async';
import 'dart:io';

import '../core/identity.dart';
import '../core/receiver_client.dart';
import '../core/transfer_progress.dart';
import 'receive_flow.dart';

/// Is our laptop answering at [link]? Checks `/ping` (never the one-time token) and that
/// the certificate is the one pinned in the QR, so a stranger at the same address is not trusted.
Future<bool> probeLink(Uri link) async {
  final fp = link.queryParameters['fp'];
  if (link.scheme != 'https' || fp == null || fp.length != 64) return false;
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2)
    ..badCertificateCallback = (cert, _, __) => sha256Hex(cert.der) == fp;
  try {
    final ping = Uri(scheme: 'https', host: link.host, port: link.port, path: '/ping');
    final res = await (await client.getUrl(ping)).close().timeout(const Duration(seconds: 3));
    await res.drain<void>();
    return res.statusCode == 204;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Downloads every file behind [link] into [dest] with the pinned, encrypted client.
Future<List<DownloadedFile>> downloadLink(
  Uri link,
  void Function(TransferProgress) onProgress,
  Directory dest,
) async {
  final client = ReceiverClient();
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
