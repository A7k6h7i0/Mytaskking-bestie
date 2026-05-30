import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state.dart';

const _kMutedKey = 'chat.muted_channels';
const _kMutedUntilKey = 'chat.muted_until_v2';

/// Channel-mute settings. Map of channelId → expiry. `null` value means
/// "forever". A missing key means "not muted". The backend doesn't yet
/// have a per-user mute column, so we keep this on-device only.
final _mutedUntilProvider =
    FutureProvider.autoDispose<Map<String, DateTime?>>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final out = <String, DateTime?>{};
  // Forward-compat: import any old boolean-set entries as "forever".
  final legacy = prefs.getStringList(_kMutedKey) ?? const [];
  for (final id in legacy) { out[id] = null; }
  final raw = prefs.getString(_kMutedUntilKey);
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
    } catch (_) {/* corrupt cache — ignore */}
  }
  return out;
});

bool _isMutedNow(String channelId, Map<String, DateTime?> map) {
  if (!map.containsKey(channelId)) return false;
  final until = map[channelId];
  if (until == null) return true; // forever
  return until.isAfter(DateTime.now());
}

/// Backwards-compat shim — existing build code reads the old boolean set.
/// Computed from the new map so we don't have to touch every callsite.
final _mutedChannelsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final map = await ref.watch(_mutedUntilProvider.future);
  return {
    for (final entry in map.entries)
      if (_isMutedNow(entry.key, map)) entry.key,
  };
});

