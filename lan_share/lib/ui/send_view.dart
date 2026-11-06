import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'file_chips.dart';
import 'pulse.dart';
import 'theme.dart';
import 'transfer_ring.dart';

/// Where the phone-hotspot flow is: off, starting, waiting for the phone to join, or joined.
enum HotspotUi { off, starting, joining, ready }

/// The QR itself; keeps its payload public so tests can check what a phone would read.
class QrBox extends StatelessWidget {
  const QrBox(this.data, {super.key});
  final String data;
  @override
  Widget build(BuildContext context) => QrImageView(data: data, size: 250);
}

/// Pure presentation for the sender: QR while waiting, ring afterwards.
class SendView extends StatelessWidget {
  const SendView({
    super.key,
    required this.phase,
    required this.link,
    required this.fileCount,
    this.fileNames = const [],
    this.fraction = 0,
    this.speedMBps,
    this.remaining = 1,
    this.pairCode,
    this.accessCode,
    this.manualAddress,
    this.showManual = false,
    this.hotspot = HotspotUi.off,
    this.wifiQr,
    this.hotspotName,
    this.hotspotPass,
    this.onToggleHotspot,
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

  /// Live transfer speed, shown under the ring while sending.
  final double? speedMBps;

  /// Life left on the QR code, 1 -> 0.
  final double remaining;
  final String? pairCode;

  /// 6-digit code for phones that cannot scan; shown with the address.
  final String? accessCode;

  /// Short address to type on a phone; falls back to the link's host:port.
  final String? manualAddress;
  final bool showManual;

  /// Hotspot flow: the join-Wi-Fi QR payload and the credentials to type.
  final HotspotUi hotspot;
  final String? wifiQr, hotspotName, hotspotPass;
  final VoidCallback? onToggleHotspot;
  final VoidCallback? onToggleManual, onApprove, onDeny, onRefresh, onRetry, onClose;

  bool get _hotspotOn => hotspot == HotspotUi.starting || hotspot == HotspotUi.joining || hotspot == HotspotUi.ready;
  bool get _joining => phase == Phase.waiting && (hotspot == HotspotUi.starting || hotspot == HotspotUi.joining);

  @override
  Widget build(BuildContext context) {
    final color = _joining ? C.violet : phaseColor(phase);
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
            Expanded(child: Center(child: _hero(context, color))),
            _links(),
            FileChips(names: fileNames, count: fileCount, color: color),
            const SizedBox(height: 16),
            _action(),
          ]),
        ),
      ),
    );
  }

  /// Text links under the QR: typed code, and the hotspot switch.
  Widget _links() {
    final waiting = phase == Phase.waiting && pairCode == null;
    final manual = waiting && link != null && accessCode != null;
    final spot = waiting && onToggleHotspot != null;
    if (!manual && !spot) return const SizedBox.shrink();
    const style = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
        if (manual)
          TextButton.icon(
            key: const Key('manual'),
            onPressed: onToggleManual,
            icon: Icon(showManual ? Icons.qr_code_2 : Icons.dialpad, size: 20),
            label: Text(showManual ? 'Scan QR' : 'No scanner?', style: style),
          ),
        if (spot)
          TextButton.icon(
            key: const Key('hotspot'),
            onPressed: hotspot == HotspotUi.starting ? null : onToggleHotspot,
            icon: Icon(_hotspotOn ? Icons.wifi_tethering_off : Icons.wifi_tethering, size: 20),
            label: Text(_hotspotOn ? 'Stop' : 'Hotspot', style: style),
          ),
      ]),
    );
  }

  Widget _hero(BuildContext context, Color color) {
    if (pairCode != null) return _pairing(context);
    if (phase == Phase.waiting) {
      if (hotspot == HotspotUi.starting) return _starting(color);
      if (hotspot == HotspotUi.joining) {
        return showManual ? _wifiTiles(context) : _joinQr(context, color);
      }
      if (showManual && link != null && accessCode != null) return _manual(context);
      if (link != null) return _linkQr(color);
    }
    final ring = TransferRing(phase: phase, fraction: fraction, size: 230);
    if (phase != Phase.active || speedMBps == null) return ring;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ring,
      const SizedBox(height: 20),
      Text('${speedMBps!.toStringAsFixed(1)} MB/s',
          key: const Key('speed'),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Pal.of(context).muted)),
    ]);
  }

  /// Spinner while Windows brings the hotspot up.
  Widget _starting(Color color) => SizedBox(
        width: 200,
        height: 200,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(child: CircularProgressIndicator(strokeWidth: 12, strokeCap: StrokeCap.round, color: color)),
          Icon(Icons.wifi_tethering, size: 78, color: color),
        ]),
      );

  Widget _qrCard(String data, Color color, {Key? key, Widget? badge}) => Stack(clipBehavior: Clip.none, children: [
        Container(
          key: key,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: color.withValues(alpha: .5), blurRadius: 44)],
          ),
          child: QrBox(data),
        ),
        if (badge != null) Positioned(right: -10, top: -10, child: badge),
      ]);

  /// Phone scans this to join the laptop's hotspot.
  Widget _joinQr(BuildContext context, Color color) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Pulse(
          color: color,
          size: 400,
          child: _qrCard(
            wifiQr ?? '',
            color,
            key: const Key('wifiQr'),
            badge: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: C.violet,
                shape: BoxShape.circle,
                border: Border.all(color: Pal.of(context).bg, width: 4),
              ),
              child: const Icon(Icons.wifi_rounded, color: Colors.white, size: 30),
            ),
          ),
        ),
      );

  Widget _linkQr(Color color) {
    final arcColor = remaining < .2 ? C.amber : C.blue;
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
              child: QrBox(link.toString()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, Color color, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Pal.of(context).card,
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

  /// Typed fallback for joining the hotspot: network name and password.
  Widget _wifiTiles(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        _tile(context, Icons.wifi_rounded, C.violet,
            Text(hotspotName ?? '', key: const Key('hotspotName'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
        const SizedBox(height: 20),
        _tile(context, Icons.key_rounded, C.amber,
            Text(hotspotPass ?? '', key: const Key('hotspotPass'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 2))),
      ]);

  Widget _manual(BuildContext context) {
    final c = accessCode!;
    final grouped = '${c.substring(0, 3)} ${c.substring(3)}';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _tile(context, Icons.language, C.blue,
          Text(manualAddress ?? link!.authority, key: const Key('manualAddress'),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
      const SizedBox(height: 20),
      _tile(context, Icons.pin_outlined, C.green,
          Text(grouped, key: const Key('manualCode'),
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, letterSpacing: 6))),
    ]);
  }

  Widget _pairing(BuildContext context) {
    final pal = Pal.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        decoration: BoxDecoration(
          color: pal.card,
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
  }

  Widget _action() {
    switch (phase) {
      case Phase.done:
        return _Big(key: const Key('act'), icon: Icons.check, label: 'Done', color: C.green, onTap: onClose);
      case Phase.offline:
        return _Big(key: const Key('act'), icon: Icons.refresh, label: 'Retry', color: C.slate, onTap: onRetry);
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
