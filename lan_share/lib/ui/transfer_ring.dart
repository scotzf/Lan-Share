import 'package:flutter/material.dart';
import 'theme.dart';

enum Phase { waiting, active, done, failed, expired }

Color phaseColor(Phase p) => switch (p) {
      Phase.waiting => C.blue,
      Phase.active => C.blue,
      Phase.done => C.green,
      Phase.failed => C.red,
      Phase.expired => C.amber,
    };

IconData phaseIcon(Phase p) => switch (p) {
      Phase.waiting => Icons.wifi_tethering,
      Phase.active => Icons.south,
      Phase.done => Icons.check_rounded,
      Phase.failed => Icons.close_rounded,
      Phase.expired => Icons.timer_off_outlined,
    };

/// Progress ring: fills while active, then shows a state icon.
class TransferRing extends StatelessWidget {
  const TransferRing({super.key, required this.phase, this.fraction = 0, this.size = 180});
  final Phase phase;
  final double fraction;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = phaseColor(phase);
    final value = switch (phase) {
      Phase.active => fraction.clamp(0.0, 1.0),
      Phase.done => 1.0,
      _ => 0.0,
    };
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: 1,
            strokeWidth: 14,
            color: color.withValues(alpha: .15),
          ),
        ),
        SizedBox.expand(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: value),
            duration: const Duration(milliseconds: 250),
            builder: (_, v, __) => CircularProgressIndicator(
              value: v,
              strokeWidth: 14,
              strokeCap: StrokeCap.round,
              color: color,
            ),
          ),
        ),
        Icon(phaseIcon(phase), size: size * .38, color: color),
      ]),
    );
  }
}
