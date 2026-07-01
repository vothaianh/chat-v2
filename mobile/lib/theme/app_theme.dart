import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Professional dark messaging palette — deep slate/indigo, high-contrast,
/// content-first. All screens read these tokens so the theme stays cohesive.
class AppTheme {
  // Brand
  static const Color primary = Color(0xFF6366F1); // indigo-500 (brighter for dark)
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color accent = Color(0xFF22D3EE); // cyan-400

  // Surfaces (layered, dark → lighter)
  static const Color background = Color(0xFF0B0E14); // app scaffold
  static const Color surface = Color(0xFF141822); // app bars, cards
  static const Color surfaceElevated = Color(0xFF1C212E); // inputs, sheets
  static const Color surfaceHigh = Color(0xFF262C3B); // pressed / their bubble

  // Bubbles
  static const Color bubbleMine = Color(0xFF6366F1);
  static const Color bubbleTheirs = Color(0xFF222736);

  // Text
  static const Color textPrimary = Color(0xFFECEEF3);
  static const Color textSecondary = Color(0xFF9AA3B2);
  static const Color textFaint = Color(0xFF6B7280);

  // Accents / status
  static const Color online = Color(0xFF34D399);
  static const Color offline = Color(0xFF64748B);
  static const Color divider = Color(0xFF232838);
  static const Color mention = Color(0xFF7DD3FC);
  static const Color danger = Color(0xFFF87171);

  /// System UI (status bar) styling for the dark theme.
  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: background,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: Colors.white,
        secondary: accent,
        surface: surface,
        onSurface: textPrimary,
        error: danger,
      ),
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlay,
        titleTextStyle: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        hintStyle: const TextStyle(color: textFaint),
        labelStyle: const TextStyle(color: textSecondary),
        floatingLabelStyle: const TextStyle(color: primary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: divider, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primary.withValues(alpha: 0.4),
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1),
      dividerColor: divider,
      iconTheme: const IconThemeData(color: textSecondary),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
      ),
    );
  }
}