Future<void> _writeMutedUntil(String channelId, DateTime? until) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kMutedUntilKey);
  final cur = <String, dynamic>{};
  if (raw != null && raw.isNotEmpty) {
    try {
      cur.addAll(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }
  cur[channelId] = until == null ? 'forever' : until.toIso8601String();
  await prefs.setString(_kMutedUntilKey, jsonEncode(cur));
}

Future<void> _writeUnmuted(String channelId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kMutedUntilKey);
  final cur = <String, dynamic>{};
  if (raw != null && raw.isNotEmpty) {
    try {
      cur.addAll(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }
  cur.remove(channelId);
  await prefs.setString(_kMutedUntilKey, jsonEncode(cur));
  // Also drop from the legacy key so the import doesn't re-add it.
  final legacy = (prefs.getStringList(_kMutedKey) ?? const <String>[]).toList();
  legacy.remove(channelId);
  await prefs.setStringList(_kMutedKey, legacy);
}

/// Tracks which channels currently have someone typing, populated from
/// `chat.typing` socket events. Each channel entry self-expires ~4 s after
/// the last keystroke so the "typing…" tile label fades on its own.
final typingChannelsProvider =
    StateNotifierProvider<_TypingChannelsNotifier, Set<String>>((ref) {
  return _TypingChannelsNotifier(ref);
});

class _TypingChannelsNotifier extends StateNotifier<Set<String>> {
  final Ref _ref;
  final Map<String, Timer> _timers = {};
  void Function()? _unsub;
  _TypingChannelsNotifier(this._ref) : super(const {}) {
    final rt = _ref.read(realtimeProvider);
    _unsub = rt.onAny('chat.typing', ([data]) {
      if (data is! Map) return;
      final channelId = data['channelId']?.toString();
      if (channelId == null) return;
      final me = _ref.read(authStoreProvider).user;
      if (data['userId']?.toString() == me?.id) return;
      final typing = data['typing'] == true;
      _timers[channelId]?.cancel();
      if (!typing) {
        if (state.contains(channelId)) {
          state = {...state}..remove(channelId);
        }
        return;
      }
      if (!state.contains(channelId)) state = {...state, channelId};
      _timers[channelId] = Timer(const Duration(seconds: 4), () {
        _timers.remove(channelId);
        if (state.contains(channelId)) {
          state = {...state}..remove(channelId);
        }
      });
    });
  }

  @override
  void dispose() {
    for (final t in _timers.values) { t.cancel(); }
    _unsub?.call();
    super.dispose();
  }
}

/// Chat home — grouped by conversation kind:
///   • Direct messages  (kind = DM)
///   • Group chats      (kind = GROUP, PROJECT, ANNOUNCEMENT — internal)
///   • Client channels  (isClientChannel = true OR kind = CLIENT — external)
///
/// "Channels" in this app are scoped to client ↔ employee threads; internal
/// employee chatter lives in DMs and groups.
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BestieColors.of(context);
    final channels = ref.watch(channelsProvider);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.text,
        title: const Text('Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search people, messages, files',
            onPressed: () => context.go('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Mark all chats read',
            onPressed: () => _markAllRead(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.edit_square),
            tooltip: 'Start a new chat',
            onPressed: () => _newChat(context, ref),
          ),
        ],
      ),
      bottomNavigationBar: SizedBox(
        // Reserve the floating nav footprint so the body stops above it.
        height: 70.0 + MediaQuery.of(context).padding.bottom - 18,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(channelsProvider.future),
        child: channels.when(
          loading: () => const BestieSkeletonList(itemCount: 6),
          error: (e, _) => BestieEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Couldn\'t load chats',
            description: formatApiError(e),
          ),
          data: (items) {
            if (items.isEmpty) {
              return _EmptyState(onNewChat: () => _newChat(context, ref));
            }

            // Bucket by section.
            final dms = <Map<String, dynamic>>[];
            final groups = <Map<String, dynamic>>[];
            final clientChannels = <Map<String, dynamic>>[];

            for (final c in items) {
              final kind = (c['kind'] ?? 'GROUP').toString();
              final isClientChannel = c['isClientChannel'] == true || kind == 'CLIENT';
              if (isClientChannel) {
                clientChannels.add(c);
              } else if (kind == 'DM') {
                dms.add(c);
              } else {
                groups.add(c);
              }
            }

            final me = ref.read(authStoreProvider).user;

            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _Section(
                  title: 'Direct messages',
                  icon: Icons.chat_bubble_outline_rounded,
                  count: dms.length,
                  emptyHint: 'Tap the pencil icon above to start a chat.',
                  children: [
                    for (final c in dms)
                      _ChatTile(channel: c, kind: 'DM', currentUserId: me?.id),
                  ],
                ),
                _Section(
                  title: 'Groups',
                  icon: Icons.groups_outlined,
                  count: groups.length,
                  emptyHint: 'Create a group to chat with multiple teammates at once.',
                  children: [
                    for (final c in groups)
                      _ChatTile(channel: c, kind: 'GROUP', currentUserId: me?.id),
                  ],
                ),
                _Section(
                  title: 'Client channels',
                  icon: Icons.business_center_outlined,
                  count: clientChannels.length,
                  emptyHint: 'External client threads will appear here.',
                  children: [
                    for (final c in clientChannels)
                      _ChatTile(channel: c, kind: 'CLIENT', currentUserId: me?.id),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: BestieTokens.cBrand,
        foregroundColor: Colors.white,
        tooltip: 'New chat',
        onPressed: () => _newChat(context, ref),
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    final api = ref.read(apiProvider);
    final me = ref.read(authStoreProvider).user;
    final channels = ref.read(channelsProvider).asData?.value ?? const [];
    if (me == null) return;
    final unreadIds = channels
        .where((c) {
          final members = (c['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
          final mine = members.firstWhere((m) => m['userId'] == me.id, orElse: () => const {});
          return mine.isNotEmpty && mine['lastReadAt'] == null;
        })
        .map((c) => c['id'] as String)
        .toList();
    if (unreadIds.isEmpty) {
      bestieToast(context, 'Already all read', kind: BestieToastKind.info);
      return;
    }
    // Sequential, not parallel — firing 30 concurrent POSTs against the
    // mark-read endpoint trips the global rate limiter (429). One at a
    // time with a tiny pause is still nearly instant for normal inboxes.
    for (final id in unreadIds) {
      try { await api.markChannelRead(id); } catch (_) {}
    }
    ref.invalidate(channelsProvider);
    if (context.mounted) {
      bestieToast(context, 'Marked ${unreadIds.length} chat${unreadIds.length == 1 ? '' : 's'} read',
          kind: BestieToastKind.success);
    }
  }

  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    final api = ref.read(apiProvider);
    final me = ref.read(authStoreProvider).user;
    final channel = await showBestieNewChatSheet(
      context,
      currentUserId: me?.id,
      fetchEmployees: (q) => api.listEmployees(q: q.trim().isEmpty ? null : q.trim()),
      onStartDm: (otherId) async {
        final ch = await api.createChannel(kind: 'DM', memberIds: [otherId]);
        return ch;
      },
      onStartGroup: (name, memberIds) async {
        final ch = await api.createChannel(kind: 'GROUP', name: name, memberIds: memberIds);
        return ch;
      },
    );
    if (channel != null && context.mounted) {
      ref.invalidate(channelsProvider);
      final id = channel['id']?.toString();
      if (id != null) context.go('/chat/$id');
    }
  }
}

// ---------------------------------------------------------------------------
// section header + chat tile
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;
  final String emptyHint;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.count,
    required this.emptyHint,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            Icon(icon, size: 14, color: c.textMuted),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: BestieTokens.fwBold,
                color: c.textMuted,
                letterSpacing: BestieTokens.lsEyebrow,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(BestieTokens.rPill),
                ),
                child: Text('$count', style: TextStyle(
                  fontSize: 10, color: c.textSoft, fontWeight: BestieTokens.fwBold,
                )),
              ),
            ],
          ]),
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Text(emptyHint, style: TextStyle(color: c.textFaint, fontSize: 12)),
          )
        else
          ...children,
      ],
    );
  }
}

