import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/identity.dart';
import 'package:lan_share/core/pairing.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('id_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('creates an identity with a sha256 fingerprint', () async {
    final id = await loadOrCreateIdentity(dir);
    expect(id.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('second load reuses the same certificate', () async {
    final a = await loadOrCreateIdentity(dir);
    final b = await loadOrCreateIdentity(dir);
    expect(b.fingerprint, a.fingerprint);
  });

  test('corrupt files are replaced with a fresh identity', () async {
    await loadOrCreateIdentity(dir);
    File('${dir.path}/cert.pem').writeAsStringSync('garbage');
    final id = await loadOrCreateIdentity(dir);
    expect(id.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('sasCode is 4 digits, stable, and depends on cert and id', () {
    final c1 = [1, 2, 3], c2 = [9, 9, 9];
    expect(sasCode(c1, 'abc'), matches(RegExp(r'^\d{4}$')));
    expect(sasCode(c1, 'abc'), sasCode(c1, 'abc'));
    final codes = {sasCode(c1, 'abc'), sasCode(c2, 'abc'), sasCode(c1, 'xyz')};
    expect(codes.length, greaterThan(1));
  });
}
