import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String chatClearedAtPrefsKey(String channelId) => 'chat.clearedAt.$channelId';

/// When the local user last tapped "Clear chat" — messages at or before this
/// time are hidden on this device only (WhatsApp-style).
final chatClearedAtProvider =
    FutureProvider.family.autoDispose<DateTime?, String>(
  (ref, channelId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(chatClearedAtPrefsKey(channelId));
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  },
);

Future<void> markChatCleared(SharedPreferences prefs, String channelId) async {
  await prefs.setString(
    chatClearedAtPrefsKey(channelId),
    DateTime.now().toUtc().toIso8601String(),
  );
}

DateTime? messageCreatedUtc(Map<String, dynamic> message) {
  final iso = message['createdAt']?.toString();
  if (iso == null || iso.isEmpty) return null;
  var dt = DateTime.tryParse(iso);
  if (dt == null) return null;
  final hasTz =
      iso.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(iso);
  if (!dt.isUtc && !hasTz) {
    dt = DateTime.utc(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
      dt.microsecond,
    );
  }
  return dt.toUtc();
}

/// True when the message should still appear after a local clear-chat action.
bool isMessageVisibleAfterClear(
  Map<String, dynamic> message,
  DateTime? clearedAt,
) {
  if (clearedAt == null) return true;
  final created = messageCreatedUtc(message);
  if (created == null) return true;
  return created.isAfter(clearedAt);
}

bool isLastMessageCleared(
  Map<String, dynamic>? lastMessage,
  DateTime? clearedAt,
) {
  if (lastMessage == null || clearedAt == null) return false;
  return !isMessageVisibleAfterClear(lastMessage, clearedAt);
}
