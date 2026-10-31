import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/pairing.dart';

void main() {
  test('code is 4 digits', () {
    for (var i = 0; i < 50; i++) {
      expect(newPairingCode(), matches(RegExp(r'^\d{4}$')));
    }
  });
  test('same code+salt gives same key', () async {
    final a = await deriveSessionKey('1234', [1, 2, 3]);
    final b = await deriveSessionKey('1234', [1, 2, 3]);
    expect(await a.extractBytes(), await b.extractBytes());
  });
  test('different code gives different key', () async {
    final a = await deriveSessionKey('1234', [1, 2, 3]);
    final b = await deriveSessionKey('1235', [1, 2, 3]);
    expect(await a.extractBytes(), isNot(await b.extractBytes()));
  });
  test('codesMatch false on mismatch', () {
    expect(codesMatch('1234', '1234'), isTrue);
    expect(codesMatch('1234', '4321'), isFalse);
  });
}
