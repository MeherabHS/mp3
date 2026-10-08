import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF08080A);
  static const Color surface = Color(0xFF111116);
  static const Color surfaceElevated = Color(0xFF171722);
  static const Color border = Color(0xFF222232);

  // Accents from Master Design
  static const Color accentPurple = Color(0xFFA855F7);
  static const Color neonPurple = Color(0xFFC084FC);
  static const Color accentGold = Color(0xFFE5A93C);
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color connectedGreen = Color(0xFF00E676);

  static const Color textPrimary = Color(0xFFF5F5FA);
  static const Color textSecondary = Color(0xFF9494A8);
  static const Color textTertiary = Color(0xFF5C5C70);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accentPurple,
      canvasColor: background,
      cardColor: surface,
      dividerColor: border,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accentPurple,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineMedium: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 14,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 13,
        ),
        bodySmall: TextStyle(
          color: textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
