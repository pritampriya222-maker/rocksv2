import 'package:flutter/material.dart';

/// AppTheme: Solid dark gray, white text.
/// Per project constraint: NO gradients, NO color themes.
/// Functional and readable only.
class AppTheme {
  // Color palette - locked to spec
  static const Color background   = Color(0xFF1A1A1A); // Dark gray
  static const Color surface      = Color(0xFF242424); // Slightly lighter panel
  static const Color surfaceAlt   = Color(0xFF2E2E2E); // Input backgrounds
  static const Color border       = Color(0xFF3A3A3A); // Dividers
  static const Color textPrimary  = Color(0xFFFFFFFF); // White text
  static const Color textSecondary= Color(0xFFAAAAAA); // Muted labels
  static const Color textHint     = Color(0xFF666666); // Placeholder text
  static const Color accent       = Color(0xFF4FC3F7); // Functional highlight (status only)
  static const Color success      = Color(0xFF66BB6A);
  static const Color warning      = Color(0xFFFFA726);
  static const Color error        = Color(0xFFEF5350);

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      surface: surface,
      primary: accent,
      secondary: accent,
      error: error,
      onSurface: textPrimary,
      onPrimary: background,
    ),

    // AppBar: flat, no elevation
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        fontFamily: 'RobotoMono',
      ),
    ),

    // Cards: dark surface, no shadow
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: border, width: 1),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
    ),

    // Text fields: bordered, flat
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceAlt,
      hintStyle: const TextStyle(color: textHint),
      labelStyle: const TextStyle(color: textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),

    // Elevated buttons: flat, bordered
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: surfaceAlt,
        foregroundColor: textPrimary,
        elevation: 0,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'RobotoMono',
        ),
      ),
    ),

    // Text buttons
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(fontFamily: 'RobotoMono', fontSize: 13),
      ),
    ),

    // Dividers
    dividerTheme: const DividerThemeData(
      color: border,
      thickness: 1,
      space: 1,
    ),

    // Typography: monospace for technical data
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.w600),
      headlineSmall: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: textPrimary, fontSize: 15),
      bodyMedium: TextStyle(color: textPrimary, fontSize: 14),
      bodySmall: TextStyle(color: textSecondary, fontSize: 12),
      labelLarge: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium: TextStyle(color: textSecondary, fontSize: 12),
      labelSmall: TextStyle(color: textHint, fontSize: 11),
    ),

    fontFamily: 'RobotoMono',

    // Snack bars
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: surfaceAlt,
      contentTextStyle: TextStyle(color: textPrimary),
      behavior: SnackBarBehavior.floating,
    ),

    // Icons
    iconTheme: const IconThemeData(color: textSecondary, size: 20),
  );
}
