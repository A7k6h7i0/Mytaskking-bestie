import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/call_screen_design.dart';

/// Call-screen-only light/dark toggle for Mute–Buzzer button borders.
/// `false` (default) = blue neon borders; `true` = white borders.
final callScreenLightControlsProvider = StateProvider<bool>((_) => false);

/// Theme-aware palette for 1:1 call screens (voice + video backdrop).
class OneToOneCallPalette {
  const OneToOneCallPalette({
    required this.backgroundTop,
    required this.backgroundMid,
    required this.backgroundBottom,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accentGreen,
    required this.lightControls,
  });

  final Color backgroundTop;
  final Color backgroundMid;
  final Color backgroundBottom;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accentGreen;
  final bool lightControls;

  factory OneToOneCallPalette.forBrightness(Brightness brightness) {
    if (brightness == Brightness.light) {
      return const OneToOneCallPalette(
        backgroundTop: Color(0xFFFFFFFF),
        backgroundMid: Color(0xFFF8FAFC),
        backgroundBottom: Color(0xFFEEF2F7),
        textPrimary: Color(0xFF111827),
        textSecondary: Color(0xFF475569),
        textMuted: Color(0xFF64748B),
        accentGreen: Color(0xFF16A34A),
        lightControls: true,
      );
    }
    return const OneToOneCallPalette(
      backgroundTop: CallScreenUiColors.backgroundTop,
      backgroundMid: CallScreenUiColors.backgroundMid,
      backgroundBottom: CallScreenUiColors.backgroundBottom,
      textPrimary: CallScreenUiColors.textPrimary,
      textSecondary: CallScreenUiColors.textSecondary,
      textMuted: CallScreenUiColors.textMuted,
      accentGreen: CallScreenUiColors.neonGreen,
      lightControls: false,
    );
  }
}
