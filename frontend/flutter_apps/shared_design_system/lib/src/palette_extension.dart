import 'package:flutter/material.dart';

/// Optional per-app palette override (Windows desktop themes).
/// When present on [ThemeData.extensions], [BestieColors.of] uses these values
/// in light mode instead of the default [BestieTokens].
@immutable
class BestiePaletteExtension extends ThemeExtension<BestiePaletteExtension> {
  const BestiePaletteExtension({
    required this.id,
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
    required this.backdropTop,
    required this.backdropMid,
    required this.backdropBottom,
    required this.backdropDot,
    required this.panelBorder,
    required this.panelGradientStart,
    required this.panelGradientEnd,
    required this.sidebarGradientStart,
    required this.sidebarGradientEnd,
    required this.sidebarActiveStart,
    required this.sidebarActiveEnd,
    required this.logoGradientStart,
    required this.logoGradientEnd,
    required this.previewGradient,
  });

  final String id;
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
  final Color text;
  final Color textSoft;
  final Color textMuted;
  final Color textFaint;
  final Color brand;
  final Color brandSoft;
  final Color brandStrong;
  final Color accent;
  final Color accentSoft;
  final Color backdropTop;
  final Color backdropMid;
  final Color backdropBottom;
  final Color backdropDot;
  final Color panelBorder;
  final Color panelGradientStart;
  final Color panelGradientEnd;
  final Color sidebarGradientStart;
  final Color sidebarGradientEnd;
  final Color sidebarActiveStart;
  final Color sidebarActiveEnd;
  final Color logoGradientStart;
  final Color logoGradientEnd;
  final Gradient previewGradient;

  @override
  BestiePaletteExtension copyWith({
    String? id,
    Color? bg,
    Color? bgSoft,
    Color? bgTint,
    Color? surface,
    Color? surface1,
    Color? surface2,
    Color? surface3,
    Color? border,
    Color? borderSoft,
    Color? borderStrong,
    Color? text,
    Color? textSoft,
    Color? textMuted,
    Color? textFaint,
    Color? brand,
    Color? brandSoft,
    Color? brandStrong,
    Color? accent,
    Color? accentSoft,
    Color? backdropTop,
    Color? backdropMid,
    Color? backdropBottom,
    Color? backdropDot,
    Color? panelBorder,
    Color? panelGradientStart,
    Color? panelGradientEnd,
    Color? sidebarGradientStart,
    Color? sidebarGradientEnd,
    Color? sidebarActiveStart,
    Color? sidebarActiveEnd,
    Color? logoGradientStart,
    Color? logoGradientEnd,
    Gradient? previewGradient,
  }) {
    return BestiePaletteExtension(
      id: id ?? this.id,
      bg: bg ?? this.bg,
      bgSoft: bgSoft ?? this.bgSoft,
      bgTint: bgTint ?? this.bgTint,
      surface: surface ?? this.surface,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      border: border ?? this.border,
      borderSoft: borderSoft ?? this.borderSoft,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      textSoft: textSoft ?? this.textSoft,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      brand: brand ?? this.brand,
      brandSoft: brandSoft ?? this.brandSoft,
      brandStrong: brandStrong ?? this.brandStrong,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      backdropTop: backdropTop ?? this.backdropTop,
      backdropMid: backdropMid ?? this.backdropMid,
      backdropBottom: backdropBottom ?? this.backdropBottom,
      backdropDot: backdropDot ?? this.backdropDot,
      panelBorder: panelBorder ?? this.panelBorder,
      panelGradientStart: panelGradientStart ?? this.panelGradientStart,
      panelGradientEnd: panelGradientEnd ?? this.panelGradientEnd,
      sidebarGradientStart: sidebarGradientStart ?? this.sidebarGradientStart,
      sidebarGradientEnd: sidebarGradientEnd ?? this.sidebarGradientEnd,
      sidebarActiveStart: sidebarActiveStart ?? this.sidebarActiveStart,
      sidebarActiveEnd: sidebarActiveEnd ?? this.sidebarActiveEnd,
      logoGradientStart: logoGradientStart ?? this.logoGradientStart,
      logoGradientEnd: logoGradientEnd ?? this.logoGradientEnd,
      previewGradient: previewGradient ?? this.previewGradient,
    );
  }

