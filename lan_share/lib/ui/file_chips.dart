import 'package:flutter/material.dart';
import 'theme.dart';

(IconData, Color) fileLook(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  if (const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'bmp'}.contains(ext)) {
    return (Icons.image_rounded, C.violet);
  }
  if (const {'mp4', 'mkv', 'mov', 'avi', 'webm'}.contains(ext)) {
    return (Icons.movie_rounded, C.red);
  }
  if (const {'mp3', 'wav', 'flac', 'm4a', 'ogg'}.contains(ext)) {
    return (Icons.music_note_rounded, C.amber);
  }
  if (ext == 'pdf') return (Icons.picture_as_pdf_rounded, const Color(0xFFF97316));
  if (const {'zip', 'rar', '7z', 'tar', 'gz'}.contains(ext)) {
    return (Icons.folder_zip_rounded, C.amber);
  }
  if (const {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md'}.contains(ext)) {
    return (Icons.description_rounded, C.blue);
  }
  return (Icons.insert_drive_file_rounded, const Color(0xFF94A3B8));
}

/// Overlapping colour-coded file-type tiles plus the count.
class FileChips extends StatelessWidget {
  const FileChips({super.key, required this.names, required this.count, required this.color});
  final List<String> names;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final shown = names.take(3).toList();
    const tile = 44.0, overlap = 10.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (shown.isNotEmpty)
          SizedBox(
            width: tile + (shown.length - 1) * (tile - overlap),
            height: tile,
            child: Stack(children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: i * (tile - overlap),
                  child: _Tile(look: fileLook(shown[i]), size: tile),
                ),
            ]),
          )
        else
          Icon(Icons.insert_drive_file_rounded, color: color),
        const SizedBox(width: 12),
        Text('$count', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.look, required this.size});
  final (IconData, Color) look;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: look.$2,
          border: Border.all(color: C.bg, width: 3),
        ),
        child: Icon(look.$1, size: size * .5, color: Colors.white),
      );
}
