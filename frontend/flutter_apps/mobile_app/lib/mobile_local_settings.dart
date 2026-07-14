import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;
import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_theme_palettes.dart';

const _kThemeMode = 'mobile.theme.mode';
const _kColorTheme = 'mobile.theme.palette';
const _kOverridesPrefix = 'mobile.theme.overrides.';
const _kAdminPrimary = 'mobile.theme.admin_primary';

class MobileLocalSettings {
  MobileLocalSettings._();

  static final ValueNotifier<core.ThemeMode> themeMode =
      ValueNotifier<core.ThemeMode>(core.ThemeMode.system);
  static final ValueNotifier<MobileThemeId> colorTheme =
      ValueNotifier<MobileThemeId>(MobileThemeId.mytaskkingBlue);
  static final ValueNotifier<Map<MobileThemeId, Map<String, int>>>
      themeColorOverrides =
      ValueNotifier<Map<MobileThemeId, Map<String, int>>>({});
  /// Admin branding primaryColor (ARGB int). Null = unused.
  static final ValueNotifier<int?> adminPrimaryColor = ValueNotifier<int?>(null);

  /// Bumped on any appearance change so [MaterialApp] can force a full rebuild
  /// (go_router routes otherwise keep stale theme-dependent subtrees).
  static final ValueNotifier<int> themeEpoch = ValueNotifier<int>(0);

  static void _markThemeChanged() {
    themeEpoch.value++;
  }

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

    final overrides = <MobileThemeId, Map<String, int>>{};
    for (final id in MobileThemeId.values) {
      final raw = prefs.getString('$_kOverridesPrefix${id.storageKey}');
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          overrides[id] = {
            for (final e in decoded.entries)
              e.key.toString(): (e.value as num).toInt(),
          };
        }
      } catch (_) {}
    }
    themeColorOverrides.value = overrides;

    final adminRaw = prefs.getInt(_kAdminPrimary);
    adminPrimaryColor.value = adminRaw;
  }

  static Map<String, int> overridesFor(MobileThemeId id) =>
      Map<String, int>.from(themeColorOverrides.value[id] ?? const {});

  static Future<void> setThemeMode(core.ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = switch (mode) {
      core.ThemeMode.light => 'light',
      core.ThemeMode.dark => 'dark',
      core.ThemeMode.system => 'system',
    };
    await prefs.setString(_kThemeMode, raw);
    themeMode.value = mode;
    _markThemeChanged();
  }

  static Future<void> setColorTheme(MobileThemeId id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kColorTheme, id.storageKey);
    colorTheme.value = id;
    _markThemeChanged();
  }

  static Future<void> setThemeColorOverrides(
    MobileThemeId id,
    Map<String, int> overrides,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final next = Map<MobileThemeId, Map<String, int>>.from(
      themeColorOverrides.value,
    );
    if (overrides.isEmpty) {
      next.remove(id);
      await prefs.remove('$_kOverridesPrefix${id.storageKey}');
    } else {
      next[id] = Map<String, int>.from(overrides);
      await prefs.setString(
        '$_kOverridesPrefix${id.storageKey}',
        jsonEncode(overrides),
      );
    }
    themeColorOverrides.value = next;
    _markThemeChanged();
  }

  static Future<void> resetThemeColorOverrides(MobileThemeId id) async {
    await setThemeColorOverrides(id, const {});
  }

  static Future<void> setAdminPrimaryColor(int? argb) async {
    final prefs = await SharedPreferences.getInstance();
    if (argb == null) {
      await prefs.remove(_kAdminPrimary);
    } else {
      await prefs.setInt(_kAdminPrimary, argb);
    }
    adminPrimaryColor.value = argb;
    _markThemeChanged();
  }
}
