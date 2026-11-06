import 'package:flutter/material.dart';

import 'pulse.dart';
import 'theme.dart';

/// Home: one big drop zone (drag files in, or click to pick) and a small Receive button.
class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.dragging, this.onPick, this.onReceive});
  final bool dragging;
  final VoidCallback? onPick, onReceive;

  @override
  Widget build(BuildContext context) {
    final accent = dragging ? C.green : C.blue;
    return GlowBackground(
      color: accent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Expanded(child: _DropZone(dragging: dragging, accent: accent, onTap: onPick)),
            const SizedBox(height: 16),
            _ReceiveButton(onTap: onReceive),
          ]),
        ),
      ),
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({required this.dragging, required this.accent, this.onTap});
  final bool dragging;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('drop'),
        borderRadius: BorderRadius.circular(36),
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedBorder(accent.withValues(alpha: dragging ? .95 : .55), 36),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              color: accent.withValues(alpha: dragging ? .16 : .06),
              boxShadow: [BoxShadow(color: pal.shadow, blurRadius: 30)],
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Pulse(
                  color: accent,
                  size: 340,
                  child: AnimatedScale(
                    scale: dragging ? 1.14 : 1,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: 132,
                      height: 132,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: dragging ? const [C.green, C.teal] : const [C.blue, C.violet],
                        ),
                        boxShadow: [BoxShadow(color: accent.withValues(alpha: .5), blurRadius: 36)],
                      ),
                      child: Icon(dragging ? Icons.add_rounded : Icons.north_rounded,
                          size: 70, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiveButton extends StatelessWidget {
  const _ReceiveButton({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [C.green, C.teal]),
          ),
          child: InkWell(
            key: const Key('receive'),
            onTap: onTap,
            child: const SizedBox(
              height: 64,
              width: double.infinity,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.south_rounded, color: Colors.black87, size: 28),
                SizedBox(width: 10),
                Text('Receive',
                    style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      );
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(1.5), Radius.circular(radius)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 22) {
        canvas.drawPath(m.extractPath(d, d + 12), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
