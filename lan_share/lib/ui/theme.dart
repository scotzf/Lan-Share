import 'package:flutter/material.dart';

/// Accent colours: same in both themes, each one carries a meaning.
class C {
  static const blue = Color(0xFF3B82F6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const violet = Color(0xFF8B5CF6);
  static const teal = Color(0xFF14B8A6);
  static const slate = Color(0xFF94A3B8);
}

/// Surface colours that change with light and dark.
class Pal {
  const Pal({
    required this.bg,
    required this.card,
    required this.text,
    required this.muted,
    required this.glow,
    required this.shadow,
  });

  final Color bg, card, text, muted;

  /// Strength of the coloured wash at the top of a screen.
  final double glow;
  final Color shadow;

  static const dark = Pal(
    bg: Color(0xFF0B1220),
    card: Color(0xFF151E33),
    text: Color(0xFFF8FAFC),
    muted: Color(0xFF94A3B8),
    glow: .22,
    shadow: Color(0x47000000),
  );
  static const light = Pal(
    bg: Color(0xFFF3F6FC),
    card: Colors.white,
    text: Color(0xFF0F172A),
    muted: Color(0xFF64748B),
    glow: .10,
    shadow: Color(0x1A1E3A8A),
  );

  static Pal of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

ThemeData _theme(Brightness b, Pal p) => ThemeData(
      brightness: b,
      scaffoldBackgroundColor: p.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: C.blue, brightness: b)
          .copyWith(primary: C.blue, surface: p.card),
      useMaterial3: true,
    );

ThemeData appTheme() => _theme(Brightness.dark, Pal.dark);
ThemeData lightTheme() => _theme(Brightness.light, Pal.light);