  @override
  BestiePaletteExtension lerp(
    ThemeExtension<BestiePaletteExtension>? other,
    double t,
  ) {
    if (other is! BestiePaletteExtension) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return BestiePaletteExtension(
      id: t < 0.5 ? id : other.id,
      bg: l(bg, other.bg),
      bgSoft: l(bgSoft, other.bgSoft),
      bgTint: l(bgTint, other.bgTint),
      surface: l(surface, other.surface),
      surface1: l(surface1, other.surface1),
      surface2: l(surface2, other.surface2),
      surface3: l(surface3, other.surface3),
      border: l(border, other.border),
      borderSoft: l(borderSoft, other.borderSoft),
      borderStrong: l(borderStrong, other.borderStrong),
      text: l(text, other.text),
      textSoft: l(textSoft, other.textSoft),
      textMuted: l(textMuted, other.textMuted),
      textFaint: l(textFaint, other.textFaint),
      brand: l(brand, other.brand),
      brandSoft: l(brandSoft, other.brandSoft),
      brandStrong: l(brandStrong, other.brandStrong),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      backdropTop: l(backdropTop, other.backdropTop),
      backdropMid: l(backdropMid, other.backdropMid),
      backdropBottom: l(backdropBottom, other.backdropBottom),
      backdropDot: l(backdropDot, other.backdropDot),
      panelBorder: l(panelBorder, other.panelBorder),
      panelGradientStart: l(panelGradientStart, other.panelGradientStart),
      panelGradientEnd: l(panelGradientEnd, other.panelGradientEnd),
      sidebarGradientStart: l(sidebarGradientStart, other.sidebarGradientStart),
      sidebarGradientEnd: l(sidebarGradientEnd, other.sidebarGradientEnd),
      sidebarActiveStart: l(sidebarActiveStart, other.sidebarActiveStart),
      sidebarActiveEnd: l(sidebarActiveEnd, other.sidebarActiveEnd),
      logoGradientStart: l(logoGradientStart, other.logoGradientStart),
      logoGradientEnd: l(logoGradientEnd, other.logoGradientEnd),
      previewGradient: previewGradient,
    );
  }
}

extension BestiePaletteExtensionX on ThemeData {
  BestiePaletteExtension? get bestiePalette =>
      extension<BestiePaletteExtension>();
}

/// Human-readable labels for desktop theme color editing.
class BestiePaletteColorField {
  const BestiePaletteColorField(this.key, this.label);

  final String key;
  final String label;
}

extension BestiePaletteEditing on BestiePaletteExtension {
  static const editableFields = <BestiePaletteColorField>[
    BestiePaletteColorField('bg', 'Background'),
    BestiePaletteColorField('bgSoft', 'Background soft'),
    BestiePaletteColorField('bgTint', 'Background tint'),
    BestiePaletteColorField('surface', 'Surface'),
    BestiePaletteColorField('surface1', 'Surface 1'),
    BestiePaletteColorField('surface2', 'Surface 2'),
    BestiePaletteColorField('surface3', 'Surface 3'),
    BestiePaletteColorField('border', 'Border'),
    BestiePaletteColorField('borderSoft', 'Border soft'),
    BestiePaletteColorField('borderStrong', 'Border strong'),
    BestiePaletteColorField('text', 'Text'),
    BestiePaletteColorField('textSoft', 'Text soft'),
    BestiePaletteColorField('textMuted', 'Text muted'),
    BestiePaletteColorField('textFaint', 'Text faint'),
    BestiePaletteColorField('brand', 'Brand'),
    BestiePaletteColorField('brandSoft', 'Brand soft'),
    BestiePaletteColorField('brandStrong', 'Brand strong'),
    BestiePaletteColorField('accent', 'Accent'),
    BestiePaletteColorField('accentSoft', 'Accent soft'),
    BestiePaletteColorField('backdropTop', 'Backdrop top'),
    BestiePaletteColorField('backdropMid', 'Backdrop mid'),
    BestiePaletteColorField('backdropBottom', 'Backdrop bottom'),
    BestiePaletteColorField('backdropDot', 'Backdrop dot'),
    BestiePaletteColorField('panelBorder', 'Panel border'),
    BestiePaletteColorField('panelGradientStart', 'Panel gradient start'),
    BestiePaletteColorField('panelGradientEnd', 'Panel gradient end'),
    BestiePaletteColorField('sidebarGradientStart', 'Sidebar gradient start'),
    BestiePaletteColorField('sidebarGradientEnd', 'Sidebar gradient end'),
    BestiePaletteColorField('sidebarActiveStart', 'Sidebar active start'),
    BestiePaletteColorField('sidebarActiveEnd', 'Sidebar active end'),
    BestiePaletteColorField('logoGradientStart', 'Logo gradient start'),
    BestiePaletteColorField('logoGradientEnd', 'Logo gradient end'),
  ];

