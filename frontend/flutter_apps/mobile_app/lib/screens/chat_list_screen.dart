import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../call_event_text.dart';
import '../chat_clear.dart';
import '../chat_mute.dart';
import '../state.dart';
import 'call_screen.dart';
import '../widgets/profile_avatar_viewer.dart';

/// WhatsApp-style recency — pinned first, then most recent activity.
DateTime _channelActivityTime(Map<String, dynamic> channel) {
  final lastMsg = (channel['lastMessage'] as Map?)?.cast<String, dynamic>();
  final fromMessage = DateTime.tryParse(lastMsg?['createdAt']?.toString() ?? '');
  if (fromMessage != null) return fromMessage;
  return DateTime.tryParse(channel['updatedAt']?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

void _sortChannelsByRecent(List<Map<String, dynamic>> channels) {
  channels.sort((a, b) {
    final aPinned = a['pinned'] == true;
    final bPinned = b['pinned'] == true;
    if (aPinned != bPinned) return aPinned ? -1 : 1;
    return _channelActivityTime(b).compareTo(_channelActivityTime(a));
  });
}

bool _canCallUser(WidgetRef ref, Map<String, dynamic>? user) {
  if (user == null) return false;
  final me = ref.read(authStoreProvider).user;
  final viewerIsAdmin = me?.role == 'ADMIN' || me?.role == 'SUPER_ADMIN';
  if (viewerIsAdmin) return true;
  final role = user['role']?.toString();
  return role != 'ADMIN' && role != 'SUPER_ADMIN';
}

/// Other participant in a DM — skips self, prefers nested `user` payload.
Map<String, dynamic>? _resolveDmPeer(
  List<Map<String, dynamic>> members,
  String? meId,
) {
  for (final member in members) {
    if (meId != null && member['userId']?.toString() == meId) continue;
    final user = (member['user'] as Map?)?.cast<String, dynamic>();
    if (user != null) return user;
  }
  return null;
}

String _displayNameForUser(Map<String, dynamic>? user, {String fallback = ''}) {
  if (user == null) return fallback;
  final name = (user['name'] ?? '').toString().trim();
  if (name.isNotEmpty && name != '—') return name;
  final loginId = (user['userId'] ?? '').toString().trim();
  if (loginId.isNotEmpty) return loginId;
  return fallback;
}

bool _isRenderableDm(
  Map<String, dynamic> channel,
  String? meId,
) {
  final members =
      (channel['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final peer = _resolveDmPeer(members, meId);
  return peer != null && _displayNameForUser(peer).isNotEmpty;
}

Widget _chatListCallButton({
  required BestieColors colors,
  required IconData icon,
  required String tooltip,
  required VoidCallback onPressed,
}) {
  return Material(
    color: colors.textFaint.withValues(alpha: 0.32),
    shape: CircleBorder(
      side: BorderSide(color: colors.borderSoft, width: 1),
    ),
    child: IconButton(
      icon: Icon(icon, color: colors.textMuted, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: onPressed,
    ),
  );
}

Future<void> _startCallFromList(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> user,
  required String mode,
  String? channelId,
}) async {
  if (!_canCallUser(ref, user)) {
    if (context.mounted) {
      bestieToast(
        context,
        'Calling unavailable',
        body: 'Only admins can start calls with administrators.',
        kind: BestieToastKind.warning,
      );
    }
    return;
  }
  try {
    await CallSession.prepareForNewCall();
    final res = await ref.read(apiProvider).initiateCall(
          participantIds: [user['id'].toString()],
          kind: 'ONE_TO_ONE',
          channelId: channelId,
          mode: mode == 'voice' ? 'VOICE' : 'VIDEO',
        );
    final presence = (res['targetPresence'] as Map?)?.cast<String, dynamic>();
    if (presence != null &&
        !(presence['status'] == 'ON_CALL' && res['waiting'] == true)) {
      final custom = (presence['customStatus'] ?? '').toString();
      if (presence['status'] == 'ON_CALL' ||
          custom.toLowerCase().contains('another call')) {
        try {
          final tts = FlutterTts();
          await tts.setSpeechRate(0.36);
          await tts.speak(
              '${user['name']} is busy with another call. Please call again later.');
        } catch (_) {}
      }
      if (context.mounted) {
        bestieToast(context, '${user['name']} is unavailable',
            body: (presence['customStatus'] ?? presence['status']).toString(),
            kind: BestieToastKind.warning);
      }
      return;
    }
    final id = (res['call'] as Map?)?['id']?.toString();
    if (presence?['status'] == 'ON_CALL' && res['waiting'] == true) {
      try {
        final tts = FlutterTts();
        await tts.setSpeechRate(0.36);
        await tts.speak(
            '${user['name']} is busy on another call. Waiting for them to respond.');
      } catch (_) {}
      if (context.mounted) {
        bestieToast(context, '${user['name']} is busy',
            body: 'Waiting for them to accept and add you to their call.',
            kind: BestieToastKind.info);
      }
      return;
    }
    if (id != null && context.mounted) {
      context.go('/call/$id?mode=$mode');
    }
  } catch (e) {
    if (context.mounted) {
      bestieToast(context, 'Could not start call',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }
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
    for (final t in _timers.values) {
      t.cancel();
    }
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More options',
            onSelected: (value) {
              switch (value) {
                case 'search':
                  context.go('/search');
                  break;
                case 'mark_read':
                  _markAllRead(context, ref);
                  break;
                case 'new_chat':
                  _newChat(context, ref);
                  break;
                case 'new_group':
                  _newChat(context, ref, initialTabIndex: 1);
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'search',
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: colors.text, size: 22),
                    const SizedBox(width: 12),
                    const Text('Search'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'mark_read',
                child: Row(
                  children: [
                    Icon(Icons.done_all_rounded, color: colors.text, size: 22),
                    const SizedBox(width: 12),
                    const Text('Mark all chats read'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'new_chat',
                child: Row(
                  children: [
                    Icon(Icons.edit_square, color: colors.text, size: 22),
                    const SizedBox(width: 12),
                    const Text('New chat'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'new_group',
                child: Row(
                  children: [
                    Icon(Icons.group_add_outlined, color: colors.text, size: 22),
                    const SizedBox(width: 12),
                    const Text('New group'),
                  ],
                ),
              ),
            ],
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
            final me = ref.read(authStoreProvider).user;

            for (final c in items) {
              final kind = (c['kind'] ?? 'GROUP').toString();
              final isClientChannel =
                  c['isClientChannel'] == true || kind == 'CLIENT';
              if (isClientChannel) {
                clientChannels.add(c);
              } else if (kind == 'DM') {
                if (_isRenderableDm(c, me?.id)) dms.add(c);
              } else {
                groups.add(c);
              }
            }

            // Re-sort each section by last activity. The API sorts globally,
            // but bucketing by kind breaks WhatsApp-style recency within DMs.
            _sortChannelsByRecent(dms);
            _sortChannelsByRecent(groups);
            _sortChannelsByRecent(clientChannels);

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
                  emptyHint:
                      'Create a group to chat with multiple teammates at once.',
                  children: [
                    for (final c in groups)
                      _ChatTile(
                          channel: c, kind: 'GROUP', currentUserId: me?.id),
                  ],
                ),
                _Section(
                  title: 'Client channels',
                  icon: Icons.business_center_outlined,
                  count: clientChannels.length,
                  emptyHint: 'External client threads will appear here.',
                  children: [
                    for (final c in clientChannels)
                      _ChatTile(
                          channel: c, kind: 'CLIENT', currentUserId: me?.id),
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
          final members =
              (c['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
          final mine = members.firstWhere((m) => m['userId'] == me.id,
              orElse: () => const {});
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
      try {
        await api.markChannelRead(id);
      } catch (_) {}
    }
    ref.invalidate(channelsProvider);
    if (context.mounted) {
      bestieToast(context,
          'Marked ${unreadIds.length} chat${unreadIds.length == 1 ? '' : 's'} read',
          kind: BestieToastKind.success);
    }
  }

  Future<void> _newChat(
    BuildContext context,
    WidgetRef ref, {
    int initialTabIndex = 0,
  }) async {
    final api = ref.read(apiProvider);
    final me = ref.read(authStoreProvider).user;
    final channel = await showBestieNewChatSheet(
      context,
      currentUserId: me?.id,
      initialTabIndex: initialTabIndex,
      fetchEmployees: (q) =>
          api.listEmployees(q: q.trim().isEmpty ? null : q.trim()),
      onStartDm: (otherId) async {
        final ch = await api.createChannel(kind: 'DM', memberIds: [otherId]);
        return ch;
      },
      onStartGroup: (name, memberIds) async {
        final ch = await api.createChannel(
            kind: 'GROUP', name: name, memberIds: memberIds);
        return ch;
      },
      onStartCall: (user, mode) async {
        final targetRole = user['role']?.toString();
        final viewerIsAdmin = me?.role == 'ADMIN' || me?.role == 'SUPER_ADMIN';
        if (!viewerIsAdmin &&
            (targetRole == 'ADMIN' || targetRole == 'SUPER_ADMIN')) {
          if (context.mounted) {
            bestieToast(
              context,
              'Calling unavailable',
              body: 'Only admins can start calls with administrators.',
              kind: BestieToastKind.warning,
            );
          }
          return;
        }
        await CallSession.prepareForNewCall();
        final res = await api.initiateCall(
          participantIds: [user['id'].toString()],
          kind: 'ONE_TO_ONE',
          mode: mode == 'voice' ? 'VOICE' : 'VIDEO',
        );
        final presence =
            (res['targetPresence'] as Map?)?.cast<String, dynamic>();
        if (presence != null &&
            !(presence['status'] == 'ON_CALL' && res['waiting'] == true)) {
          final custom = (presence['customStatus'] ?? '').toString();
          if (presence['status'] == 'ON_CALL' ||
              custom.toLowerCase().contains('another call')) {
            try {
              final tts = FlutterTts();
              await tts.setSpeechRate(0.36);
              await tts.speak(
                  '${user['name']} is busy with another call. Please call again later.');
            } catch (_) {}
          }
          if (context.mounted) {
            bestieToast(context, '${user['name']} is unavailable',
                body:
                    (presence['customStatus'] ?? presence['status']).toString(),
                kind: BestieToastKind.warning);
          }
          return;
        }
        final id = (res['call'] as Map?)?['id']?.toString();
        if (presence?['status'] == 'ON_CALL' && res['waiting'] == true) {
          try {
            final tts = FlutterTts();
            await tts.setSpeechRate(0.36);
            await tts.speak(
                '${user['name']} is busy on another call. Waiting for them to respond.');
          } catch (_) {}
          if (context.mounted) {
            bestieToast(context, '${user['name']} is busy',
                body:
                    'Waiting for them to accept and add you to their call.',
                kind: BestieToastKind.info);
          }
          return;
        }
        if (id != null && context.mounted) {
          context.go('/call/$id?mode=$mode');
        }
      },
    );
    if (channel != null && context.mounted) {
      ref.invalidate(channelsProvider);
      final id = channel['id']?.toString();
      if (id != null) context.push('/chat/$id');
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
                child: Text('$count',
                    style: TextStyle(
                      fontSize: 10,
                      color: c.textSoft,
                      fontWeight: BestieTokens.fwBold,
                    )),
              ),
            ],
          ]),
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Text(emptyHint,
                style: TextStyle(color: c.textFaint, fontSize: 12)),
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

  const _ChatTile(
      {required this.channel, required this.kind, required this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final members =
        (channel['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    // Unread is driven by the backend's unreadCount, which already EXCLUDES
    // the current user's own messages — so sending a message yourself never
    // lights up an unread badge. (The old `lastReadAt == null` check did,
    // which made your own "Hii" look like an incoming unread message.)
    final unreadCount = (channel['unreadCount'] as num?)?.toInt() ?? 0;
    final unread = unreadCount > 0;
    final isClient = channel['isClientChannel'] == true || kind == 'CLIENT';

    // Build display name. For DMs prefer the *other* member's name.
    String displayName = (channel['name'] ?? '').toString().trim();
    String? avatarUrl;
    Map<String, dynamic>? dmOtherUser;
    if (kind == 'DM') {
      dmOtherUser = _resolveDmPeer(members, currentUserId);
      if (dmOtherUser != null) {
        displayName = _displayNameForUser(dmOtherUser, fallback: displayName);
        avatarUrl = dmOtherUser['avatarUrl']?.toString();
      }
    }
    if (displayName.isEmpty) displayName = 'Chat';
    final showCallActions = kind == 'DM' && _canCallUser(ref, dmOtherUser);

    final channelId = channel['id']?.toString() ?? '';
    final clearedAt =
        ref.watch(chatClearedAtProvider(channelId)).asData?.value;

    // Prefer the last message body as the preview line — what WhatsApp /
    // Telegram show. Falls back to the member count.
    final lastMessage =
        (channel['lastMessage'] as Map?)?.cast<String, dynamic>();
    final lastCleared = isLastMessageCleared(lastMessage, clearedAt);
    final lastBody = (lastMessage?['body'] ?? '').toString();
    final lastKind = (lastMessage?['kind'] ?? 'TEXT').toString();
    final hasLast = lastMessage != null && !lastCleared;
    // CALL_EVENT bodies carry a "|call:<id>:<status>" trailer used by the chat
    // bubble for the tap-to-join affordance — strip it from the list preview
    // so it doesn't leak ("Call ended · 12:07 PM · 14m|call:cmpsam…").
    final callPipe = lastBody.indexOf('|call:');
    final cleanBody =
        callPipe >= 0 ? lastBody.substring(0, callPipe) : lastBody;
    String previewBody = cleanBody;
    if (lastKind == 'CALL_EVENT' && callPipe >= 0) {
      previewBody = CallEventText.previewForViewer(
        rawBody: lastBody,
        viewerId: currentUserId,
        authorIdFallback: lastMessage?['authorId']?.toString(),
      );
    }
    String previewLine;
    if (hasLast) {
      final base = switch (lastKind) {
        'IMAGE' => '📷 Photo',
        'FILE' => '📎 File',
        'VOICE_NOTE' => '🎙️ Voice note',
        'CALL_EVENT' => previewBody.isEmpty ? '📞 Call' : previewBody,
        'SYSTEM' => cleanBody,
        _ => cleanBody.isEmpty ? '' : cleanBody,
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
      previewLine = lastCleared
          ? 'Chat cleared'
          : switch (kind) {
              'DM' => 'Direct message',
              'CLIENT' =>
                '${members.length} member${members.length == 1 ? '' : 's'} · client',
              _ => '${members.length} member${members.length == 1 ? '' : 's'}',
            };
    }
    // Live "typing…" overrides the preview line whenever someone in this
    // channel is mid-keystroke (driven by typingChannelsProvider).
    final isTyping =
        ref.watch(typingChannelsProvider).contains(channel['id']?.toString());

    final muted = ref
            .watch(chatMutedChannelsProvider)
            .asData
            ?.value
            .contains(channel['id'] as String) ??
        false;

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              ProfileAvatarViewer.show(
                context,
                name: displayName,
                imageUrl: kind == 'DM' ? avatarUrl : null,
                isClient: isClient,
              );
            },
            child: kind == 'DM'
                ? BestieAvatar(
                    name: displayName,
                    imageUrl: avatarUrl,
                    isClient: isClient,
                    size: 44,
                  )
                : Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isClient ? c.clientSoft : c.brandSoft,
                      borderRadius: BorderRadius.circular(BestieTokens.rMd),
                    ),
                    child: Icon(
                      kind == 'CLIENT'
                          ? Icons.business_center_outlined
                          : Icons.groups_outlined,
                      color: isClient ? c.client : c.brandStrong,
                      size: 22,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => context.push('/chat/${channel['id']}'),
              onLongPress: () => _showTileMenu(context, ref, muted),
              borderRadius: BorderRadius.circular(BestieTokens.rMd),
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
                          fontWeight: unread
                              ? BestieTokens.fwBold
                              : BestieTokens.fwSemibold,
                          color: c.text,
                          letterSpacing: BestieTokens.lsSnug,
                        ),
                      ),
                    ),
                    if (muted) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.volume_off_rounded,
                          size: 13, color: c.textMuted),
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
                          previewLine.isEmpty ? 'No messages yet' : previewLine,
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
          ),
          if (unread) ...[
            const SizedBox(width: 6),
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
            ),
          ],
            if (kind == 'DM') ...[
              if (showCallActions) ...[
                _chatListCallButton(
                  colors: c,
                  icon: Icons.call_rounded,
                  tooltip: 'Voice call',
                  onPressed: () => _startCallFromList(
                    context,
                    ref,
                    user: dmOtherUser!,
                    channelId: channel['id']?.toString(),
                    mode: 'voice',
                  ),
                ),
                const SizedBox(width: 4),
                _chatListCallButton(
                  colors: c,
                  icon: Icons.videocam_rounded,
                  tooltip: 'Video call',
                  onPressed: () => _startCallFromList(
                    context,
                    ref,
                    user: dmOtherUser!,
                    channelId: channel['id']?.toString(),
                    mode: 'video',
                  ),
                ),
              ] else ...[
                const SizedBox(width: 36),
                const SizedBox(width: 36),
              ],
            ],
          ]),
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
                await writeChatUnmuted(channelId);
                ref.invalidate(chatMutedUntilProvider);
                ref.invalidate(chatMutedChannelsProvider);
                return;
              }
              if (!context.mounted) return;
              await showChatMuteDurationPicker(context, ref, channelId);
            },
          ),
          ListTile(
            leading: Icon(Icons.done_all_rounded, color: c.textSoft),
            title: Text('Mark as read', style: TextStyle(color: c.text)),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(apiProvider)
                    .markChannelRead(channel['id'] as String);
                ref.invalidate(channelsProvider);
              } catch (e) {
                if (context.mounted)
                  bestieToast(context, 'Could not mark read',
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
