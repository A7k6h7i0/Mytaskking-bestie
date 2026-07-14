import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mobile_local_settings.dart';
import 'mobile_theme_palettes.dart';

/// Riverpod mirror of [MobileLocalSettings.colorTheme] so [MaterialApp]
/// rebuilds when the user picks a color palette.
final mobileColorThemeProvider = StateProvider<MobileThemeId>(
  (ref) => MobileLocalSettings.colorTheme.value,
);
