import 'dart:convert';
import 'dart:io';

/// Small remembered choices, kept in settings.json inside the app's own folder.
class Settings {
  Settings({this.hotspotAssist = true});

  /// Start the hotspot while sharing so the Android app can join without the
  /// phone being on the same Wi-Fi.
  bool hotspotAssist;

  static File _file(Directory dir) => File('${dir.path}${Platform.pathSeparator}settings.json');

  static Future<Settings> load(Directory dir) async {
    try {
      final j = jsonDecode(await _file(dir).readAsString());
      if (j is Map && j['hotspotAssist'] is bool) {
        return Settings(hotspotAssist: j['hotspotAssist'] as bool);
      }
    } catch (_) {
      // missing or unreadable: use the defaults
    }
    return Settings();
  }

  Future<void> save(Directory dir) async {
    await dir.create(recursive: true);
    await _file(dir).writeAsString(jsonEncode({'hotspotAssist': hotspotAssist}));
  }
}
