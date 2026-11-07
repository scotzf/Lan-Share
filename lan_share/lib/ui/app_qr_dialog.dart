import 'package:flutter/material.dart';

import 'send_view.dart' show QrBox;
import 'theme.dart';

/// QR that sends a phone to the Android app file on this laptop. Closing it stops the sharing.
class AppQrDialog extends StatelessWidget {
  const AppQrDialog({super.key, required this.url});
  final Uri url;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: pal.card,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: C.violet.withValues(alpha: .35), blurRadius: 48)],
          ),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: C.violet.withValues(alpha: .18), shape: BoxShape.circle),
                  child: const Icon(Icons.phone_android_rounded, color: C.violet, size: 26),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  key: const Key('close'),
                  onPressed: () => Navigator.of(context).pop(),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.close),
                ),
              ]),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                  child: QrBox(url.toString()),
                ),
              ),
              const SizedBox(height: 16),
              Text('${url.host}:${url.port}',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: pal.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
