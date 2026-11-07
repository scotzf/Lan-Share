import 'package:flutter/material.dart';

/// Widest the main content gets, so a maximized window never stretches it.
const double kColumnMax = 560;

/// Side margin that grows with the window: tight at quarter-snap, roomy when maximized.
double gutterFor(double width) => width < 480 ? 16 : (width < 900 ? 24 : 32);

/// Centers [child] in a column no wider than [maxWidth].
class CenteredColumn extends StatelessWidget {
  const CenteredColumn({super.key, required this.child, this.maxWidth = kColumnMax});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
