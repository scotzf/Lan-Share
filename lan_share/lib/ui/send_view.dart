import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'file_chips.dart';
import 'pulse.dart';
import 'theme.dart';
import 'transfer_ring.dart';

/// Pure presentation for the sender: QR while waiting, ring afterwards.
class SendView extends StatelessWidget {
  const SendView({
    super.key,
    required this.phase,
    required this.link,
    required this.fileCount,
    this.fileNames = const [],
    this.fraction = 0,
    this.remaining = 1,
    this.pairCode,
    this.onApprove,
    this.onDeny,
    this.onRefresh,
    this.onRetry,
    this.onClose,
  });

  final Phase phase;
  final Uri? link;
  final int fileCount;
  final List<String> fileNames;
  final double fraction;

  /// Life left on the QR code, 1 -> 0.
  final double remaining;
  final String? pairCode;
  final VoidCallback? onApprove, onDeny, onRefresh, onRetry, onClose;

  @override
  Widget build(BuildContext context) {
    final color = phaseColor(phase);
    return GlowBackground(
      color: color,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton.filledTonal(
                key: const Key('close'),
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(child: Center(child: _hero(color))),
            FileChips(names: fileNames, count: fileCount, color: color),
            const SizedBox(height: 16),
            _action(),
          ]),
        ),
      ),
    );
  }

  Widget _hero(Color color) {
    if (pairCode != null) return _pairing();
    if (phase == Phase.waiting && link != null) {
      final urgent = remaining < .2;
      final arcColor = urgent ? C.amber : C.blue;
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: TweenAnimationBuilder<double>(
          key: ValueKey(link),
          tween: Tween(begin: .88, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
          builder: (_, s, child) => Opacity(
            opacity: ((s - .88) / .12).clamp(0.0, 1.0),
            child: Transform.scale(scale: s, child: child),
          ),
          child: Pulse(
            color: color,
            size: 400,
            child: ExpiryArc(
              key: const Key('qr'),
              remaining: remaining,
              color: arcColor,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: .5), blurRadius: 44)],
                ),
                child: QrImageView(data: link.toString(), size: 250),
              ),
            ),
          ),
        ),
      );
    }
    return TransferRing(phase: phase, fraction: fraction, size: 230);
  }

  Widget _pairing() => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          decoration: BoxDecoration(
            color: C.card,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [BoxShadow(color: C.violet.withValues(alpha: .4), blurRadius: 40)],
          ),
          child: Text(pairCode!,
              key: const Key('pairCode'),
              style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800, letterSpacing: 10)),
        ),
        const SizedBox(height: 32),
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton.filled(
              key: const Key('deny'),
              style: IconButton.styleFrom(backgroundColor: C.red, minimumSize: const Size(76, 76)),
              onPressed: onDeny,
              icon: const Icon(Icons.close, size: 38)),
          const SizedBox(width: 36),
          IconButton.filled(
              key: const Key('approve'),
              style: IconButton.styleFrom(backgroundColor: C.green, minimumSize: const Size(76, 76)),
              onPressed: onApprove,
              icon: const Icon(Icons.check, size: 38)),
        ]),
      ]);

  Widget _action() {
    switch (phase) {
      case Phase.done:
        return _Big(key: const Key('act'), icon: Icons.check, label: 'Done', color: C.green, onTap: onClose);
      case Phase.failed:
        return _Big(key: const Key('act'), icon: Icons.refresh, label: 'Retry', color: C.red, onTap: onRetry);
      case Phase.expired:
        return _Big(key: const Key('act'), icon: Icons.qr_code_2, label: 'Refresh', color: C.amber, onTap: onRefresh);
      default:
        return const SizedBox(height: 56);
    }
  }
}

class _Big extends StatelessWidget {
  const _Big({super.key, required this.icon, required this.label, required this.color, this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 58,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
      );
}
