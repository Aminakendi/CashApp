import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryPink = Color(0xFFEC4899);
  static const Color primaryPurple = Color(0xFF8B5CF6);
  static const Color semanticGreen = Color(0xFF10B981);
  static const Color semanticRed = Color(0xFFEF4444);
  static const Color semanticAmber = Color(0xFFF59E0B);
  
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryPink, primaryPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF111827),
      primaryColor: primaryPurple,
      colorScheme: const ColorScheme.dark(
        primary: primaryPink,
        secondary: primaryPurple,
        surface: Color(0xFF1F2937),
        error: semanticRed,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryPink,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF374151),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
