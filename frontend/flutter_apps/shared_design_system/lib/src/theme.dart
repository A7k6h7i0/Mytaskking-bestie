import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

class BestieTheme {
  static ThemeData light() {
    final base = ThemeData(brightness: Brightness.light, useMaterial3: true);
    final text = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: BestieTokens.cText,
      displayColor: BestieTokens.cText,
    );

    return base.copyWith(
      scaffoldBackgroundColor: BestieTokens.cBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BestieTokens.cBrand,
        brightness: Brightness.light,
      ).copyWith(
        primary: BestieTokens.cBrand,
        surface: BestieTokens.cSurface,
        error: BestieTokens.cDanger,
      ),
      textTheme: text,
      cardTheme: CardThemeData(
        color: BestieTokens.cSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rMd),
          side: const BorderSide(color: BestieTokens.cBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BestieTokens.cSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
          borderSide: const BorderSide(color: BestieTokens.cBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
          borderSide: const BorderSide(color: BestieTokens.cBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
          borderSide: const BorderSide(color: BestieTokens.cBrand, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BestieTokens.cBrand,
          foregroundColor: BestieTokens.cTextInvert,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BestieTokens.rSm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      dividerColor: BestieTokens.cBorder,
    );
  }
}
