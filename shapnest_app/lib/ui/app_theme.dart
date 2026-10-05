import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF020617), // Deep slate black
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00E5FF),          // Cyan
        onPrimary: Colors.black,
        secondary: Color(0xFFA855F7),        // Purple
        onSecondary: Colors.white,
        surface: Color(0xFF0F172A),          // Slate 900
        surfaceContainer: Color(0xFF1E293B), // Slate 800
        onSurface: Colors.white,
        onSurfaceVariant: Color(0xFF94A3B8), // Slate 400
        outline: Color(0xFF334155),          // Slate 700
        error: Color(0xFFFF5252),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardColor: const Color(0xFF1E293B),
      dividerColor: const Color(0xFF334155),
      fontFamily: 'Roboto',
      useMaterial3: true,
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Slate 50 (Soft off-white)
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF0284C7),          // Sky 600
        onPrimary: Colors.white,
        secondary: Color(0xFF7E22CE),        // Purple 700
        onSecondary: Colors.white,
        surface: Colors.white,               // Pure White
        surfaceContainer: Color(0xFFF1F5F9), // Slate 100
        onSurface: Color(0xFF0F172A),        // Slate 900 (High contrast dark text)
        onSurfaceVariant: Color(0xFF475569), // Slate 600
        outline: Color(0xFFCBD5E1),          // Slate 300
        error: Color(0xFFDC2626),            // Red 600
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF0F172A),
        elevation: 1,
        shadowColor: Colors.black12,
        surfaceTintColor: Colors.transparent,
      ),
      cardColor: Colors.white,
      dividerColor: const Color(0xFFE2E8F0),
      fontFamily: 'Roboto',
      useMaterial3: true,
    );
  }
}
