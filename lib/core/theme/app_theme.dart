import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Primary — Spotify green
  static const Color primary = Color(0xFF1DB954);
  static const Color primaryLight = Color(0xFF1ED760);

  // Backgrounds
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF181818);
  static const Color surfaceVariant = Color(0xFF282828);
  static const Color surfaceContainerLow = Color(0xFF1A1A1A);
  static const Color surfaceContainerHigh = Color(0xFF2A2A2A);
  static const Color surfaceContainerHighest = Color(0xFF333333);

  // Text
  static const Color onSurface = Color(0xFFFFFFFF);
  static const Color onSurfaceVariant = Color(0xFFB3B3B3);
  static const Color onBackground = Color(0xFFFFFFFF);

  // Accent
  static const Color error = Color(0xFFCF6679);
  static const Color emerald = Color(0xFF1DB954);
  static const Color emeraldDark = Color(0xFF1A6B3A);
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: AppColors.background,
        secondary: AppColors.primaryLight,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        surfaceContainerHigh: AppColors.surfaceContainerHigh,
        error: AppColors.error,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(
          color: AppColors.onSurface,
          fontSize: 32,
          fontWeight: FontWeight.w900,
        ),
        headlineLarge: GoogleFonts.inter(
          color: AppColors.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w900,
        ),
        headlineMedium: GoogleFonts.inter(
          color: AppColors.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: GoogleFonts.inter(
          color: AppColors.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: GoogleFonts.inter(
          color: AppColors.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: GoogleFonts.inter(
          color: AppColors.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: GoogleFonts.inter(
          color: AppColors.onSurfaceVariant,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: GoogleFonts.inter(
          color: AppColors.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        labelSmall: GoogleFonts.inter(
          color: AppColors.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceVariant,
        selectedItemColor: AppColors.onSurface,
        unselectedItemColor: AppColors.onSurfaceVariant,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.onSurface,
        inactiveTrackColor: Colors.white.withOpacity(0.2),
        thumbColor: AppColors.onSurface,
        overlayColor: AppColors.onSurface.withOpacity(0.1),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
      ),
    );
  }
}
