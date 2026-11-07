import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pulse.dart';
import 'responsive.dart';
import 'theme.dart';

/// Laptop home: one clear drop card, two quiet actions underneath, a small status strip.
/// A single fluid column (capped at [kColumnMax]) so it looks right from a quarter-snapped
/// window to a maximized one. Three ways in, as in Quick Share: drop, choose, or right-click in Explorer.
class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.dragging,
    this.onPick,
    this.onReceive,
    this.onPhoneApp,
    this.showPhoneApp = false,
    this.assistOn = true,
    this.onToggleAssist,
    this.fastOn = false,
    this.onToggleFast,
    this.address,
  });

  final bool dragging;
  final VoidCallback? onPick, onReceive, onPhoneApp, onToggleAssist, onToggleFast;

  /// Offer the Android app (its file is installed beside this program).
  final bool showPhoneApp;

  /// Hotspot assist on or off, and this laptop's address on the network (null = offline).
  final bool assistOn;

  /// Fast mode: share over plain http (quicker, no certificate warning, not encrypted).
  final bool fastOn;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final accent = dragging ? C.green : C.blue;
    return GlowBackground(
      color: accent,
      child: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final pad = gutterFor(box.maxWidth);
          final cardHeight = (box.maxHeight * .40).clamp(240.0, 340.0);
          return SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: math.max(0, box.maxHeight - pad * 2)),
              child: CenteredColumn(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const _Header(),
                  const SizedBox(height: 24),
                  _DropCard(dragging: dragging, height: cardHeight, onPick: onPick),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: _ActionTile(
                        key: const Key('receive'),
                        icon: Icons.south_rounded,
                        label: 'Receive',
                        color: C.green,
                        onTap: onReceive,
                      ),
                    ),
                    if (showPhoneApp) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: _ActionTile(
                          key: const Key('phoneApp'),
                          icon: Icons.phone_android_rounded,
                          label: 'Phone app',
                          color: C.violet,
                          onTap: onPhoneApp,
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 24),
                  _StatusStrip(assistOn: assistOn, onToggleAssist: onToggleAssist, fastOn: fastOn, onToggleFast: onToggleFast, address: address),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset('assets/logo.png', width: 40, height: 40, filterQuality: FilterQuality.medium),
        ),
        const SizedBox(width: 12),
        Text('LAN Share',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Pal.of(context).text)),
      ]);
}

/// The big target: dashed edge, a fan of file tiles, a label and a real Choose button.
class _DropCard extends StatelessWidget {
  const _DropCard({required this.dragging, required this.height, this.onPick});
  final bool dragging;
  final double height;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final accent = dragging ? C.green : C.blue;
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('drop'),
          borderRadius: BorderRadius.circular(28),
          hoverColor: accent.withValues(alpha: .06),
          onTap: onPick,
          child: CustomPaint(
            painter: _DashedBorder(accent.withValues(alpha: dragging ? .95 : .55), 28, solid: dragging),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: dragging ? accent.withValues(alpha: .14) : pal.card.withValues(alpha: .72),
                boxShadow: [BoxShadow(color: pal.shadow, blurRadius: 32, offset: const Offset(0, 12))],
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedScale(
                      scale: dragging ? 1.1 : 1,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      child: _FileFan(dragging: dragging),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(dragging ? 'Drop' : 'Drop or choose',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: pal.text)),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('choose'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(140, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: onPick,
                  child: const Text('Choose', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three file tiles fanned like a hand of cards, with a round badge, floating gently.
class _FileFan extends StatefulWidget {
  const _FileFan({required this.dragging});
  final bool dragging;
  @override
  State<_FileFan> createState() => _FileFanState();
}

class _FileFanState extends State<_FileFan> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _tile(IconData icon, Color color, double angle, double dx) => Transform.translate(
        offset: Offset(dx, 0),
        child: Transform.rotate(
          angle: angle,
          child: Container(
            width: 72,
            height: 92,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: color.withValues(alpha: .4), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final badge = widget.dragging ? C.green : C.blue;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, reduce ? 0 : -6 * Curves.easeInOut.transform(_c.value)),
        child: SizedBox(
          width: 220,
          height: 120,
          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            _tile(Icons.image_rounded, C.violet, -.22, -64),
            _tile(Icons.movie_rounded, C.red, .22, 64),
            _tile(Icons.picture_as_pdf_rounded, const Color(0xFFF97316), 0, 0),
            Positioned(
              bottom: -10,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: badge,
                  border: Border.all(color: Pal.of(context).bg, width: 4),
                ),
                child: Icon(widget.dragging ? Icons.add_rounded : Icons.north_rounded, color: Colors.white, size: 22),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A quiet secondary action: icon tile and a one-word label.
class _ActionTile extends StatefulWidget {
  const _ActionTile({super.key, required this.icon, required this.label, required this.color, this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.02 : 1,
        duration: const Duration(milliseconds: 140),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            height: 96,
            decoration: BoxDecoration(
              color: pal.card,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: widget.color.withValues(alpha: _hover ? .26 : .14), blurRadius: 24, offset: const Offset(0, 8)),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: widget.onTap,
              child: LayoutBuilder(builder: (context, box) {
                // in a narrow tile the icon goes above the label so the word is never cut off
                final compact = box.maxWidth < 210;
                final icon = Container(
                  width: compact ? 40 : 48,
                  height: compact ? 40 : 48,
                  decoration: BoxDecoration(color: widget.color.withValues(alpha: .18), shape: BoxShape.circle),
                  child: Icon(widget.icon, color: widget.color, size: compact ? 22 : 26),
                );
                final label = Text(widget.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: pal.text));
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 20),
                  child: compact
                      ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [icon, const SizedBox(height: 8), label])
                      : Row(children: [icon, const SizedBox(width: 16), label]),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small facts as chips: is the hotspot helper on (tap to change), and which network we are on.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.assistOn, this.onToggleAssist, this.fastOn = false, this.onToggleFast, this.address});
  final bool assistOn;
  final VoidCallback? onToggleAssist, onToggleFast;
  final bool fastOn;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final online = address != null;
    return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
      if (onToggleAssist != null)
        _Chip(
          key: const Key('assist'),
          tip: 'Hotspot assist',
          icon: assistOn ? Icons.wifi_tethering : Icons.wifi_tethering_off,
          label: 'Hotspot',
          color: assistOn ? C.violet : C.slate,
          filled: assistOn,
          onTap: onToggleAssist,
        ),
      if (onToggleFast != null)
        _Chip(
          key: const Key('fast'),
          tip: fastOn ? 'Fast mode: not encrypted' : 'Fast mode off: encrypted',
          icon: Icons.bolt_rounded,
          label: 'Fast',
          color: fastOn ? C.amber : C.slate,
          filled: fastOn,
          onTap: onToggleFast,
        ),
      _Chip(
        key: const Key('address'),
        tip: 'This laptop on your network',
        icon: online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
        label: online ? address! : 'Offline',
        color: online ? C.blue : C.slate,
        filled: online,
      ),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.tip, required this.icon, required this.label, required this.color, required this.filled, this.onTap});
  final String tip, label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: Material(
          color: color.withValues(alpha: filled ? .16 : .10),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
              ]),
            ),
          ),
        ),
      );
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color, this.radius, {this.solid = false});
  final Color color;
  final double radius;
  final bool solid;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(1.5), Radius.circular(radius)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (solid) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 22) {
        canvas.drawPath(m.extractPath(d, d + 12), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.solid != solid;
}
