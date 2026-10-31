import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/token_store.dart';

void main() {
  test('consume succeeds once', () {
    final s = TokenStore();
    final t = s.issue();
    expect(s.consume(t), isTrue);
  });
  test('second consume fails', () {
    final s = TokenStore();
    final t = s.issue();
    s.consume(t);
    expect(s.consume(t), isFalse);
  });
  test('expired token fails', () {
    var now = DateTime(2026, 1, 1);
    final s = TokenStore(now: () => now);
    final t = s.issue();
    now = now.add(const Duration(minutes: 5, seconds: 1));
    expect(s.consume(t), isFalse);
  });
  test('unknown token fails', () {
    expect(TokenStore().consume('nope'), isFalse);
  });
}
