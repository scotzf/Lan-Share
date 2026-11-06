import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// This device's TLS identity: a self-signed certificate created once and reused.
class Identity {
  Identity(this.context, this.der);
  final SecurityContext context;
  final List<int> der;

  /// SHA-256 of the certificate, lowercase hex. Pinned by receivers.
  String get fingerprint => sha256Hex(der);
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

Future<Identity> loadOrCreateIdentity(Directory dir) async {
  final certFile = File('${dir.path}${Platform.pathSeparator}cert.pem');
  final keyFile = File('${dir.path}${Platform.pathSeparator}key.pem');
  if (certFile.existsSync() && keyFile.existsSync()) {
    try {
      return _load(certFile.readAsStringSync(), keyFile.readAsStringSync());
    } catch (_) {
      // unreadable or corrupt: fall through and make a new one
    }
  }
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final priv = pair.privateKey as RSAPrivateKey;
  final pub = pair.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem({'CN': 'lan-share'}, priv, pub);
  final certPem = X509Utils.generateSelfSignedCertificate(priv, csr, 3650);
  final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(priv);
  await dir.create(recursive: true);
  certFile.writeAsStringSync(certPem);
  keyFile.writeAsStringSync(keyPem);
  return _load(certPem, keyPem);
}

Identity _load(String certPem, String keyPem) {
  final ctx = SecurityContext()
    ..useCertificateChainBytes(utf8.encode(certPem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));
  return Identity(ctx, CryptoUtils.getBytesFromPEMString(certPem));
}
