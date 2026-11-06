import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../core/web_pages.dart' show formatSize;
import '../ui/file_chips.dart';
import '../ui/pulse.dart';
import '../ui/theme.dart';
import 'mobile_ring.dart';
import 'receive_flow.dart';

/// What the phone shows while it receives: pure presentation of a [ReceiveFlow] state.
/// Type scale 56 / 24 / 16 / 13, spacing on an 8-point grid, main action in the thumb zone.
class ReceiveView extends StatelessWidget {
  const ReceiveView({
    super.key,
    required this.phase,
    this.problem = FlowProblem.none,
    this.fraction = 0,
    this.speedMBps,
    this.names = const [],
    this.fileCount = 0,
    this.totalBytes = 0,
    this.onOpen,
    this.onDone,
    this.onScan,
    this.onClose,
  });

  final FlowPhase phase;
  final FlowProblem problem;
  final double fraction;
  final double? speedMBps;
  final List<String> names;
  final int fileCount, totalBytes;
  final VoidCallback? onOpen, onDone, onScan, onClose;

  Color get _color => switch (phase) {
        FlowPhase.joining => C.violet,
        FlowPhase.done => C.green,
        FlowPhase.failed => C.red,
        FlowPhase.invalid => C.amber,
        FlowPhase.offline => C.slate,
        _ => C.blue,
      };

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return GlowBackground(
      color: _color,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton.filledTonal(
                key: const Key('close'),
                onPressed: onClose,
                iconSize: 24,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(child: Center(child: _hero(context, pal))),
            _actions(),
          ]),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, Pal pal) {
    switch (phase) {
      case FlowPhase.idle:
      case FlowPhase.connecting:
        return MobileRing(
          key: const Key('ring'),
          color: C.blue,
          child: const Icon(Icons.wifi_rounded, size: 88, color: C.blue),
        );
      case FlowPhase.joining:
        return MobileRing(
          key: const Key('ring'),
          color: C.violet,
          child: const Icon(Icons.wifi_tethering, size: 88, color: C.violet),
        );
      case FlowPhase.downloading:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          MobileRing(
            key: const Key('ring'),
            color: C.blue,
            value: fraction,
            child: Text(
              '${(fraction * 100).floor()}%',
              key: const Key('percent'),
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                color: pal.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 24, // keeps the layout still before the first speed reading
            child: speedMBps == null
                ? null
                : Text('${speedMBps!.toStringAsFixed(1)} MB/s',
                    key: const Key('speed'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: pal.muted)),
          ),
        ]);
      case FlowPhase.done:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          MobileRing(
            key: const Key('ring'),
            color: C.green,
            value: 1,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: .4, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: const Icon(Icons.check_rounded, size: 112, color: C.green),
            ),
          ),
          const SizedBox(height: 32),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            FileChips(names: names, count: fileCount, color: C.green),
            Container(
              key: const Key('size'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: C.green.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(formatSize(totalBytes),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.green)),
            ),
          ]),
        ]);
      case FlowPhase.failed:
        return MobileRing(
          key: const Key('ring'),
          color: C.red,
          value: 0,
          child: Icon(_problemIcon, size: 96, color: C.red),
        );
      case FlowPhase.offline:
        return MobileRing(
          key: const Key('ring'),
          color: C.slate,
          value: 0,
          child: const Icon(Icons.wifi_off_rounded, size: 96, color: C.slate),
        );
      case FlowPhase.invalid:
        return MobileRing(
          key: const Key('ring'),
          color: C.amber,
          value: 0,
          child: const Icon(Icons.qr_code_2_rounded, size: 96, color: C.amber),
        );
    }
  }

  IconData get _problemIcon => switch (problem) {
        FlowProblem.join => Icons.wifi_password_rounded,
        FlowProblem.unreachable => Icons.portable_wifi_off_rounded,
        FlowProblem.save => Icons.folder_off_rounded,
        _ => Icons.close_rounded,
      };

  /// The main action lives in the bottom third where a thumb rests.
  Widget _actions() {
    switch (phase) {
      case FlowPhase.done:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _Primary(key: const Key('open'), icon: Icons.folder_open_rounded, label: 'Open', color: C.green, onTap: onOpen),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('done'),
            onPressed: onDone,
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ),
        ]);
      case FlowPhase.failed:
        return _Primary(key: const Key('scan'), icon: Icons.qr_code_scanner_rounded, label: 'Scan', color: C.red, onTap: onScan);
      case FlowPhase.offline:
        return _Primary(key: const Key('scan'), icon: Icons.qr_code_scanner_rounded, label: 'Scan', color: C.slate, onTap: onScan);
      case FlowPhase.invalid:
        return _Primary(key: const Key('scan'), icon: Icons.qr_code_scanner_rounded, label: 'Scan', color: C.amber, onTap: onScan);
      default:
        return const SizedBox(height: 64);
    }
  }
}

class _Primary extends StatelessWidget {
  const _Primary({super.key, required this.icon, required this.label, required this.color, this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 64,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.black,
            elevation: 0,
            shadowColor: color.withValues(alpha: .5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 24),
          label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      );
}

/// Phone home: one hero to aim, one big scan button under the thumb.
class MobileHomeView extends StatelessWidget {
  const MobileHomeView({super.key, this.onScan});
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return GlowBackground(
      color: C.blue,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(children: [
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Pulse(
                    color: C.blue,
                    size: 340,
                    child: Container(
                      key: const Key('hero'),
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [C.blue, C.violet],
                        ),
                        boxShadow: [BoxShadow(color: C.blue.withValues(alpha: .45), blurRadius: 48)],
                      ),
                      child: const Icon(Icons.qr_code_scanner_rounded, size: 80, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: FilledButton.icon(
                key: const Key('scan'),
                style: FilledButton.styleFrom(
                  backgroundColor: C.blue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: pal.shadow,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: onScan,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
                label: const Text('Scan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
