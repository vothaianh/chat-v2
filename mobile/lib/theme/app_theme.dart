import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pulse — ink-black canvas, electric lime, hot orchid.
/// Built for a Gen Z messenger: high contrast, editorial type, no generic indigo.
class AppTheme {
  static const Color primary = Color(0xFFC6FF4A);
  static const Color primaryDark = Color(0xFF9BE01A);
  static const Color primaryInk = Color(0xFF0B1400);
  static const Color accent = Color(0xFFFF4D9A);
  static const Color violet = Color(0xFFA78BFA);
  static const Color aqua = Color(0xFF5CE1E6);

  static const Color background = Color(0xFF07070B);
  static const Color surface = Color(0xFF101016);
  static const Color surfaceElevated = Color(0xFF18181F);
  static const Color surfaceHigh = Color(0xFF22222C);

  static const Color bubbleMine = Color(0xFFC6FF4A);
  static const Color bubbleTheirs = Color(0xFF1A1A22);

  static const Color textPrimary = Color(0xFFF4F4F0);
  static const Color textSecondary = Color(0xFF9A9AA3);
  static const Color textFaint = Color(0xFF5C5C66);
  static const Color textOnLime = Color(0xFF0B1400);

  static const Color online = Color(0xFFC6FF4A);
  static const Color offline = Color(0xFF4A4A54);
  static const Color divider = Color(0x14FFFFFF);
  static const Color mention = Color(0xFFFF4D9A);
  static const Color danger = Color(0xFFFF5C7A);

  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: background,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static TextStyle display({
    double size = 28,
    FontWeight weight = FontWeight.w800,
    Color color = textPrimary,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.syne(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height ?? 1.05,
        letterSpacing: letterSpacing ?? -0.8,
      );

  static TextStyle body({
    double size = 15,
    FontWeight weight = FontWeight.w500,
    Color color = textPrimary,
    double? height,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height ?? 1.35,
      );

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: primaryInk,
        secondary: accent,
        surface: surface,
        onSurface: textPrimary,
        error: danger,
      ),
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlay,
        titleTextStyle: GoogleFonts.syne(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        hintStyle: GoogleFonts.plusJakartaSans(color: textFaint, fontWeight: FontWeight.w500),
        labelStyle: GoogleFonts.plusJakartaSans(color: textSecondary),
        floatingLabelStyle: GoogleFonts.plusJakartaSans(color: primary, fontWeight: FontWeight.w600),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: divider, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: primaryInk,
          disabledBackgroundColor: primary.withValues(alpha: 0.35),
          disabledForegroundColor: primaryInk.withValues(alpha: 0.5),
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.3),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: primaryInk,
        elevation: 0,
        shape: CircleBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: textPrimary, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1),
      dividerColor: divider,
      iconTheme: const IconThemeData(color: textSecondary),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.selected)) return primary;
            return surfaceElevated;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.selected)) return primaryInk;
            return textSecondary;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: divider)),
          textStyle: WidgetStateProperty.all(
            GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
