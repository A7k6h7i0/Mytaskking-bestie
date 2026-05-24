import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state.dart';

const _kMutedKey = 'chat.muted_channels';

/// Channel ids the user has muted locally. The backend doesn't yet have a
/// per-user mute column, so we hide push toast + show a muted indicator on
/// this device only. Refresh by invalidating after writes.
final _mutedChannelsProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getStringList(_kMutedKey) ?? const []).toSet();
});

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
        height: 70.0 + MediaQuery.of(context).padding.bottom + 4,
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
    final myMember = members.firstWhere(
      (m) => m['userId'] == currentUserId,
      orElse: () => const {},
    );
    final unread = myMember['lastReadAt'] == null;
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
      previewLine = switch (lastKind) {
        'IMAGE'      => '📷 Photo',
        'FILE'       => '📎 File',
        'VOICE_NOTE' => '🎙️ Voice note',
        'CALL_EVENT' => lastBody.isEmpty ? '📞 Call' : lastBody,
        'SYSTEM'     => lastBody,
        _            => lastBody.isEmpty ? '' : lastBody,
      };
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
                    const Spacer(),
                    if (timeLine.isNotEmpty)
                      Text(
                        timeLine,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: unread ? BestieTokens.fwSemibold : BestieTokens.fwMedium,
                          color: unread ? c.brand : c.textFaint,
                        ),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    Expanded(
                      child: Text(
                        previewLine.isEmpty ? '—' : previewLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: unread ? c.text : c.textMuted,
                          fontSize: 13,
                          fontWeight: unread ? BestieTokens.fwSemibold : BestieTokens.fwRegular,
                        ),
                      ),
                    ),
                    if (unread)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        width: 9, height: 9,
                        decoration: BoxDecoration(
                          color: muted ? c.textMuted : c.brand,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ]),
                ],
              ),
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
            leading: Icon(currentlyMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: c.textSoft),
            title: Text(currentlyMuted ? 'Unmute notifications' : 'Mute notifications',
                style: TextStyle(color: c.text)),
            onTap: () async {
              Navigator.pop(ctx);
              final prefs = await SharedPreferences.getInstance();
              final ids = prefs.getStringList(_kMutedKey)?.toSet() ?? <String>{};
              currentlyMuted
                  ? ids.remove(channel['id'])
                  : ids.add(channel['id'] as String);
              await prefs.setStringList(_kMutedKey, ids.toList());
              ref.invalidate(_mutedChannelsProvider);
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
