/// Reduces a sender-supplied name to a plain file name that is unique in [taken].
String safeName(String raw, Set<String> taken) {
  var name = raw.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'[\x00-\x1f:*?"<>|]'), '').trim();
  if (name.isEmpty || RegExp(r'^\.+$').hasMatch(name)) name = 'file';
  if (!taken.contains(name)) return name;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var n = 2;; n++) {
    final c = '$base ($n)$ext';
    if (!taken.contains(c)) return c;
  }
}
