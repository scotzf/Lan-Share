import 'dart:io';

bool _isPrivate(InternetAddress a) {
  final b = a.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

bool _isVirtual(String name) => RegExp(
        r'vethernet|virtual|vmware|vbox|hyper-v|docker|tun|tap|vpn|wsl|loopback|bluetooth',
        caseSensitive: false)
    .hasMatch(name);

/// Prefers a private IPv4 on a physical adapter; falls back to any private
/// IPv4, then loopback.
Future<InternetAddress> pickLanAddress() async {
  final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4, includeLoopback: false);
  InternetAddress? fallback;
  for (final i in ifaces) {
    for (final a in i.addresses.where(_isPrivate)) {
      if (!_isVirtual(i.name)) return a;
      fallback ??= a;
    }
  }
  return fallback ?? InternetAddress.loopbackIPv4;
}
