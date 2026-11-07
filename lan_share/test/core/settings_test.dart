import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/settings.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('st_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('hotspot assist is on by default', () async {
    expect((await Settings.load(dir)).hotspotAssist, isTrue);
  });

  test('a saved choice is remembered', () async {
    final s = await Settings.load(dir);
    s.hotspotAssist = false;
    await s.save(dir);
    expect((await Settings.load(dir)).hotspotAssist, isFalse);
    s.hotspotAssist = true;
    await s.save(dir);
    expect((await Settings.load(dir)).hotspotAssist, isTrue);
  });

  test('a corrupt or odd file falls back to the defaults', () async {
    File('${dir.path}/settings.json').writeAsStringSync('{not json');
    expect((await Settings.load(dir)).hotspotAssist, isTrue);
    File('${dir.path}/settings.json').writeAsStringSync('{"hotspotAssist":"maybe"}');
    expect((await Settings.load(dir)).hotspotAssist, isTrue);
    File('${dir.path}/settings.json').writeAsStringSync('[1,2]');
    expect((await Settings.load(dir)).hotspotAssist, isTrue);
  });

  test('saving creates the folder if needed', () async {
    final nested = Directory('${dir.path}/a/b');
    final s = await Settings.load(nested);
    s.hotspotAssist = false;
    await s.save(nested);
    expect((await Settings.load(nested)).hotspotAssist, isFalse);
  });

  group('fast mode', () {
    test('is off by default: sharing stays encrypted until the user flips it', () async {
      expect((await Settings.load(dir)).fastMode, isFalse);
    });

    test('a saved choice is remembered, independent of hotspot assist', () async {
      final s = await Settings.load(dir);
      s.fastMode = true;
      s.hotspotAssist = false;
      await s.save(dir);
      final back = await Settings.load(dir);
      expect(back.fastMode, isTrue);
      expect(back.hotspotAssist, isFalse);
    });

    test('old settings files without the new key still load, with encryption on', () async {
      File('${dir.path}/settings.json').writeAsStringSync('{"hotspotAssist":false}');
      final s = await Settings.load(dir);
      expect(s.hotspotAssist, isFalse);
      expect(s.fastMode, isFalse);
    });

    test('a wrong type for the key falls back to encrypted', () async {
      File('${dir.path}/settings.json').writeAsStringSync('{"hotspotAssist":true,"fastMode":"yes"}');
      final s = await Settings.load(dir);
      expect(s.fastMode, isFalse);
      expect(s.hotspotAssist, isTrue);
    });
  });
}
