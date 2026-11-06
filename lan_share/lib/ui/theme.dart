import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF0B1220);
  static const card = Color(0xFF151E33);
  static const blue = Color(0xFF3B82F6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const violet = Color(0xFF8B5CF6);
}

ThemeData appTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: C.bg,
      colorScheme: const ColorScheme.dark(primary: C.blue, surface: C.card),
      useMaterial3: true,
    );
