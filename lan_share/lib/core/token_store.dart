import 'dart:math';

/// Single-use tokens that expire after [ttl].
class TokenStore {
  TokenStore({this.ttl = const Duration(minutes: 5), DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;
  final Map<String, DateTime> _issued = {};
  final Random _rng = Random.secure();

  String issue() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    final token = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _issued[token] = _now();
    return token;
  }

  /// True exactly once for a live token; false if used, expired or unknown.
  bool consume(String token) {
    final at = _issued.remove(token);
    if (at == null) return false;
    return !_now().isAfter(at.add(ttl));
  }
}
