import 'package:flutter/material.dart';

/// Single source of truth for color, spacing, radius, type, and motion.
/// Mirrors the React tokens in `frontend/react_web/src/styles/tokens.css`.
class BestieTokens {
  // ---- color: surfaces (light)
  static const cBg            = Color(0xFFF4F6FB);
  static const cBgSoft        = Color(0xFFECEFF7);
  static const cBgTint        = Color(0xFFF7F9FD);
  static const cSurface       = Color(0xFFFFFFFF);
  static const cSurface1      = Color(0xFFFBFCFE);
  static const cSurface2      = Color(0xFFF1F4FA);
  static const cSurface3      = Color(0xFFE8ECF4);
  static const cBorder        = Color(0xFFE4E7EF);
  static const cBorderSoft    = Color(0xFFEEF0F6);
  static const cBorderStrong  = Color(0xFFD0D4E0);

  // ---- color: text
  static const cText        = Color(0xFF0B0E13);
  static const cTextSoft    = Color(0xFF424A5B);
  static const cTextMuted   = Color(0xFF828A9B);
  static const cTextFaint   = Color(0xFFB4BAC6);
  static const cTextInvert  = Color(0xFFFFFFFF);

  // ---- brand (Lark-ish blue family)
  static const cBrand50     = Color(0xFFEEF3FF);
  static const cBrand100    = Color(0xFFDDE6FF);
  static const cBrand200    = Color(0xFFB8CAFF);
  static const cBrand300    = Color(0xFF8BA9FF);
  static const cBrand400    = Color(0xFF5D86FF);
  static const cBrand       = Color(0xFF3A6DF0);
  static const cBrandSoft   = Color(0xFFE7EEFF);
  static const cBrandStrong = Color(0xFF2A55C8);
  static const cBrandDeep   = Color(0xFF1B3DA5);
  static const cAccent      = Color(0xFF7C5CFF);
  static const cAccentSoft  = Color(0xFFECE6FF);

  // ---- gradient stops
  static const gBrand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C5CFF), Color(0xFF3A6DF0), Color(0xFF3AA1FF)],
    stops: [0.0, 0.55, 1.0],
  );

  // ---- status
  static const cSuccess     = Color(0xFF10B981);
  static const cSuccessSoft = Color(0xFFDCFCE7);
  static const cWarning     = Color(0xFFF59E0B);
  static const cWarningSoft = Color(0xFFFEF3C7);
  static const cDanger      = Color(0xFFEF4444);
  static const cDangerSoft  = Color(0xFFFEE2E2);
  static const cInfo        = Color(0xFF0EA5E9);
  static const cInfoSoft    = Color(0xFFE0F2FE);

  // ---- clients always render in red
  static const cClient     = Color(0xFFE0254A);
  static const cClientSoft = Color(0xFFFDE7EC);

  // ---- elevation
  static const shadowSoft = [
    BoxShadow(color: Color(0x0A0F1216), blurRadius: 2,  offset: Offset(0, 1)),
    BoxShadow(color: Color(0x060F1216), blurRadius: 1,  offset: Offset(0, 1)),
  ];
  static const shadow1 = [
    BoxShadow(color: Color(0x0A0F1216), blurRadius: 4,  offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0F0F1216), blurRadius: 18, offset: Offset(0, 8)),
  ];
  static const shadow2 = [
    BoxShadow(color: Color(0x0F0F1216), blurRadius: 8,  offset: Offset(0, 4)),
    BoxShadow(color: Color(0x1A0F1216), blurRadius: 40, offset: Offset(0, 16)),
  ];
  static const shadowPop = [
    BoxShadow(color: Color(0x2E0F1216), blurRadius: 56, offset: Offset(0, 20)),
    BoxShadow(color: Color(0x140F1216), blurRadius: 8,  offset: Offset(0, 4)),
  ];

  // ---- radii
  static const rXs   = 6.0;
  static const rSm   = 10.0;
  static const rMd   = 14.0;
  static const rLg   = 18.0;
  static const rXl   = 24.0;
  static const r2Xl  = 32.0;
  static const rPill = 999.0;

  // ---- spacing
  static const s0 = 4.0;
  static const s1 = 8.0;
  static const s2 = 12.0;
  static const s3 = 16.0;
  static const s4 = 20.0;
  static const s5 = 24.0;
  static const s6 = 32.0;
  static const s7 = 40.0;
  static const s8 = 56.0;
  static const s9 = 72.0;

  // ---- type
  static const fsXs   = 12.0;
  static const fsSm   = 13.0;
  static const fsBase = 14.0;
  static const fsMd   = 15.0;
  static const fsLg   = 17.0;
  static const fsXl   = 20.0;
  static const fs2Xl  = 24.0;
  static const fs3Xl  = 30.0;
  static const fs4Xl  = 36.0;

  static const fwRegular  = FontWeight.w400;
  static const fwMedium   = FontWeight.w500;
  static const fwSemibold = FontWeight.w600;
  static const fwBold     = FontWeight.w700;

  static const lsTight   = -0.4;
  static const lsSnug    = -0.2;
  static const lsNormal  = -0.1;
  static const lsEyebrow = 1.4;

  // ---- motion
  static const durInstant = Duration(milliseconds: 80);
  static const durFast    = Duration(milliseconds: 140);
  static const dur        = Duration(milliseconds: 220);
  static const durMedium  = Duration(milliseconds: 320);
  static const durSlow    = Duration(milliseconds: 420);
  static const durXSlow   = Duration(milliseconds: 620);

  static const ease         = Curves.easeOutCubic;
  static const easeOut      = Cubic(0.16, 1, 0.3, 1);
  static const easeEmphasis = Cubic(0.2, 0, 0, 1);
  static const easeSpring   = Cubic(0.34, 1.56, 0.64, 1);
  static const easeSnap     = Cubic(0.5, 0, 0.2, 1);

  // ---- layout
  static const sidebarW          = 264.0;
  static const sidebarWCollapsed = 64.0;
  static const topbarH           = 56.0;

  // ---- dark theme palette
  // Surfaces
  static const cBgDark           = Color(0xFF0A0D12);
  static const cBgSoftDark       = Color(0xFF0E1218);
  static const cBgTintDark       = Color(0xFF11151C);
  static const cSurfaceDark      = Color(0xFF141923);
  static const cSurface1Dark     = Color(0xFF181D27);
  static const cSurface2Dark     = Color(0xFF1D232F);
  static const cSurface3Dark     = Color(0xFF232A38);
  static const cBorderDark       = Color(0xFF232A36);
  static const cBorderSoftDark   = Color(0xFF1C222D);
  static const cBorderStrongDark = Color(0xFF323B4B);

  // Text
  static const cTextDark      = Color(0xFFF0F3F8);
  static const cTextSoftDark  = Color(0xFFC4CAD8);
  static const cTextMutedDark = Color(0xFF8C95A6);
  static const cTextFaintDark = Color(0xFF5F6675);

  // Brand soft (dark)
  static const cBrandSoftDark   = Color(0xFF1C2A52);
  static const cAccentSoftDark  = Color(0xFF2A214A);
  static const cClientSoftDark  = Color(0xFF3A121E);
  static const cSuccessSoftDark = Color(0xFF0E2E23);
  static const cWarningSoftDark = Color(0xFF3A2A0C);
  static const cDangerSoftDark  = Color(0xFF3A1414);
  static const cInfoSoftDark    = Color(0xFF0C2A3A);
}
