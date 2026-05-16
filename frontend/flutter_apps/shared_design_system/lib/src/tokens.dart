import 'package:flutter/material.dart';

/// Single source of truth for color, spacing, radius, type, and motion.
/// Mirrors the React tokens in `frontend/react_web/src/styles/tokens.css`.
class BestieTokens {
  // ---- color: surfaces (light)
  static const cBg = Color(0xFFF6F7FB);
  static const cBgSoft = Color(0xFFEEF0F6);
  static const cSurface = Color(0xFFFFFFFF);
  static const cSurface1 = Color(0xFFFBFCFE);
  static const cSurface2 = Color(0xFFF3F5FA);
  static const cBorder = Color(0xFFE6E8EF);
  static const cBorderStrong = Color(0xFFD3D6E0);

  // ---- color: text
  static const cText = Color(0xFF0F1216);
  static const cTextSoft = Color(0xFF4A5160);
  static const cTextMuted = Color(0xFF8B93A3);
  static const cTextFaint = Color(0xFFB8BDC8);
  static const cTextInvert = Color(0xFFFFFFFF);

  // ---- brand
  static const cBrand = Color(0xFF5B8CFF);
  static const cBrandSoft = Color(0xFFE7EFFF);
  static const cBrandStrong = Color(0xFF3A6DF0);
  static const cAccent = Color(0xFF7C5CFF);

  // ---- status
  static const cSuccess = Color(0xFF10B981);
  static const cWarning = Color(0xFFF59E0B);
  static const cDanger = Color(0xFFEF4444);
  static const cInfo = Color(0xFF0EA5E9);

  // ---- clients always render in red
  static const cClient = Color(0xFFE0254A);
  static const cClientSoft = Color(0xFFFDE7EC);

  // ---- radii
  static const rXs = 6.0;
  static const rSm = 10.0;
  static const rMd = 14.0;
  static const rLg = 20.0;
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

  // ---- motion
  static const durFast = Duration(milliseconds: 120);
  static const dur = Duration(milliseconds: 200);
  static const durSlow = Duration(milliseconds: 360);
  static const ease = Curves.easeOutCubic;
  static const easeSpring = Curves.elasticOut;

  // ---- layout
  static const sidebarW = 268.0;
  static const sidebarWCollapsed = 64.0;
  static const topbarH = 56.0;
}
