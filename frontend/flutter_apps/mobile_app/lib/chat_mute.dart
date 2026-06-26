import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kChatMutedKey = 'chat.muted_channels';
const kChatMutedUntilKey = 'chat.muted_until_v2';

/// Channel-mute settings. Map of channelId → expiry. `null` value means
/// "forever". A missing key means "not muted". Stored on-device only.
final chatMutedUntilProvider =
    FutureProvider.autoDispose<Map<String, DateTime?>>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final out = <String, DateTime?>{};
  final legacy = prefs.getStringList(kChatMutedKey) ?? const [];
  for (final id in legacy) {
    out[id] = null;
  }
  final raw = prefs.getString(kChatMutedUntilKey);
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((k, v) {
        if (v == null || v == 'forever') {
          out[k] = null;
        } else {
          out[k] = DateTime.tryParse(v.toString());
        }
      });
    } catch (_) {}
  }
  return out;
});

final chatMutedChannelsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final map = await ref.watch(chatMutedUntilProvider.future);
  return {
    for (final entry in map.entries)
      if (isChatMutedNow(entry.key, map)) entry.key,
  };
});

bool isChatMutedNow(String channelId, Map<String, DateTime?> map) {
  if (!map.containsKey(channelId)) return false;
  final until = map[channelId];
  if (until == null) return true;
  return until.isAfter(DateTime.now());
}

Future<void> writeChatMutedUntil(String channelId, DateTime? until) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kChatMutedUntilKey);
  final cur = <String, dynamic>{};
  if (raw != null && raw.isNotEmpty) {
    try {
      cur.addAll(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }
  cur[channelId] = until == null ? 'forever' : until.toIso8601String();
  await prefs.setString(kChatMutedUntilKey, jsonEncode(cur));
}

Future<void> writeChatUnmuted(String channelId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kChatMutedUntilKey);
  final cur = <String, dynamic>{};
  if (raw != null && raw.isNotEmpty) {
    try {
      cur.addAll(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }
  cur.remove(channelId);
  await prefs.setString(kChatMutedUntilKey, jsonEncode(cur));
  final legacy = (prefs.getStringList(kChatMutedKey) ?? const <String>[]).toList();
  legacy.remove(channelId);
  await prefs.setStringList(kChatMutedKey, legacy);
}

Future<void> showChatMuteDurationPicker(
  BuildContext context,
  WidgetRef ref,
  String channelId,
) async {
  final c = BestieColors.of(context);
  final options = <(String, Duration?)>[
    ('8 hours', const Duration(hours: 8)),
    ('Until tomorrow', const Duration(days: 1)),
    ('A week', const Duration(days: 7)),
    ('Forever', null),
  ];
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: c.borderStrong,
            borderRadius: BorderRadius.circular(BestieTokens.rPill),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(children: [
            Icon(Icons.volume_off_rounded, size: 18, color: c.textSoft),
            const SizedBox(width: 8),
            Text('Mute notifications for…',
                style: TextStyle(
                    color: c.text,
                    fontWeight: BestieTokens.fwSemibold,
                    fontSize: 15)),
          ]),
        ),
        for (final opt in options)
          ListTile(
            title: Text(opt.$1, style: TextStyle(color: c.text)),
            trailing: Icon(Icons.chevron_right_rounded, color: c.textFaint),
            onTap: () async {
              Navigator.pop(ctx);
              final until =
                  opt.$2 == null ? null : DateTime.now().add(opt.$2!);
              await writeChatMutedUntil(channelId, until);
              ref.invalidate(chatMutedUntilProvider);
              ref.invalidate(chatMutedChannelsProvider);
              if (context.mounted) {
                bestieToast(context, 'Muted for ${opt.$1.toLowerCase()}',
                    kind: BestieToastKind.success);
              }
            },
          ),
      ]),
    ),
  );
}
