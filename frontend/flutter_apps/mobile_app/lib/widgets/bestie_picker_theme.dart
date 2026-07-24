import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

/// Wraps Material date/time pickers so dial, background, and labels follow the
/// app light/dark palette (fixes unreadable time text in schedule dialogs).
ThemeData _bestiePickerTheme(BuildContext context) {
  final c = BestieColors.of(context);
  final base = Theme.of(context);
  final scheme = ColorScheme(
    brightness: c.isDark ? Brightness.dark : Brightness.light,
    primary: c.brand,
    onPrimary: Colors.white,
    secondary: c.accent,
    onSecondary: Colors.white,
    error: c.danger,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.text,
  );
  return base.copyWith(
    colorScheme: scheme,
    dialogTheme: DialogThemeData(backgroundColor: c.surface),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: c.surface,
      headerBackgroundColor: c.brand,
      headerForegroundColor: Colors.white,
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return c.text;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return c.brand;
        return Colors.transparent;
      }),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return c.text;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return c.brand;
        return Colors.transparent;
      }),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: c.surface,
      hourMinuteColor: c.surface2,
      hourMinuteTextColor: c.text,
      hourMinuteTextStyle: TextStyle(
        color: c.text,
        fontWeight: FontWeight.w600,
        fontSize: 48,
      ),
      dayPeriodColor: c.surface2,
      dayPeriodTextColor: c.text,
      dayPeriodTextStyle: TextStyle(color: c.text, fontWeight: FontWeight.w600),
      dialBackgroundColor: c.surface2,
      dialHandColor: c.brand,
      dialTextColor: c.text,
      dialTextStyle: TextStyle(color: c.text, fontWeight: FontWeight.w500),
      entryModeIconColor: c.textMuted,
      helpTextStyle: TextStyle(color: c.textMuted, fontSize: 12),
      hourMinuteShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestieTokens.rSm),
        side: BorderSide(color: c.border),
      ),
      dayPeriodShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestieTokens.rSm),
        side: BorderSide(color: c.border),
      ),
    ),
  );
}

Widget _bestiePickerBuilder(BuildContext context, Widget? child) {
  return Theme(
    data: _bestiePickerTheme(context),
    child: child ?? const SizedBox.shrink(),
  );
}

/// Date then time — returns local [DateTime], or null if cancelled / in the past.
Future<({DateTime? value, bool cancelled})> bestiePickScheduledDateTime(
  BuildContext context, {
  required DateTime initial,
  required DateTime firstDate,
  required DateTime lastDate,
}) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: initial.isBefore(firstDate) ? firstDate : initial,
    firstDate: firstDate,
    lastDate: lastDate,
    builder: _bestiePickerBuilder,
  );
  if (date == null) return (value: null, cancelled: true);
  if (!context.mounted) return (value: null, cancelled: true);
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    builder: _bestiePickerBuilder,
  );
  if (time == null) return (value: null, cancelled: true);
  final picked =
      DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (picked.isBefore(now)) return (value: null, cancelled: false);
  return (value: picked, cancelled: false);
}

/// Theme-aware date-only picker. Returns null if cancelled.
Future<DateTime?> bestiePickDate(
  BuildContext context, {
  DateTime? initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final now = DateTime.now();
  final start = firstDate ?? DateTime(now.year - 5);
  final end = lastDate ?? DateTime(now.year + 5);
  var seed = initial ?? now;
  if (seed.isBefore(start)) seed = start;
  if (seed.isAfter(end)) seed = end;
  return showDatePicker(
    context: context,
    useRootNavigator: true,
    initialDate: seed,
    firstDate: start,
    lastDate: end,
    builder: _bestiePickerBuilder,
  );
}
