import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/core/web_pages.dart';

void main() {
  const files = [
    WebFile('photo & sun.png', 2400000, '/s/x/f/0'),
    WebFile('movie.mp4', 734003200, '/s/x/f/1'),
  ];

  test('download page lists files with escaped names, type tiles and sizes', () {
    final html = downloadPage(files);
    expect(html, contains('photo &amp; sun.png'));
    expect(html, contains('>PNG<'));
    expect(html, contains('>MP4<'));
    expect(html, contains('2.3 MB'));
    expect(html, contains('700 MB'));
    expect(html, contains('href="/s/x/f/0"'));
    expect(html, contains('download'));
  });

  test('Save all shows only with more than one file', () {
    expect(downloadPage(files), contains('Save all'));
    expect(downloadPage([files.first]), isNot(contains('Save all')));
  });

  test('each file type gets its own colour class', () {
    final html = downloadPage(files);
    expect(html, contains('t-image'));
    expect(html, contains('t-video'));
  });

  test('page carries the logo and is mobile friendly', () {
    final html = downloadPage(files);
    expect(html, contains('<svg'));
    expect(html, contains('width=device-width'));
  });

  test('join page has the numeric input; error and lock are visual states', () {
    expect(joinPage(), contains('inputmode="numeric"'));
    expect(joinPage(), isNot(contains('class="err"')));
    expect(joinPage(JoinState.wrong), contains('class="err"'));
    final locked = joinPage(JoinState.locked);
    expect(locked, contains('lock'));
    expect(locked, isNot(contains('<input')));
  });

  test('pages follow the phone light/dark setting', () {
    for (final html in [downloadPage(files), joinPage(), joinPage(JoinState.locked)]) {
      expect(html, contains('prefers-color-scheme:light'));
      expect(html, contains('var(--bg)'));
      expect(html, isNot(contains('background:#151e33')));
    }
  });

  test('sizes read naturally', () {
    expect(formatSize(0), '0 B');
    expect(formatSize(900), '900 B');
    expect(formatSize(2048), '2 KB');
    expect(formatSize(5 * 1024 * 1024 * 1024), '5.0 GB');
  });
}
