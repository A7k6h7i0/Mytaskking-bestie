import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAutoLogoutEnabled = 'desktop.auto_logout.enabled';
const _kAutoLogoutMinutes = 'desktop.auto_logout.minutes';

@immutable
class DesktopAutoLogoutSettings {
  const DesktopAutoLogoutSettings({
    required this.enabled,
    required this.minutesSinceMidnight,
  });

  static const fallback = DesktopAutoLogoutSettings(
    enabled: true,
    minutesSinceMidnight: 18 * 60,
  );

  final bool enabled;
  final int minutesSinceMidnight;

  int get hour => (minutesSinceMidnight ~/ 60).clamp(0, 23);
  int get minute => (minutesSinceMidnight % 60).clamp(0, 59);

  String get label {
    final rawHour = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final mm = minute.toString().padLeft(2, '0');
    return '$rawHour:$mm $suffix';
  }

  DesktopAutoLogoutSettings copyWith({
    bool? enabled,
    int? minutesSinceMidnight,
  }) {
    return DesktopAutoLogoutSettings(
      enabled: enabled ?? this.enabled,
      minutesSinceMidnight: minutesSinceMidnight ?? this.minutesSinceMidnight,
    );
  }
}

class DesktopLocalSettings {
  DesktopLocalSettings._();

  static final ValueNotifier<DesktopAutoLogoutSettings> autoLogout =
      ValueNotifier<DesktopAutoLogoutSettings>(
    DesktopAutoLogoutSettings.fallback,
  );

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kAutoLogoutEnabled) ?? true;
    final minutes = prefs.getInt(_kAutoLogoutMinutes) ?? (18 * 60);
    autoLogout.value = DesktopAutoLogoutSettings(
      enabled: enabled,
      minutesSinceMidnight: minutes.clamp(0, 1439),
    );
  }

  static Future<void> saveAutoLogout(DesktopAutoLogoutSettings value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoLogoutEnabled, value.enabled);
    await prefs.setInt(
      _kAutoLogoutMinutes,
      value.minutesSinceMidnight.clamp(0, 1439),
    );
    autoLogout.value = value.copyWith(
      minutesSinceMidnight: value.minutesSinceMidnight.clamp(0, 1439),
    );
  }
}
