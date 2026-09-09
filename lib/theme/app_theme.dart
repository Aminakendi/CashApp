import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Color Tokens
  static const Color background = Color(0xFF0B0B14);
  static const Color surface = Color(0xFF16161F);
  static const Color surfaceElevated = Color(0xFF1C1C28);
  static const Color surfaceBorder = Color(0x80262633); // #26263380

  static const Color primaryPink = Color(0xFFEC4899);
  static const Color primaryPurple = Color(0xFF8B5CF6);
  
  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFF9797A6);
  static const Color textDisabled = Color(0xFF5C5C6B);

  // Semantic Colors
  static const Color semanticGreen = Color(0xFF10B981); // Income / Positive
  static const Color semanticRed = Color(0xFFEF4444);   // Expense / Negative
  static const Color semanticAmber = Color(0xFFF59E0B); // Warning / Near-limit

  // Chart Palette
  static const List<Color> chartPalette = [
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
    Color(0xFF06B6D4),
    Color(0xFF14B8A6),
    Color(0xFFF59E0B),
    Color(0xFFF97316),
    Color(0xFFEAB308),
    Color(0xFFA855F7),
    Color(0xFF6366F1),
  ];
  
  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryPink, primaryPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    transform: GradientRotation(2.35619), // ~135 degrees in radians
  );

  // Shape Tokens
  static const double cardRadius = 16.0;
  static const double buttonRadius = 12.0;

  // Typography
  static TextTheme get textTheme {
    return TextTheme(
      displayLarge: GoogleFonts.sora(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineMedium: GoogleFonts.sora(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.normal,
        color: textPrimary,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.normal,
        color: textSecondary,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.normal,
        color: textSecondary,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primaryPurple,
      textTheme: textTheme,
      colorScheme: const ColorScheme.dark(
        primary: primaryPink,
        secondary: primaryPurple,
        surface: surface,
        error: semanticRed,
        onSurface: textPrimary,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: surfaceBorder, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryPink, // Ideally wrap FAB in a Container with primaryGradient, but as fallback use pink
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        hintStyle: GoogleFonts.inter(color: textDisabled),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: surfaceBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: surfaceBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: primaryPurple, width: 1),
        ),
      ),
    );
  }
}
