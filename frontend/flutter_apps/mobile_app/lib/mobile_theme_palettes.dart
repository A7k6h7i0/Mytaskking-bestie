import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

enum MobileThemeId {
  mytaskkingBlue('mytaskking_blue', 'MyTaskKing Blue', 'Default'),
  orangeMilk('orange_milk', 'Orange Milk', 'Theme 2'),
  forestSlate('forest_slate', 'Forest Slate', 'Theme 3');

  const MobileThemeId(this.storageKey, this.title, this.subtitle);
  final String storageKey;
  final String title;
  final String subtitle;

  static MobileThemeId fromStorage(String? raw) {
    for (final id in MobileThemeId.values) {
      if (id.storageKey == raw) return id;
    }
    return MobileThemeId.mytaskkingBlue;
  }
}

class MobileThemePalettes {
  MobileThemePalettes._();

  static BestiePaletteExtension basePaletteFor(MobileThemeId id) {
    switch (id) {
      case MobileThemeId.orangeMilk:
        return _orangeMilk;
      case MobileThemeId.forestSlate:
        return _forestSlate;
      case MobileThemeId.mytaskkingBlue:
        return _mytaskkingBlue;
    }
  }

  static BestiePaletteExtension paletteFor(
    MobileThemeId id, {
    Map<String, int>? overrides,
  }) {
    final base = basePaletteFor(id);
    if (overrides == null || overrides.isEmpty) return base;
    return base.withColorValues(overrides);
  }

