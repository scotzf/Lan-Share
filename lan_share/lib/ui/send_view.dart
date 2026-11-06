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
    this.accessCode,
    this.showManual = false,
    this.onToggleManual,
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

  /// 6-digit code for phones that cannot scan; shown with the address.
  final String? accessCode;
  final bool showManual;
  final VoidCallback? onToggleManual, onApprove, onDeny, onRefresh, onRetry, onClose;

  @override
  Widget build(BuildContext context) {
    final color = phaseColor(phase);
    return GlowBackground(
      color: color,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              IconButton.filledTonal(
                key: const Key('close'),
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
              const Spacer(),
            ]),
            Expanded(child: Center(child: _hero(color))),
            _switchLink(),
            FileChips(names: fileNames, count: fileCount, color: color),
            const SizedBox(height: 16),
            _action(),
          ]),
        ),
      ),
    );
  }

  /// Text link under the QR: swaps between the QR and the typed code.
  Widget _switchLink() {
    final available = phase == Phase.waiting && link != null && pairCode == null && accessCode != null;
    if (!available) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextButton.icon(
        key: const Key('manual'),
        onPressed: onToggleManual,
        icon: Icon(showManual ? Icons.qr_code_2 : Icons.dialpad, size: 20),
        label: Text(showManual ? 'Scan QR' : 'No scanner?',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _hero(Color color) {
    if (pairCode != null) return _pairing();
    if (showManual && phase == Phase.waiting && link != null && accessCode != null) {
      return _manual();
    }
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

  Widget _manual() {
    final c = accessCode!;
    final grouped = '${c.substring(0, 3)} ${c.substring(3)}';
    Widget tile(IconData icon, Color color, Widget child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: C.card,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: color.withValues(alpha: .3), blurRadius: 30)],
          ),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: color.withValues(alpha: .25), shape: BoxShape.circle),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: child)),
          ]),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      tile(Icons.language, C.blue,
          Text(link!.authority, key: const Key('manualAddress'),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
      const SizedBox(height: 20),
      tile(Icons.pin_outlined, C.green,
          Text(grouped, key: const Key('manualCode'),
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, letterSpacing: 6))),
    ]);
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
