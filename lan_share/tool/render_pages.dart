// Writes sample phone pages to a folder so they can be previewed in a browser.
// Run from lan_share/:  dart run tool/render_pages.dart <output-dir>
import 'dart:io';

import 'package:lan_share/core/web_pages.dart';

void main(List<String> args) {
  final out = Directory(args.isEmpty ? 'build/pages' : args.first)..createSync(recursive: true);
  const files = [
    WebFile('Holiday photo.png', 2400000, '#'),
    WebFile('Trip video final cut.mp4', 734003200, '#'),
    WebFile('Report Q3.pdf', 1800000, '#'),
    WebFile('notes.txt', 900, '#'),
  ];
  File('${out.path}/download.html').writeAsStringSync(downloadPage(files));
  File('${out.path}/download1.html').writeAsStringSync(downloadPage([files.first]));
  File('${out.path}/join.html').writeAsStringSync(joinPage());
  File('${out.path}/join_wrong.html').writeAsStringSync(joinPage(JoinState.wrong));
  File('${out.path}/join_locked.html').writeAsStringSync(joinPage(JoinState.locked));
  stdout.writeln('wrote ${out.path}');
}
