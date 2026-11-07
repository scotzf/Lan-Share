import 'dart:convert';
import 'dart:io';

/// Small remembered choices, kept in settings.json inside the app's own folder.
class Settings {
  Settings({this.hotspotAssist = true, this.fastMode = false});

  /// Start the hotspot while sharing so the Android app can join without the
  /// phone being on the same Wi-Fi.
  bool hotspotAssist;

  /// Share over plain HTTP: faster, and no browser certificate warning, but nothing is
  /// encrypted, so anyone on the same network who sees the link could download the files.
  /// Off by default: the user turns it on on purpose.
  bool fastMode;

  static File _file(Directory dir) => File('${dir.path}${Platform.pathSeparator}settings.json');

  static Future<Settings> load(Directory dir) async {
    try {
      final j = jsonDecode(await _file(dir).readAsString());
      if (j is Map) {
        // each key is read on its own, so one bad value never changes the others
        return Settings(
          hotspotAssist: j['hotspotAssist'] is bool ? j['hotspotAssist'] as bool : true,
          fastMode: j['fastMode'] is bool ? j['fastMode'] as bool : false,
        );
      }
    } catch (_) {
      // missing or unreadable: use the defaults
    }
    return Settings();
  }

  Future<void> save(Directory dir) async {
    await dir.create(recursive: true);
    await _file(dir).writeAsString(jsonEncode({'hotspotAssist': hotspotAssist, 'fastMode': fastMode}));
  }
}
