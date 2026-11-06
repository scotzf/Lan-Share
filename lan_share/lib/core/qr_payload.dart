import 'hotspot.dart';

/// The same URL with no fragment at all (Uri.replace(fragment: '') leaves a stray '#').
Uri _bare(Uri u, {String? host}) => Uri(
      scheme: u.scheme,
      host: host ?? u.host,
      port: u.hasPort ? u.port : null,
      path: u.path,
      query: u.hasQuery && u.query.isNotEmpty ? u.query : null,
    );

/// What a QR code carries: the secure share link, plus (when the laptop's hotspot
/// is up) how to join it, hidden in the link's fragment so browsers ignore it.
class QrPayload {
  const QrPayload(this.link, this.hotspot);
  final Uri link;
  final HotspotInfo? hotspot;

  /// The same share link, reached through the hotspot address.
  Uri? get hotspotLink {
    final h = hotspot;
    return h == null ? null : _bare(link, host: h.ip);
  }
}

String qrPayload(Uri link, {HotspotInfo? hotspot}) {
  if (hotspot == null) return link.toString();
  final fragment = Uri(queryParameters: {'hs': hotspot.ssid, 'hp': hotspot.pass, 'hip': hotspot.ip}).query;
  return link.replace(fragment: fragment).toString();
}

/// Null when the text is not one of our links.
QrPayload? parseQrPayload(String text) {
  final u = Uri.tryParse(text.trim());
  if (u == null || !(u.scheme == 'https' || u.scheme == 'http') || u.host.isEmpty) return null;
  HotspotInfo? hs;
  if (u.hasFragment && u.fragment.isNotEmpty) {
    try {
      final f = Uri.splitQueryString(u.fragment);
      final ssid = f['hs'], pass = f['hp'], ip = f['hip'];
      if (ssid != null && ssid.isNotEmpty && pass != null && pass.isNotEmpty && ip != null && ip.isNotEmpty) {
        hs = HotspotInfo(ssid, pass, ip, true);
      }
    } on FormatException {
      hs = null;
    }
  }
  return QrPayload(_bare(u), hs);
}
