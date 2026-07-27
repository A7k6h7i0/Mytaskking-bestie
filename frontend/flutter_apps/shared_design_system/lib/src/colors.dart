import 'package:flutter/material.dart';
import 'palette_extension.dart';
import 'tokens.dart';

/// Theme-aware accessor for the Bestie palette.
///
/// `BestieTokens.cSurface` (etc.) are raw light-mode hex constants — useful for
/// gradients, but they bypass `Brightness.dark`. Use `BestieColors.of(context)`
/// inside screens/widgets so the same code renders the right palette in both
/// themes. The mapping mirrors the React `--c-*` CSS variables that flip via
/// `.theme-dark`.
class BestieColors {
  final bool isDark;

  // surfaces
  final Color bg;
  final Color bgSoft;
  final Color bgTint;
  final Color surface;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color borderSoft;
  final Color borderStrong;

  // text
  final Color text;
  final Color textSoft;
  final Color textMuted;
  final Color textFaint;

  // brand / accent / status — primaries don't flip, soft variants do
  final Color brand;
  final Color brandSoft;
  final Color brandStrong;
  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  // clients always render in red
  final Color client;
  final Color clientSoft;

  // commonly-needed elevation list
  final List<BoxShadow> shadow1;
  final List<BoxShadow> shadow2;
  final List<BoxShadow> shadowPop;

  const BestieColors._({
    required this.isDark,
    required this.bg,
    required this.bgSoft,
    required this.bgTint,
    required this.surface,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderSoft,
    required this.borderStrong,
    required this.text,
    required this.textSoft,
    required this.textMuted,
    required this.textFaint,
    required this.brand,
    required this.brandSoft,
    required this.brandStrong,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.client,
    required this.clientSoft,
    required this.shadow1,
    required this.shadow2,
    required this.shadowPop,
  });

  /// Resolve the palette from the surrounding `Theme.of(context).brightness`.
  factory BestieColors.of(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final override = theme.extension<BestiePaletteExtension>();
    return BestieColors.resolve(isDark: isDark, override: override);
  }

