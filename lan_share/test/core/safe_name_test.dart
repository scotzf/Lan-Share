import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/safe_name.dart';

void main() {
  test('strips ../ and drive letters', () {
    expect(safeName('../../x.txt', {}), 'x.txt');
    expect(safeName(r'C:\evil.exe', {}), 'evil.exe');
    expect(safeName('/etc/passwd', {}), 'passwd');
  });
  test('renames duplicates', () {
    expect(safeName('a.txt', {'a.txt'}), 'a (2).txt');
    expect(safeName('a.txt', {'a.txt', 'a (2).txt'}), 'a (3).txt');
  });
  test('unicode and spaces preserved', () {
    expect(safeName('my 写真 🙂.jpg', {}), 'my 写真 🙂.jpg');
  });
  test('empty or dots fall back to a name', () {
    expect(safeName('..', {}), 'file');
    expect(safeName('', {}), 'file');
  });
}