  Color colorForKey(String key) {
    switch (key) {
      case 'bg':
        return bg;
      case 'bgSoft':
        return bgSoft;
      case 'bgTint':
        return bgTint;
      case 'surface':
        return surface;
      case 'surface1':
        return surface1;
      case 'surface2':
        return surface2;
      case 'surface3':
        return surface3;
      case 'border':
        return border;
      case 'borderSoft':
        return borderSoft;
      case 'borderStrong':
        return borderStrong;
      case 'text':
        return text;
      case 'textSoft':
        return textSoft;
      case 'textMuted':
        return textMuted;
      case 'textFaint':
        return textFaint;
      case 'brand':
        return brand;
      case 'brandSoft':
        return brandSoft;
      case 'brandStrong':
        return brandStrong;
      case 'accent':
        return accent;
      case 'accentSoft':
        return accentSoft;
      case 'backdropTop':
        return backdropTop;
      case 'backdropMid':
        return backdropMid;
      case 'backdropBottom':
        return backdropBottom;
      case 'backdropDot':
        return backdropDot;
      case 'panelBorder':
        return panelBorder;
      case 'panelGradientStart':
        return panelGradientStart;
      case 'panelGradientEnd':
        return panelGradientEnd;
      case 'sidebarGradientStart':
        return sidebarGradientStart;
      case 'sidebarGradientEnd':
        return sidebarGradientEnd;
      case 'sidebarActiveStart':
        return sidebarActiveStart;
      case 'sidebarActiveEnd':
        return sidebarActiveEnd;
      case 'logoGradientStart':
        return logoGradientStart;
      case 'logoGradientEnd':
        return logoGradientEnd;
      default:
        return brand;
    }
  }

  Map<String, int> toColorValueMap() {
    return {
      for (final field in BestiePaletteEditing.editableFields)
        field.key: colorForKey(field.key).toARGB32(),
    };
  }

  BestiePaletteExtension withColorValues(Map<String, int> values) {
    Color pick(String key, Color fallback) {
      final raw = values[key];
      return raw == null ? fallback : Color(raw);
    }

    final next = copyWith(
      bg: pick('bg', bg),
      bgSoft: pick('bgSoft', bgSoft),
      bgTint: pick('bgTint', bgTint),
      surface: pick('surface', surface),
      surface1: pick('surface1', surface1),
      surface2: pick('surface2', surface2),
      surface3: pick('surface3', surface3),
      border: pick('border', border),
      borderSoft: pick('borderSoft', borderSoft),
      borderStrong: pick('borderStrong', borderStrong),
      text: pick('text', text),
      textSoft: pick('textSoft', textSoft),
      textMuted: pick('textMuted', textMuted),
      textFaint: pick('textFaint', textFaint),
      brand: pick('brand', brand),
      brandSoft: pick('brandSoft', brandSoft),
      brandStrong: pick('brandStrong', brandStrong),
      accent: pick('accent', accent),
      accentSoft: pick('accentSoft', accentSoft),
      backdropTop: pick('backdropTop', backdropTop),
      backdropMid: pick('backdropMid', backdropMid),
      backdropBottom: pick('backdropBottom', backdropBottom),
      backdropDot: pick('backdropDot', backdropDot),
      panelBorder: pick('panelBorder', panelBorder),
      panelGradientStart: pick('panelGradientStart', panelGradientStart),
      panelGradientEnd: pick('panelGradientEnd', panelGradientEnd),
      sidebarGradientStart: pick('sidebarGradientStart', sidebarGradientStart),
      sidebarGradientEnd: pick('sidebarGradientEnd', sidebarGradientEnd),
      sidebarActiveStart: pick('sidebarActiveStart', sidebarActiveStart),
      sidebarActiveEnd: pick('sidebarActiveEnd', sidebarActiveEnd),
      logoGradientStart: pick('logoGradientStart', logoGradientStart),
      logoGradientEnd: pick('logoGradientEnd', logoGradientEnd),
      previewGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          pick('logoGradientStart', logoGradientStart),
          pick('brand', brand),
          pick('accent', accent),
          pick('backdropBottom', backdropBottom),
        ],
        stops: const [0.0, 0.35, 0.62, 1.0],
      ),
    );
    return next;
  }
}
