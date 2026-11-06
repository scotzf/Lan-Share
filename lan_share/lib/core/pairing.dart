import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
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

/// Short authentication string: both sides derive the same 4 digits from the
/// certificate they see plus the pairing id. A man in the middle presents a
/// different certificate, so the two screens show different codes.
String sasCode(List<int> certDer, String pairId) {
  final h = sha256.convert([...certDer, ...utf8.encode(pairId)]).bytes;
  final n = (h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3];
  return (n % 10000).toString().padLeft(4, '0');
}