  /// Resolve directly without a context — handy for theme builders.
  factory BestieColors.resolve({
    required bool isDark,
    BestiePaletteExtension? override,
  }) {
    if (!isDark && override != null) {
      final status = _statusFromPalette(override, isDark: false);
      return BestieColors._(
        isDark: false,
        bg: override.bg,
        bgSoft: override.bgSoft,
        bgTint: override.bgTint,
        surface: override.surface,
        surface1: override.surface1,
        surface2: override.surface2,
        surface3: override.surface3,
        border: override.border,
        borderSoft: override.borderSoft,
        borderStrong: override.borderStrong,
        text: override.text,
        textSoft: override.textSoft,
        textMuted: override.textMuted,
        textFaint: override.textFaint,
        brand: override.brand,
        brandSoft: override.brandSoft,
        brandStrong: override.brandStrong,
        accent: override.accent,
        accentSoft: override.accentSoft,
        success: status.success,
        successSoft: status.successSoft,
        warning: status.warning,
        warningSoft: status.warningSoft,
        danger: status.danger,
        dangerSoft: status.dangerSoft,
        info: status.info,
        infoSoft: status.infoSoft,
        client: status.client,
        clientSoft: status.clientSoft,
        shadow1: BestieTokens.shadowSoft,
        shadow2: BestieTokens.shadow1,
        shadowPop: BestieTokens.shadowPop,
      );
    }
    if (isDark) {
      // Keep dark surfaces for readability, but honor the selected palette's
      // brand/accent so Orange Milk / Forest Slate still tint buttons & chips.
      final status = override != null
          ? _statusFromPalette(override, isDark: true)
          : (
              success: BestieTokens.cSuccess,
              successSoft: BestieTokens.cSuccessSoftDark,
              warning: BestieTokens.cWarning,
              warningSoft: BestieTokens.cWarningSoftDark,
              danger: BestieTokens.cDanger,
              dangerSoft: BestieTokens.cDangerSoftDark,
              info: BestieTokens.cInfo,
              infoSoft: BestieTokens.cInfoSoftDark,
              client: BestieTokens.cClient,
              clientSoft: BestieTokens.cClientSoftDark,
            );
      return BestieColors._(
        isDark: true,
        bg:           BestieTokens.cBgDark,
        bgSoft:       BestieTokens.cBgSoftDark,
        bgTint:       BestieTokens.cBgTintDark,
        surface:      BestieTokens.cSurfaceDark,
        surface1:     BestieTokens.cSurface1Dark,
        surface2:     BestieTokens.cSurface2Dark,
        surface3:     BestieTokens.cSurface3Dark,
        border:       BestieTokens.cBorderDark,
        borderSoft:   BestieTokens.cBorderSoftDark,
        borderStrong: BestieTokens.cBorderStrongDark,
        text:         BestieTokens.cTextDark,
        textSoft:     BestieTokens.cTextSoftDark,
        textMuted:    BestieTokens.cTextMutedDark,
        textFaint:    BestieTokens.cTextFaintDark,
        brand:        override?.brand ?? BestieTokens.cBrand400,
        brandSoft:    override != null
            ? override.brand.withValues(alpha: 0.22)
            : BestieTokens.cBrandSoftDark,
        brandStrong:  override?.brandStrong ?? BestieTokens.cBrand300,
        accent:       override?.accent ?? BestieTokens.cAccent,
        accentSoft:   override != null
            ? override.accent.withValues(alpha: 0.18)
            : BestieTokens.cAccentSoftDark,
        success:      status.success,
        successSoft:  status.successSoft,
        warning:      status.warning,
        warningSoft:  status.warningSoft,
        danger:       status.danger,
        dangerSoft:   status.dangerSoft,
        info:         status.info,
        infoSoft:     status.infoSoft,
        client:       status.client,
        clientSoft:   status.clientSoft,
        shadow1:      const [
          BoxShadow(color: Color(0x73000000), blurRadius: 2, offset: Offset(0, 1)),
        ],
        shadow2:      const [
          BoxShadow(color: Color(0x73000000), blurRadius: 12, offset: Offset(0, 4)),
          BoxShadow(color: Color(0x4D000000), blurRadius: 3,  offset: Offset(0, 1)),
        ],
        shadowPop:    const [
          BoxShadow(color: Color(0xB3000000), blurRadius: 72, offset: Offset(0, 28)),
        ],
      );
    }
    return BestieColors._(
      isDark: false,
      bg:           BestieTokens.cBg,
      bgSoft:       BestieTokens.cBgSoft,
      bgTint:       BestieTokens.cBgTint,
      surface:      BestieTokens.cSurface,
      surface1:     BestieTokens.cSurface1,
      surface2:     BestieTokens.cSurface2,
      surface3:     BestieTokens.cSurface3,
      border:       BestieTokens.cBorder,
      borderSoft:   BestieTokens.cBorderSoft,
      borderStrong: BestieTokens.cBorderStrong,
      text:         BestieTokens.cText,
      textSoft:     BestieTokens.cTextSoft,
      textMuted:    BestieTokens.cTextMuted,
      textFaint:    BestieTokens.cTextFaint,
      brand:        BestieTokens.cBrand,
      brandSoft:    BestieTokens.cBrandSoft,
      brandStrong:  BestieTokens.cBrandStrong,
      accent:       BestieTokens.cAccent,
      accentSoft:   BestieTokens.cAccentSoft,
      success:      BestieTokens.cSuccess,
      successSoft:  BestieTokens.cSuccessSoft,
      warning:      BestieTokens.cWarning,
      warningSoft:  BestieTokens.cWarningSoft,
      danger:       BestieTokens.cDanger,
      dangerSoft:   BestieTokens.cDangerSoft,
      info:         BestieTokens.cInfo,
      infoSoft:     BestieTokens.cInfoSoft,
      client:       BestieTokens.cClient,
      clientSoft:   BestieTokens.cClientSoft,
      shadow1:      BestieTokens.shadowSoft,
      shadow2:      BestieTokens.shadow1,
      shadowPop:    BestieTokens.shadowPop,
    );
  }
}