  static const _mytaskkingBlue = BestiePaletteExtension(
    id: 'mytaskking_blue',
    bg: BestieTokens.cBg,
    bgSoft: BestieTokens.cBgSoft,
    bgTint: BestieTokens.cBgTint,
    surface: BestieTokens.cSurface,
    surface1: BestieTokens.cSurface1,
    surface2: BestieTokens.cSurface2,
    surface3: BestieTokens.cSurface3,
    border: BestieTokens.cBorder,
    borderSoft: BestieTokens.cBorderSoft,
    borderStrong: BestieTokens.cBorderStrong,
    text: BestieTokens.cText,
    textSoft: BestieTokens.cTextSoft,
    textMuted: BestieTokens.cTextMuted,
    textFaint: BestieTokens.cTextFaint,
    brand: BestieTokens.cBrand,
    brandSoft: BestieTokens.cBrandSoft,
    brandStrong: BestieTokens.cBrandStrong,
    accent: BestieTokens.cAccent,
    accentSoft: BestieTokens.cAccentSoft,
    backdropTop: Color(0xFFF8FBFF),
    backdropMid: Color(0xFFF2F7FF),
    backdropBottom: Color(0xFFEEF4FF),
    backdropDot: Color(0xFF0A4AA6),
    panelBorder: Color(0xFFDCE6F5),
    panelGradientStart: Color(0xE0FFFFFF),
    panelGradientEnd: Color(0xDBF5F9FF),
    sidebarGradientStart: Colors.white,
    sidebarGradientEnd: Color(0xFFF6FAFF),
    sidebarActiveStart: Color(0xFF062E78),
    sidebarActiveEnd: Color(0xFF0A4AA6),
    logoGradientStart: Color(0xFF08307A),
    logoGradientEnd: Color(0xFF0C4FBF),
    previewGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF0C4FBF),
        Color(0xFF397BF6),
        Color(0xFF09A7FF),
        Color(0xFFEEF4FF),
      ],
      stops: [0.0, 0.35, 0.62, 1.0],
    ),
  );

  static const _orangeMilk = BestiePaletteExtension(
    id: 'orange_milk',
    bg: Color(0xFFFFFBF7),
    bgSoft: Color(0xFFFFF7ED),
    bgTint: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surface1: Color(0xFFFFFBF7),
    surface2: Color(0xFFFFF1E6),
    surface3: Color(0xFFFFE8D6),
    border: Color(0xFFFED7AA),
    borderSoft: Color(0xFFFFEDD5),
    borderStrong: Color(0xFFFDBA74),
    text: Color(0xFF1C1917),
    textSoft: Color(0xFF57534E),
    textMuted: Color(0xFF78716C),
    textFaint: Color(0xFFA8A29E),
    brand: Color(0xFFEA580C),
    brandSoft: Color(0xFFFFEDD5),
    brandStrong: Color(0xFFC2410C),
    accent: Color(0xFFFB923C),
    accentSoft: Color(0xFFFFF7ED),
    backdropTop: Color(0xFFFFFBF7),
    backdropMid: Color(0xFFFFF7ED),
    backdropBottom: Color(0xFFFFEDD5),
    backdropDot: Color(0xFFEA580C),
    panelBorder: Color(0xFFFED7AA),
    panelGradientStart: Color(0xE0FFFFFF),
    panelGradientEnd: Color(0xDBFFFBF7),
    sidebarGradientStart: Color(0xFFFFFFFF),
    sidebarGradientEnd: Color(0xFFFFF7ED),
    sidebarActiveStart: Color(0xFFC2410C),
    sidebarActiveEnd: Color(0xFFEA580C),
    logoGradientStart: Color(0xFF9A3412),
    logoGradientEnd: Color(0xFFEA580C),
    previewGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFEA580C),
        Color(0xFFFB923C),
        Color(0xFFFFEDD5),
        Color(0xFFFFFBF7),
      ],
      stops: [0.0, 0.38, 0.68, 1.0],
    ),
  );

  static const _forestSlate = BestiePaletteExtension(
    id: 'forest_slate',
    bg: Color(0xFFF1F5F4),
    bgSoft: Color(0xFFE8EEEC),
    bgTint: Color(0xFFF8FAF9),
    surface: Color(0xFFFFFFFF),
    surface1: Color(0xFFF8FAF9),
    surface2: Color(0xFFE8F0ED),
    surface3: Color(0xFFD5E3DE),
    border: Color(0xFFCBD5E1),
    borderSoft: Color(0xFFE2E8F0),
    borderStrong: Color(0xFF94A3B8),
    text: Color(0xFF0F172A),
    textSoft: Color(0xFF334155),
    textMuted: Color(0xFF64748B),
    textFaint: Color(0xFF94A3B8),
    brand: Color(0xFF166534),
    brandSoft: Color(0xFFDCFCE7),
    brandStrong: Color(0xFF14532D),
    accent: Color(0xFF1E3A5F),
    accentSoft: Color(0xFFE2E8F0),
    backdropTop: Color(0xFFF8FAF9),
    backdropMid: Color(0xFFF1F5F4),
    backdropBottom: Color(0xFFE8EEEC),
    backdropDot: Color(0xFF166534),
    panelBorder: Color(0xFFCBD5E1),
    panelGradientStart: Color(0xE0FFFFFF),
    panelGradientEnd: Color(0xDBF8FAF9),
    sidebarGradientStart: Color(0xFFFFFFFF),
    sidebarGradientEnd: Color(0xFFE8F0ED),
    sidebarActiveStart: Color(0xFF14532D),
    sidebarActiveEnd: Color(0xFF166534),
    logoGradientStart: Color(0xFF14532D),
    logoGradientEnd: Color(0xFF1E3A5F),
    previewGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF14532D),
        Color(0xFF166534),
        Color(0xFF1E3A5F),
        Color(0xFFF8FAF9),
      ],
      stops: [0.0, 0.34, 0.62, 1.0],
    ),
  );

  static ThemeData applyTo(ThemeData base, BestiePaletteExtension palette) {
    final isDark = base.brightness == Brightness.dark;
    if (isDark) {
      return base.copyWith(extensions: [palette]);
    }
    return base.copyWith(
      extensions: [palette],
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: base.colorScheme.copyWith(
        primary: palette.brand,
        onPrimary: Colors.white,
        primaryContainer: palette.brandSoft,
        onPrimaryContainer: palette.brandStrong,
        secondary: palette.accent,
        onSecondary: Colors.white,
        secondaryContainer: palette.accentSoft,
        surface: palette.surface,
        onSurface: palette.text,
        surfaceContainerLowest: palette.surface1,
        surfaceContainerLow: palette.surface1,
        surfaceContainer: palette.surface2,
        surfaceContainerHigh: palette.surface3,
        outline: palette.borderStrong,
        outlineVariant: palette.border,
        onSurfaceVariant: palette.textMuted,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: palette.surface.withValues(alpha: 0.78),
        foregroundColor: palette.text,
      ),
      cardTheme: base.cardTheme.copyWith(color: palette.surface),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: palette.surface,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BestieTokens.rSm),
          borderSide: BorderSide(color: palette.brand, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.brand,
          foregroundColor: Colors.white,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.brand,
          foregroundColor: Colors.white,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: palette.brandStrong),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: palette.surface,
        indicatorColor: palette.brandSoft,
      ),
      chipTheme: base.chipTheme.copyWith(backgroundColor: palette.surface2),
      dividerTheme: base.dividerTheme.copyWith(color: palette.border),
      progressIndicatorTheme:
          base.progressIndicatorTheme.copyWith(color: palette.brand),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : palette.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? palette.brand
              : palette.borderStrong,
        ),
      ),
    );
  }
}

/// Brand-aligned colors for Windows screens that used hardcoded Tailwind blues.
class DesktopUiColors {
  DesktopUiColors._(this._palette);

  final BestiePaletteExtension? _palette;

  factory DesktopUiColors.of(BuildContext context) {
    return DesktopUiColors._(
      Theme.of(context).extension<BestiePaletteExtension>(),
    );
  }

  Color get primaryBlue => _palette?.brand ?? const Color(0xFF0C4FBF);
  Color get textMain => _palette?.text ?? const Color(0xFF0B0E13);
  Color get textMuted => _palette?.textMuted ?? const Color(0xFF828A9B);
  Color get textLight => _palette?.textFaint ?? const Color(0xFFB4BAC6);
  Color get borderColor => _palette?.border ?? const Color(0xFFD8E2F4);
  Color get bgPage => _palette?.surface ?? Colors.white;
  Color get bgSurface => _palette?.surface ?? Colors.white;
  Color get blueLight => _palette?.brandSoft ?? const Color(0xFFDCEAFF);
}
