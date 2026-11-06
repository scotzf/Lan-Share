
import 'package:flutter/material.dart';

import 'theme.dart';

/// Rings that expand and fade behind [child]; shows "searching" without words.
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.color, required this.size, required this.child});
  final Color color;
  final double size;
  final Widget child;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(alignment: Alignment.center, children: [
        if (!reduce)
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              size: Size.square(widget.size),
              painter: _RingsPainter(_c.value, widget.color),
            ),
          ),
        widget.child,
      ]),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      final radius = size.width / 2 * (0.62 + 0.38 * p);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color.withValues(alpha: 0.35 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.color != color;
}

/// Thin arc that drains clockwise; the remaining life of a QR code.
class ExpiryArc extends StatelessWidget {
  const ExpiryArc({super.key, required this.remaining, required this.color, required this.child});
  final double remaining; // 1 -> 0
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        foregroundPainter: _ArcPainter(remaining.clamp(0.0, 1.0), color),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      );
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.remaining, this.color);
  final double remaining;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(4);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(38));
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = color.withValues(alpha: .18);
    canvas.drawRRect(rrect, track);
    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..color = color;
    canvas.drawPath(metric.extractPath(0, metric.length * remaining), progress);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.remaining != remaining || old.color != color;
}

/// Radial colour wash behind a screen; the colour tracks the state.
class GlowBackground extends StatelessWidget {
  const GlowBackground({super.key, required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 1.1,
          colors: [color.withValues(alpha: pal.glow), pal.bg],
          stops: const [0, 0.85],
        ),
      ),
      child: child,
    );
  }
}
