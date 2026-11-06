import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ui/theme.dart';

/// Full-screen camera with a rounded scan frame. Pops with the text of the first QR it reads.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _found = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_found) return;
    final text = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (text == null || text.isEmpty) return;
    setState(() => _found = true);
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 280)); // let the frame turn green
    if (mounted) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final frame = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * .42),
      width: (size.width * .72).clamp(220.0, 300.0),
      height: (size.width * .72).clamp(220.0, 300.0),
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => const Center(
            child: Icon(Icons.no_photography_rounded, size: 96, color: C.slate),
          ),
        ),
        CustomPaint(painter: _FramePainter(frame, _found ? C.green : Colors.white)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              IconButton.filledTonal(
                key: const Key('close'),
                onPressed: () => Navigator.of(context).pop(),
                iconSize: 24,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.close),
              ),
              const Spacer(),
              IconButton.filledTonal(
                key: const Key('torch'),
                onPressed: () async {
                  await _controller.toggleTorch();
                  if (mounted) setState(() => _torch = !_torch);
                },
                iconSize: 24,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(_torch ? Icons.flashlight_off_rounded : Icons.flashlight_on_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Dims everything except the scan frame and draws its four corners.
class _FramePainter extends CustomPainter {
  _FramePainter(this.frame, this.color);
  final Rect frame;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(frame, const Radius.circular(32));
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: .6));

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = color.withValues(alpha: .35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawRRect(rrect, glow);

    const arm = 40.0;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = color;
    final r = frame;
    const k = 32.0; // matches the frame's corner radius
    // four rounded corner brackets
    for (final (x, y, sx, sy) in [
      (r.left, r.top, 1.0, 1.0),
      (r.right, r.top, -1.0, 1.0),
      (r.left, r.bottom, 1.0, -1.0),
      (r.right, r.bottom, -1.0, -1.0),
    ]) {
      final path = Path()
        ..moveTo(x, y + sy * arm)
        ..lineTo(x, y + sy * k)
        ..quadraticBezierTo(x, y, x + sx * k, y)
        ..lineTo(x + sx * arm, y);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.frame != frame || old.color != color;
}
