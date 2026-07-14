import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mobile_local_settings.dart';
import 'mobile_theme_palettes.dart';
import 'state.dart';

/// Per-organisation branding shown on the chat home header.
class OrgBranding {
  final String name;
  final String? logoUrl;
  final String? primaryColor;

  const OrgBranding({
    this.name = 'MyTaskKing',
    this.logoUrl,
    this.primaryColor,
  });
}

Color? parseBrandHex(String? raw) {
  if (raw == null) return null;
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('#')) text = text.substring(1);
  if (text.length == 6) text = 'FF$text';
  if (text.length != 8) return null;
  final value = int.tryParse(text, radix: 16);
  if (value == null) return null;
  return Color(value);
}

final orgBrandingProvider = FutureProvider<OrgBranding>((ref) async {
  try {
    final data = await ref.read(apiProvider).settingsScope(scope: 'branding');
    final branding =
        (data['branding'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = (branding['name'] ?? 'MyTaskKing').toString().trim();
    final logoUrl = branding['logoUrl']?.toString();
    final primaryColor = branding['primaryColor']?.toString();
    final parsed = parseBrandHex(primaryColor);
    final onDefaultPalette =
        MobileLocalSettings.colorTheme.value == MobileThemeId.mytaskkingBlue;
    if (parsed != null &&
        onDefaultPalette &&
        MobileLocalSettings.adminPrimaryColor.value != parsed.toARGB32()) {
      // Fire-and-forget; avoid await in provider to reduce rebuild churn.
      MobileLocalSettings.setAdminPrimaryColor(parsed.toARGB32());
    } else if ((primaryColor == null || primaryColor.trim().isEmpty) &&
        onDefaultPalette &&
        MobileLocalSettings.adminPrimaryColor.value != null) {
      MobileLocalSettings.setAdminPrimaryColor(null);
    }
    return OrgBranding(
      name: name.isEmpty ? 'MyTaskKing' : name,
      logoUrl: logoUrl != null && logoUrl.isNotEmpty ? logoUrl : null,
      primaryColor: primaryColor,
    );
  } catch (_) {
    return const OrgBranding();
  }
});
