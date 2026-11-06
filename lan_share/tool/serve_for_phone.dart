// Serves files like the laptop app does and prints what a phone would scan.
// Run from lan_share/:  dart run tool/serve_for_phone.dart <file> [more files]
// Optional:  --hotspot=<ssid>,<pass>,<ip>   adds a hotspot hint to the printed payload.
import 'dart:async';
import 'dart:io';

import 'package:lan_share/core/hotspot.dart';
import 'package:lan_share/core/identity.dart';
import 'package:lan_share/core/qr_payload.dart';
import 'package:lan_share/core/sender_server.dart';
import 'package:lan_share/core/token_store.dart';

Future<void> main(List<String> args) async {
  final files = [for (final a in args.where((a) => !a.startsWith('--'))) File(a)];
  final hs = args.where((a) => a.startsWith('--hotspot=')).map((a) => a.substring(10).split(',')).firstOrNull;
  final dir = Directory('${Directory.systemTemp.path}/lanshare_serve_id')..createSync(recursive: true);
  final identity = await loadOrCreateIdentity(dir);
  final server = SenderServer(files, TokenStore(), identity: identity, bindAll: true, idle: const Duration(minutes: 20));
  final link = await server.start();
  final hotspot = hs == null ? null : HotspotInfo(hs[0], hs[1], hs[2], true);
  stdout.writeln('PAYLOAD ${qrPayload(link, hotspot: hotspot)}');
  stdout.writeln('READY');
  server.progress.listen((p) => stdout.writeln('PROGRESS ${p.state.name} ${p.overallSent}/${p.overallTotal}'));
  await Completer<void>().future; // until killed
}
