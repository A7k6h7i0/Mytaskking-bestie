import 'package:flutter/foundation.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_theme_palettes.dart';

const _kThemeMode = 'mobile.theme.mode';
const _kColorTheme = 'mobile.theme.palette';

class MobileLocalSettings {
  MobileLocalSettings._();

  static final ValueNotifier<core.ThemeMode> themeMode =
      ValueNotifier<core.ThemeMode>(core.ThemeMode.system);
  static final ValueNotifier<MobileThemeId> colorTheme =
      ValueNotifier<MobileThemeId>(MobileThemeId.mytaskkingBlue);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeRaw = prefs.getString(_kThemeMode);
    themeMode.value = switch (modeRaw) {
      'light' => core.ThemeMode.light,
      'dark' => core.ThemeMode.dark,
      _ => core.ThemeMode.system,
    };
    colorTheme.value =
        MobileThemeId.fromStorage(prefs.getString(_kColorTheme));
  }

  static Future<void> setThemeMode(core.ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = switch (mode) {
      core.ThemeMode.light => 'light',
      core.ThemeMode.dark => 'dark',
      core.ThemeMode.system => 'system',
    };
    await prefs.setString(_kThemeMode, raw);
    themeMode.value = mode;
  }

  static Future<void> setColorTheme(MobileThemeId id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kColorTheme, id.storageKey);
    colorTheme.value = id;
  }
}
