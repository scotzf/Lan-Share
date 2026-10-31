import 'dart:math';
import 'package:cryptography/cryptography.dart';

String newPairingCode() =>
    Random.secure().nextInt(10000).toString().padLeft(4, '0');

Future<SecretKey> deriveSessionKey(String code, List<int> salt) {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );
  return pbkdf2.deriveKeyFromPassword(password: code, nonce: salt);
}

/// Constant-time comparison.
bool codesMatch(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
