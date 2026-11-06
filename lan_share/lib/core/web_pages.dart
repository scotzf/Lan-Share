import 'dart:convert';

/// Pages a phone browser sees. Kept free of server code so they are easy to test.

class WebFile {
  const WebFile(this.name, this.size, this.url);
  final String name;
  final int size;
  final String url;
}

enum JoinState { fresh, wrong, locked }

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  if (bytes < 1024 * 1024 * 1024) {
    return mb >= 100 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
  }
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}

const _text = HtmlEscape(HtmlEscapeMode.element);
const _attr = HtmlEscape(HtmlEscapeMode.attribute);

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 || dot == name.length - 1 ? '' : name.substring(dot + 1).toLowerCase();
}

String _kind(String ext) {
  if (const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'bmp'}.contains(ext)) return 'image';
  if (const {'mp4', 'mkv', 'mov', 'avi', 'webm'}.contains(ext)) return 'video';
  if (const {'mp3', 'wav', 'flac', 'm4a', 'ogg'}.contains(ext)) return 'audio';
  if (ext == 'pdf') return 'pdf';
  if (const {'zip', 'rar', '7z', 'tar', 'gz'}.contains(ext)) return 'archive';
  if (const {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md'}.contains(ext)) return 'doc';
  return 'other';
}

const _logo = r'''<svg class="logo" viewBox="0 0 64 64" aria-hidden="true">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3B82F6"/><stop offset="1" stop-color="#8B5CF6"/></linearGradient></defs>
<rect width="64" height="64" rx="15" fill="url(#g)"/>
<path d="M28.8 19.2H44.8V35.2M44.8 19.2L26.9 37.1" stroke="#fff" stroke-width="6.4" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
<g fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="butt">
<path d="M10 48A6 6 0 0 1 16 54" opacity=".95"/><path d="M10 42A12 12 0 0 1 22 54" opacity=".65"/><path d="M10 36A18 18 0 0 1 28 54" opacity=".4"/></g>
</svg>''';

const _downIcon = r'''<svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v11m0 0-5-5m5 5 5-5M5 20h14"/></svg>''';

const _phoneIcon = r'''<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="2.5" width="12" height="19" rx="3"/><path d="M12 8v6m0 0-2.5-2.5M12 14l2.5-2.5"/></svg>''';

const _css = r'''
:root{--bg:#0b1220;--card:#151e33;--fg:#f8fafc;--muted:#94a3b8;--glow:.38;--shadow:rgba(0,0,0,.28)}
@media (prefers-color-scheme:light){:root{--bg:#f3f6fc;--card:#fff;--fg:#0f172a;--muted:#64748b;--glow:.2;--shadow:rgba(30,58,138,.14)}}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{margin:0;min-height:100vh;color:var(--fg);font:16px/1.3 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;
background:radial-gradient(120% 60% at 50% -8%,rgba(59,130,246,var(--glow)),var(--bg) 62%) no-repeat,var(--bg)}
main{max-width:480px;margin:0 auto;padding:28px 16px 40px}
main.c{min-height:100vh;display:flex;flex-direction:column;justify-content:center;padding-bottom:14vh}
.logo{display:block;width:72px;height:72px;margin:0 auto 28px;filter:drop-shadow(0 10px 28px rgba(99,102,241,.55))}
.f{display:flex;align-items:center;gap:14px;padding:14px;margin-bottom:12px;border-radius:24px;
background:var(--card);color:inherit;text-decoration:none;box-shadow:0 8px 24px var(--shadow);transition:transform .12s}
.f:active{transform:scale(.97)}
.tile{flex:none;display:grid;place-items:center;width:54px;height:54px;border-radius:16px;
font-weight:800;font-size:13px;letter-spacing:.04em;color:#fff;background:#94a3b8}
.t-image{background:#8b5cf6}.t-video{background:#ef4444}.t-audio{background:#f59e0b}
.t-pdf{background:#f97316}.t-archive{background:#f59e0b}.t-doc{background:#3b82f6}
.meta{flex:1;min-width:0;display:flex;flex-direction:column;gap:4px}
.meta b{font-weight:650;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.meta i{font-style:normal;font-size:13px;color:var(--muted)}
.dl{flex:none;display:grid;place-items:center;width:48px;height:48px;border-radius:50%;background:#22c55e;color:#04210f}
.all{width:100%;height:60px;margin-top:8px;border:0;border-radius:22px;background:#22c55e;color:#04210f;
font:800 18px system-ui;display:flex;align-items:center;justify-content:center;gap:10px;box-shadow:0 10px 30px rgba(34,197,94,.35)}
.all:active{transform:scale(.97)}
.app{display:flex;align-items:center;justify-content:center;gap:10px;margin-top:24px;padding:14px;border-radius:20px;
color:var(--muted);text-decoration:none;font-weight:600;border:2px dashed rgba(148,163,184,.4)}
form{display:flex;gap:12px;justify-content:center;margin:8px auto 0;max-width:420px}
input{flex:1;min-width:0;max-width:300px;font:800 30px system-ui;letter-spacing:.22em;text-align:center;padding:14px 4px 14px 14px;
border-radius:22px;border:2px solid #3b82f6;background:var(--card);color:inherit;outline:none;box-shadow:0 0 34px rgba(59,130,246,.3)}
input:focus{border-color:#60a5fa}
.go{width:64px;border:0;border-radius:22px;background:#22c55e;color:#04210f}
.err input{border-color:#ef4444;box-shadow:0 0 34px rgba(239,68,68,.35);animation:shake .4s}
.err .go{background:#ef4444;color:#fff}
.lock{display:grid;place-items:center;width:120px;height:120px;margin:24px auto;border-radius:50%;
background:rgba(239,68,68,.16);color:#ef4444}
@keyframes shake{20%,60%{transform:translateX(-8px)}40%,80%{transform:translateX(8px)}}
@media (prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important}}
''';

String _shell(String body, {bool center = false}) => '<!doctype html><html lang="en"><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '<meta name="theme-color" content="#0b1220" media="(prefers-color-scheme:dark)">'
    '<meta name="theme-color" content="#f3f6fc" media="(prefers-color-scheme:light)"><title>LAN Share</title>'
    '<style>$_css</style><main${center ? ' class="c"' : ''}>$_logo$body</main></html>';

/// Page listing the shared files, one tap to save each, or all at once.
String downloadPage(List<WebFile> files, {String? appLink}) {
  final rows = files.map((f) {
    final ext = _ext(f.name);
    final label = ext.isEmpty ? 'FILE' : (ext.length > 4 ? ext.substring(0, 4) : ext).toUpperCase();
    return '<a class="f" href="${_attr.convert(f.url)}" download>'
        '<span class="tile t-${_kind(ext)}">$label</span>'
        '<span class="meta"><b>${_text.convert(f.name)}</b><i>${formatSize(f.size)}</i></span>'
        '<span class="dl">$_downIcon</span></a>';
  }).join();
  final all = files.length > 1
      ? '<button class="all" onclick="saveAll()">$_downIcon Save all</button>'
          '<script>function saveAll(){var a=document.querySelectorAll("a.f"),i=0;'
          '(function n(){if(i<a.length){a[i++].click();setTimeout(n,800)}})()}</script>'
      : '';
  final app = appLink == null
      ? ''
      : '<a class="app" href="${_attr.convert(appLink)}" download>$_phoneIcon Android app</a>';
  return _shell('$rows$all$app');
}

/// Typed-code entry; the error and lock states are shown, not explained.
String joinPage([JoinState state = JoinState.fresh]) {
  if (state == JoinState.locked) {
    return _shell('<div class="lock"><svg viewBox="0 0 24 24" width="56" height="56" fill="none" '
        'stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">'
        '<rect x="5" y="11" width="14" height="9" rx="2.5"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg></div>', center: true);
  }
  final cls = state == JoinState.wrong ? ' class="err"' : '';
  return _shell('<form action="/join" method="get"$cls>'
      '<input name="code" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="off" autofocus>'
      '<button class="go" aria-label="Go"><svg viewBox="0 0 24 24" width="30" height="30" fill="none" '
      'stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M5 12h14m0 0-6-6m6 6-6 6"/></svg></button></form>', center: true);
}