class _ChatTile extends ConsumerWidget {
  final Map<String, dynamic> channel;
  final String kind;
  final String? currentUserId;

  const _ChatTile({required this.channel, required this.kind, required this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final members = (channel['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    // Unread is driven by the backend's unreadCount, which already EXCLUDES
    // the current user's own messages — so sending a message yourself never
    // lights up an unread badge. (The old `lastReadAt == null` check did,
    // which made your own "Hii" look like an incoming unread message.)
    final unreadCount = (channel['unreadCount'] as num?)?.toInt() ?? 0;
    final unread = unreadCount > 0;
    final isClient = channel['isClientChannel'] == true || kind == 'CLIENT';

    // Build display name. For DMs prefer the *other* member's name.
    String displayName = (channel['name'] ?? '—').toString();
    String? avatarUrl;
    if (kind == 'DM') {
      final other = members.firstWhere(
        (m) => m['userId'] != currentUserId,
        orElse: () => const {},
      );
      final user = other['user'] as Map<String, dynamic>?;
      if (user != null) {
        displayName = (user['name'] ?? displayName).toString();
        avatarUrl = user['avatarUrl']?.toString();
      }
    }

    // Prefer the last message body as the preview line — what WhatsApp /
    // Telegram show. Falls back to the member count.
    final lastMessage = (channel['lastMessage'] as Map?)?.cast<String, dynamic>();
    final lastBody = (lastMessage?['body'] ?? '').toString();
    final lastKind = (lastMessage?['kind'] ?? 'TEXT').toString();
    final hasLast = lastMessage != null;
    String previewLine;
    if (hasLast) {
      final base = switch (lastKind) {
        'IMAGE'      => '📷 Photo',
        'FILE'       => '📎 File',
        'VOICE_NOTE' => '🎙️ Voice note',
        'CALL_EVENT' => lastBody.isEmpty ? '📞 Call' : lastBody,
        'SYSTEM'     => lastBody,
        _            => lastBody.isEmpty ? '' : lastBody,
      };
      // WhatsApp-style sender prefix: "You: " for your own last message, and
      // "Name: " for someone else's in a group. DMs from the other person show
      // no prefix. System/call events are shown as-is.
      final lastAuthorId = lastMessage['authorId']?.toString();
      final author = (lastMessage['author'] as Map?)?.cast<String, dynamic>();
      final isMine = lastAuthorId != null && lastAuthorId == currentUserId;
      if (lastKind == 'SYSTEM' || lastKind == 'CALL_EVENT' || base.isEmpty) {
        previewLine = base;
      } else if (isMine) {
        previewLine = 'You: $base';
      } else if (kind != 'DM') {
        final n = (author?['name'] ?? '').toString().trim();
        final first = n.isEmpty ? '' : n.split(' ').first;
        previewLine = first.isEmpty ? base : '$first: $base';
      } else {
        previewLine = base;
      }
    } else {
      previewLine = switch (kind) {
        'DM'     => 'Direct message',
        'CLIENT' => '${members.length} member${members.length == 1 ? '' : 's'} · client',
        _        => '${members.length} member${members.length == 1 ? '' : 's'}',
      };
    }
    final timeLine = BestieTime.shortRelative(
      lastMessage?['createdAt']?.toString() ?? channel['updatedAt']?.toString(),
    );
    // Live "typing…" overrides the preview line whenever someone in this
    // channel is mid-keystroke (driven by typingChannelsProvider).
    final isTyping =
        ref.watch(typingChannelsProvider).contains(channel['id']?.toString());

    final muted = ref.watch(_mutedChannelsProvider).asData?.value
            .contains(channel['id'] as String) ?? false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go('/chat/${channel['id']}'),
        onLongPress: () => _showTileMenu(context, ref, muted),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            kind == 'DM'
                ? BestieAvatar(
                    name: displayName,
                    imageUrl: avatarUrl,
                    isClient: isClient,
                    size: 44,
                  )
                : Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: isClient ? c.clientSoft : c.brandSoft,
                      borderRadius: BorderRadius.circular(BestieTokens.rMd),
                    ),
                    child: Icon(
                      kind == 'CLIENT' ? Icons.business_center_outlined : Icons.groups_outlined,
                      color: isClient ? c.client : c.brandStrong,
                      size: 22,
                    ),
                  ),
            const SizedBox(width: 12),
            // Left block: name (top) + preview (bottom).
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Flexible(
                      child: BestieUserName(
                        name: displayName,
                        isClient: isClient,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: unread ? BestieTokens.fwBold : BestieTokens.fwSemibold,
                          color: c.text,
                          letterSpacing: BestieTokens.lsSnug,
                        ),
                      ),
                    ),
                    if (muted) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.volume_off_rounded, size: 13, color: c.textMuted),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  isTyping
                      ? Text(
                          'typing…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.brand,
                            fontSize: 13,
                            fontWeight: BestieTokens.fwSemibold,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : Text(
                          previewLine.isEmpty ? '—' : previewLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unread ? c.text : c.textMuted,
                            fontSize: 13,
                            fontWeight: unread
                                ? BestieTokens.fwSemibold
                                : BestieTokens.fwRegular,
                          ),
                        ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right block: timestamp pinned to the TOP, unread count badge
            // below it (WhatsApp layout — the time no longer floats in the
            // vertical middle of the row).
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (timeLine.isNotEmpty)
                  Text(
                    timeLine,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: unread
                          ? BestieTokens.fwSemibold
                          : BestieTokens.fwMedium,
                      color: unread ? c.brand : c.textFaint,
                    ),
                  ),
                const SizedBox(height: 6),
                if (unread)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: muted ? c.textMuted : c.brand,
                      borderRadius: BorderRadius.circular(BestieTokens.rPill),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: BestieTokens.fwBold,
                        height: 1.3,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 18),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  /// Bottom-sheet menu — mute/unmute + mark read. Stored locally because the
  /// backend doesn't have per-user channel-mute state yet; this still works
  /// for hiding push noise on this device.
  void _showTileMenu(BuildContext context, WidgetRef ref, bool currentlyMuted) {
    final c = BestieColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: c.borderStrong, borderRadius: BorderRadius.circular(BestieTokens.rPill),
            ),
          ),
          ListTile(
            leading: Icon(
                currentlyMuted
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                color: c.textSoft),
            title: Text(
                currentlyMuted ? 'Unmute notifications' : 'Mute notifications',
                style: TextStyle(color: c.text)),
            onTap: () async {
              Navigator.pop(ctx);
              final channelId = channel['id'] as String;
              if (currentlyMuted) {
                await _writeUnmuted(channelId);
                ref.invalidate(_mutedUntilProvider);
                ref.invalidate(_mutedChannelsProvider);
                return;
              }
              if (!context.mounted) return;
              await _pickMuteDuration(context, ref, channelId);
            },
          ),
          ListTile(
            leading: Icon(Icons.done_all_rounded, color: c.textSoft),
            title: Text('Mark as read', style: TextStyle(color: c.text)),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(apiProvider).markChannelRead(channel['id'] as String);
                ref.invalidate(channelsProvider);
              } catch (e) {
                if (context.mounted) bestieToast(context, 'Could not mark read',
                    body: formatApiError(e), kind: BestieToastKind.error);
              }
            },
          ),
        ]),
      ),
    );
  }

  /// Mute duration picker — "until 8 hours / tomorrow / a week / forever".
  Future<void> _pickMuteDuration(
      BuildContext context, WidgetRef ref, String channelId) async {
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
            width: 40, height: 4,
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
                final until = opt.$2 == null
                    ? null
                    : DateTime.now().add(opt.$2!);
                await _writeMutedUntil(channelId, until);
                ref.invalidate(_mutedUntilProvider);
                ref.invalidate(_mutedChannelsProvider);
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
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onNewChat;
  const _EmptyState({required this.onNewChat});

  @override
  Widget build(BuildContext context) {
    return BestieEmptyState(
      icon: Icons.chat_bubble_outline_rounded,
      title: 'No chats yet',
      description: 'Start a direct message with a teammate or create a group.',
      action: FilledButton.icon(
        onPressed: onNewChat,
        style: FilledButton.styleFrom(
          backgroundColor: BestieTokens.cBrand,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: const Text('Start a chat'),
      ),
    );
  }
}
