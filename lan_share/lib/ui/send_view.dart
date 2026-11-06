import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'theme.dart';
import 'transfer_ring.dart';

/// Pure presentation for the sender: QR while waiting, ring afterwards.
class SendView extends StatelessWidget {
  const SendView({
    super.key,
    required this.phase,
    required this.link,
    required this.fileCount,
    this.fraction = 0,
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
  final double fraction;
  final String? pairCode;
  final VoidCallback? onApprove, onDeny, onRefresh, onRetry, onClose;

  @override
  Widget build(BuildContext context) {
    final color = phaseColor(phase);
    return SafeArea(
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
          _Chips(count: fileCount, color: color),
          const SizedBox(height: 16),
          _action(),
        ]),
      ),
    );
  }

  Widget _hero(Color color) {
    if (pairCode != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Text(pairCode!,
            key: const Key('pairCode'),
            style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800, letterSpacing: 8)),
        const SizedBox(height: 24),
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton.filled(
              key: const Key('deny'),
              style: IconButton.styleFrom(backgroundColor: C.red, minimumSize: const Size(72, 72)),
              onPressed: onDeny,
              icon: const Icon(Icons.close, size: 36)),
          const SizedBox(width: 32),
          IconButton.filled(
              key: const Key('approve'),
              style: IconButton.styleFrom(backgroundColor: C.green, minimumSize: const Size(72, 72)),
              onPressed: onApprove,
              icon: const Icon(Icons.check, size: 36)),
        ]),
      ]);
    }
    if (phase == Phase.waiting && link != null) {
      return Container(
        key: const Key('qr'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [BoxShadow(color: C.blue.withValues(alpha: .45), blurRadius: 40)],
        ),
        child: QrImageView(data: link.toString(), size: 260),
      );
    }
    return TransferRing(phase: phase, fraction: fraction, size: 220);
  }

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

class _Chips extends StatelessWidget {
  const _Chips({required this.count, required this.color});
  final int count;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: .18), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.insert_drive_file_rounded, color: color),
          const SizedBox(width: 8),
          Text('$count', style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
      );
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
        height: 56,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.black),
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      );
}
