import 'package:flutter/material.dart';

/// Single source of truth for color, spacing, radius, type, and motion.
/// Mirrors the React tokens in `frontend/react_web/src/styles/tokens.css`.
class BestieTokens {
  // ---- color: surfaces (light)
  static const cBg = Color(0xFFEEF4FF);
  static const cBgSoft = Color(0xFFE4ECFB);
  static const cBgTint = Color(0xFFF5F9FF);
  static const cSurface = Color(0xFFFFFFFF);
  static const cSurface1 = Color(0xFFFAFCFF);
  static const cSurface2 = Color(0xFFEDF3FF);
  static const cSurface3 = Color(0xFFDDE7F7);
  static const cBorder = Color(0xFFD8E2F4);
  static const cBorderSoft = Color(0xFFE8EEF8);
  static const cBorderStrong = Color(0xFFB9C8DE);

  // ---- color: text
  static const cText = Color(0xFF0B0E13);
  static const cTextSoft = Color(0xFF424A5B);
  static const cTextMuted = Color(0xFF828A9B);
  static const cTextFaint = Color(0xFFB4BAC6);
  static const cTextInvert = Color(0xFFFFFFFF);

  // ---- brand (Lark-ish blue family)
  static const cBrand50 = Color(0xFFEAF2FF);
  static const cBrand100 = Color(0xFFD8E6FF);
  static const cBrand200 = Color(0xFFABC7FF);
  static const cBrand300 = Color(0xFF78A4FF);
  static const cBrand400 = Color(0xFF397BF6);
  static const cBrand = Color(0xFF0C4FBF);
  static const cBrandSoft = Color(0xFFDCEAFF);
  static const cBrandStrong = Color(0xFF063D96);
  static const cBrandDeep = Color(0xFF082C6C);
  static const cAccent = Color(0xFF09A7FF);
  static const cAccentSoft = Color(0xFFD9F2FF);

  // ---- gradient stops
  static const gBrand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF072B78), Color(0xFF0C4FBF), Color(0xFF09A7FF)],
    stops: [0.0, 0.55, 1.0],
  );

  // ---- status
  static const cSuccess = Color(0xFF10B981);
  static const cSuccessSoft = Color(0xFFDCFCE7);
  static const cWarning = Color(0xFFF59E0B);
  static const cWarningSoft = Color(0xFFFEF3C7);
  static const cDanger = Color(0xFFEF4444);
  static const cDangerSoft = Color(0xFFFEE2E2);
  static const cInfo = Color(0xFF0EA5E9);
  static const cInfoSoft = Color(0xFFE0F2FE);

  // ---- clients always render in red
  static const cClient = Color(0xFFE0254A);
  static const cClientSoft = Color(0xFFFDE7EC);

  // ---- elevation
  static const shadowSoft = [
    BoxShadow(color: Color(0x0A082455), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x06082455), blurRadius: 1, offset: Offset(0, 1)),
  ];
  static const shadow1 = [
    BoxShadow(color: Color(0x0C082455), blurRadius: 6, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x12082455), blurRadius: 24, offset: Offset(0, 12)),
  ];
  static const shadow2 = [
    BoxShadow(color: Color(0x12082455), blurRadius: 10, offset: Offset(0, 5)),
    BoxShadow(color: Color(0x1E082455), blurRadius: 48, offset: Offset(0, 18)),
  ];
  static const shadowPop = [
    BoxShadow(color: Color(0x33082455), blurRadius: 62, offset: Offset(0, 24)),
    BoxShadow(color: Color(0x16082455), blurRadius: 10, offset: Offset(0, 5)),
  ];

  // ---- radii
  static const rXs = 6.0;
  static const rSm = 10.0;
  static const rMd = 14.0;
  static const rLg = 18.0;
  static const rXl = 24.0;
  static const r2Xl = 32.0;
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
  static const fsXs = 12.0;
  static const fsSm = 13.0;
  static const fsBase = 14.0;
  static const fsMd = 15.0;
  static const fsLg = 17.0;
  static const fsXl = 20.0;
  static const fs2Xl = 24.0;
  static const fs3Xl = 30.0;
  static const fs4Xl = 36.0;

  static const fwRegular = FontWeight.w400;
  static const fwMedium = FontWeight.w500;
  static const fwSemibold = FontWeight.w600;
  static const fwBold = FontWeight.w700;

  static const lsTight = -0.4;
  static const lsSnug = -0.2;
  static const lsNormal = -0.1;
  static const lsWide = 0.4;
  static const lsEyebrow = 1.4;

  // ---- motion
  static const durInstant = Duration(milliseconds: 80);
  static const durFast = Duration(milliseconds: 140);
  static const dur = Duration(milliseconds: 220);
  static const durMedium = Duration(milliseconds: 320);
  static const durSlow = Duration(milliseconds: 420);
  static const durXSlow = Duration(milliseconds: 620);

  static const ease = Curves.easeOutCubic;
  static const easeOut = Cubic(0.16, 1, 0.3, 1);
  static const easeEmphasis = Cubic(0.2, 0, 0, 1);
  static const easeSpring = Cubic(0.34, 1.56, 0.64, 1);
  static const easeSnap = Cubic(0.5, 0, 0.2, 1);

  // ---- layout
  static const sidebarW = 264.0;
  static const sidebarWCollapsed = 64.0;
  static const topbarH = 56.0;

  // ---- dark theme palette
  // Surfaces
  static const cBgDark = Color(0xFF050B18);
  static const cBgSoftDark = Color(0xFF071225);
  static const cBgTintDark = Color(0xFF0A1730);
  static const cSurfaceDark = Color(0xFF0D1931);
  static const cSurface1Dark = Color(0xFF10203D);
  static const cSurface2Dark = Color(0xFF15294A);
  static const cSurface3Dark = Color(0xFF1B3560);
  static const cBorderDark = Color(0xFF1D3562);
  static const cBorderSoftDark = Color(0xFF132744);
  static const cBorderStrongDark = Color(0xFF2C4A7D);

  // Text
  static const cTextDark = Color(0xFFF0F3F8);
  static const cTextSoftDark = Color(0xFFC4CAD8);
  static const cTextMutedDark = Color(0xFF8C95A6);
  static const cTextFaintDark = Color(0xFF5F6675);

  // Brand soft (dark)
  static const cBrandSoftDark = Color(0xFF0D2858);
  static const cAccentSoftDark = Color(0xFF073954);
  static const cClientSoftDark = Color(0xFF3A121E);
  static const cSuccessSoftDark = Color(0xFF0E2E23);
  static const cWarningSoftDark = Color(0xFF3A2A0C);
  static const cDangerSoftDark = Color(0xFF3A1414);
  static const cInfoSoftDark = Color(0xFF0C2A3A);
}
