import 'package:flutter/material.dart';

/// The one progress indicator of the phone app: a round track with a fill.
/// [value] null spins (waiting), a number fills it (determinate), as Material recommends
/// for a known size. [child] sits in the middle.
class MobileRing extends StatelessWidget {
  const MobileRing({super.key, required this.color, this.value, this.size = 240, this.child});
  final Color color;
  final double? value;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(
            child: CircularProgressIndicator(value: 1, strokeWidth: 16, color: color.withValues(alpha: .16)),
          ),
          SizedBox.expand(
            child: value == null
                ? CircularProgressIndicator(strokeWidth: 16, strokeCap: StrokeCap.round, color: color)
                : TweenAnimationBuilder<double>(
                    tween: Tween(end: value!.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 250),
                    builder: (_, v, __) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 16,
                      strokeCap: StrokeCap.round,
                      color: color,
                    ),
                  ),
          ),
          if (child != null) child!,
        ]),
      );
}
