import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/args.dart';

void main() {
  test('paths with spaces and unicode parse intact', () {
    final d = Directory.systemTemp.createTempSync('ar_');
    addTearDown(() => d.deleteSync(recursive: true));
    final a = File('${d.path}/a b 写.txt')..writeAsStringSync('x');
    final b = File('${d.path}/c.txt')..writeAsStringSync('y');
    final files = parseSharedPaths([a.path, b.path]);
    expect(files.map((f) => f.path), [a.path, b.path]);
  });
  test('empty args and missing files are ignored', () {
    expect(parseSharedPaths([]), isEmpty);
    expect(parseSharedPaths(['Z:/nope/missing.txt']), isEmpty);
  });
}
