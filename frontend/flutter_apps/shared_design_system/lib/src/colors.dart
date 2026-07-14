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
        success: BestieTokens.cSuccess,
        successSoft: BestieTokens.cSuccessSoft,
        warning: BestieTokens.cWarning,
        warningSoft: BestieTokens.cWarningSoft,
        danger: BestieTokens.cDanger,
        dangerSoft: BestieTokens.cDangerSoft,
        info: BestieTokens.cInfo,
        infoSoft: BestieTokens.cInfoSoft,
        client: BestieTokens.cClient,
        clientSoft: BestieTokens.cClientSoft,
        shadow1: BestieTokens.shadowSoft,
        shadow2: BestieTokens.shadow1,
        shadowPop: BestieTokens.shadowPop,
      );
    }
    if (isDark) {
      // Keep dark surfaces for readability, but honor the selected palette's
      // brand/accent so Orange Milk / Forest Slate still tint buttons & chips.
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
        success:      BestieTokens.cSuccess,
        successSoft:  BestieTokens.cSuccessSoftDark,
        warning:      BestieTokens.cWarning,
        warningSoft:  BestieTokens.cWarningSoftDark,
        danger:       BestieTokens.cDanger,
        dangerSoft:   BestieTokens.cDangerSoftDark,
        info:         BestieTokens.cInfo,
        infoSoft:     BestieTokens.cInfoSoftDark,
        client:       BestieTokens.cClient,
        clientSoft:   BestieTokens.cClientSoftDark,
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