/// Status / priority tones for themed palettes.
///
/// Default MyTaskKing Blue keeps classic green/amber/red/sky so existing
/// screens stay familiar. Gray & White (and other custom palettes) remaps
/// those roles into brand-family shades so yellow/blue accents don't clash
/// with a monochrome or orange/forest look.
({
  Color success,
  Color successSoft,
  Color warning,
  Color warningSoft,
  Color danger,
  Color dangerSoft,
  Color info,
  Color infoSoft,
  Color client,
  Color clientSoft,
}) _statusFromPalette(BestiePaletteExtension palette, {required bool isDark}) {
  // Keep the original semantic rainbow on the default blue theme.
  if (palette.id == 'mytaskking_blue') {
    return (
      success: BestieTokens.cSuccess,
      successSoft:
          isDark ? BestieTokens.cSuccessSoftDark : BestieTokens.cSuccessSoft,
      warning: BestieTokens.cWarning,
      warningSoft:
          isDark ? BestieTokens.cWarningSoftDark : BestieTokens.cWarningSoft,
      danger: BestieTokens.cDanger,
      dangerSoft:
          isDark ? BestieTokens.cDangerSoftDark : BestieTokens.cDangerSoft,
      info: BestieTokens.cInfo,
      infoSoft: isDark ? BestieTokens.cInfoSoftDark : BestieTokens.cInfoSoft,
      client: BestieTokens.cClient,
      clientSoft:
          isDark ? BestieTokens.cClientSoftDark : BestieTokens.cClientSoft,
    );
  }

  final brand = palette.brand;
  final brandSoft = isDark
      ? brand.withValues(alpha: 0.22)
      : palette.brandSoft;
  final brandStrong = palette.brandStrong;
  final accent = palette.accent;
  final hsl = HSLColor.fromColor(brand);
  final monochrome = hsl.saturation < 0.18;

  if (monochrome) {
    // Gray & White: every status role is a shade of brand — same family as
    // Morning check-in's icon, with lightness steps for priority hierarchy.
    final soft = isDark ? brand.withValues(alpha: 0.18) : brandSoft;
    return (
      success: brandStrong,
      successSoft: soft,
      warning: brand,
      warningSoft: soft,
      danger: brandStrong,
      dangerSoft: soft,
      info: accent,
      infoSoft: soft,
      client: palette.textMuted,
      clientSoft: soft,
    );
  }

  // Chromatic themes (Orange Milk / Forest Slate): blend classic semantics
  // toward brand so chips stay readable but feel on-palette.
  Color mix(Color semantic, double towardBrand) =>
      Color.lerp(semantic, brand, towardBrand)!;
  Color softMix(Color semanticSoft, double towardBrandSoft) => isDark
      ? mix(semanticSoft, towardBrandSoft).withValues(alpha: 0.22)
      : Color.lerp(semanticSoft, brandSoft, towardBrandSoft)!;

  return (
    success: mix(BestieTokens.cSuccess, 0.38),
    successSoft: softMix(
      isDark ? BestieTokens.cSuccessSoftDark : BestieTokens.cSuccessSoft,
      0.45,
    ),
    warning: mix(BestieTokens.cWarning, 0.48),
    warningSoft: softMix(
      isDark ? BestieTokens.cWarningSoftDark : BestieTokens.cWarningSoft,
      0.5,
    ),
    danger: mix(BestieTokens.cDanger, 0.32),
    dangerSoft: softMix(
      isDark ? BestieTokens.cDangerSoftDark : BestieTokens.cDangerSoft,
      0.4,
    ),
    info: mix(BestieTokens.cInfo, 0.42),
    infoSoft: softMix(
      isDark ? BestieTokens.cInfoSoftDark : BestieTokens.cInfoSoft,
      0.45,
    ),
    client: mix(BestieTokens.cClient, 0.4),
    clientSoft: softMix(
      isDark ? BestieTokens.cClientSoftDark : BestieTokens.cClientSoft,
      0.45,
    ),
  );
}
