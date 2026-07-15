import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../branding.dart';
import '../call_event_text.dart';
import '../chat_clear.dart';
import '../chat_mute.dart';
import '../state.dart';
import 'call_screen.dart';
import '../widgets/profile_avatar_viewer.dart';

/// WhatsApp-style recency — pinned first, then most recent activity.
DateTime _channelActivityTime(Map<String, dynamic> channel) {
  final lastMsg = (channel['lastMessage'] as Map?)?.cast<String, dynamic>();
  final fromMessage =
      DateTime.tryParse(lastMsg?['createdAt']?.toString() ?? '');
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

bool _isPlatformSuperAdmin(Map<String, dynamic>? user) =>
    user?['role']?.toString() == 'SUPER_ADMIN';

bool _isOrgAdmin(BestieUser? user) {
  final role = user?.role ?? '';
  return role == 'ADMIN' || role == 'SUPER_ADMIN';
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

bool _isReallyOnline(Map<String, dynamic>? user) =>
    user?['online'] == true ||
    (((user?['presence'] as Map?)?.cast<String, dynamic>())?['online'] == true);

Color _presenceDotColor(Map<String, dynamic>? user, Color brand) {
  if (user == null) return Colors.transparent;
  if (_isReallyOnline(user)) return brand;
  final status = (user['status'] ?? '').toString();
  if (status == 'AWAY' || status == 'BUSY') return const Color(0xFFFFC107);
  return const Color(0xFFB4BAC6);
}

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _timeLabel(DateTime time) {
  final now = DateTime.now();
  final local = time.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(local.year, local.month, local.day);
  final dayDiff = today.difference(msgDay).inDays;
  if (dayDiff == 0) {
    final hour = local.hour == 0
        ? 12
        : local.hour > 12
            ? local.hour - 12
            : local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }
  if (dayDiff == 1) return 'Yesterday';
  if (dayDiff < 7) return _weekdayNames[local.weekday - 1];
  return '${local.month}/${local.day}/${local.year % 100}';
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
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final channels = ref.watch(channelsProvider);
    final me = ref.watch(authStoreProvider).user;
    // Clear the shell's bottom nav without a nested Scaffold bottom bar — an
    // empty SizedBox there renders as a white strip above the real footer.
    final shellNavClearance =
        70.0 + 24 + MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: colors.surface,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: shellNavClearance),
        child: FloatingActionButton(
          backgroundColor: colors.brand,
          foregroundColor: Colors.white,
          elevation: 4,
          tooltip: 'New chat',
          onPressed: () => _newChat(context, ref),
          child: const Icon(Icons.edit_outlined),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChatsHeader(
              colors: colors,
              user: me,
              onMenuSelected: (value) => _onHeaderMenu(context, ref, value),
              onEditOrg:
                  _isOrgAdmin(me) ? () => _editOrgName(context, ref) : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                style: TextStyle(color: colors.text, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search messages...',
                  hintStyle: TextStyle(color: colors.textFaint, fontSize: 15),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: colors.textMuted, size: 20),
                  filled: true,
                  fillColor: colors.surface2,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide:
                        BorderSide(color: colors.brand.withValues(alpha: 0.35)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.refresh(channelsProvider.future),
                child: channels.when(
                  loading: () => const BestieSkeletonList(itemCount: 6),
                  error: (e, _) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.55,
                        child: BestieEmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'Couldn\'t load chats',
                          description: formatApiError(e),
                          action: FilledButton.icon(
                            onPressed: () =>
                                ref.invalidate(channelsProvider),
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.brand,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return _EmptyState(
                          onNewChat: () => _newChat(context, ref));
                    }

                    final dms = <Map<String, dynamic>>[];
                    final groups = <Map<String, dynamic>>[];
                    final clientChannels = <Map<String, dynamic>>[];

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

                    _sortChannelsByRecent(dms);
                    _sortChannelsByRecent(groups);
                    _sortChannelsByRecent(clientChannels);

                    bool matchesQuery(
                        Map<String, dynamic> channel, String kind) {
                      if (_query.isEmpty) return true;
                      final members = (channel['members'] as List?)
                              ?.cast<Map<String, dynamic>>() ??
                          const [];
                      Map<String, dynamic>? peer;
                      if (kind == 'DM') {
                        peer = _resolveDmPeer(members, me?.id);
                      }
                      final name = kind == 'DM'
                          ? _displayNameForUser(
                              peer,
                              fallback: (channel['name'] ?? '').toString(),
                            )
                          : (channel['name'] ?? '').toString();
                      return name.toLowerCase().contains(_query);
                    }

                    final filteredDms =
                        dms.where((c) => matchesQuery(c, 'DM')).toList();
                    final filteredGroups =
                        groups.where((c) => matchesQuery(c, 'GROUP')).toList();
                    final filteredClients = clientChannels
                        .where((c) => matchesQuery(c, 'CLIENT'))
                        .toList();

                    if (_query.isNotEmpty &&
                        filteredDms.isEmpty &&
                        filteredGroups.isEmpty &&
                        filteredClients.isEmpty) {
                      return bestieEmptyScrollable(
                        context,
                        const BestieEmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No chats found',
                          description: 'Try a different name or keyword.',
                        ),
                      );
                    }

                    return ListView(
                      padding: EdgeInsets.only(bottom: shellNavClearance + 16),
                      children: [
                        _Section(
                          title: 'Direct messages',
                          icon: Icons.chat_bubble_outline_rounded,
                          count: filteredDms.length,
                          emptyHint:
                              'Tap Edit above or the pencil button to start a chat.',
                          children: [
                            for (final c in filteredDms)
                              _ChatTile(
                                channel: c,
                                kind: 'DM',
                                currentUserId: me?.id,
                              ),
                          ],
                        ),
                        _Section(
                          title: 'Groups',
                          icon: Icons.groups_outlined,
                          count: filteredGroups.length,
                          emptyHint:
                              'Create a group to chat with multiple teammates at once.',
                          children: [
                            for (final c in filteredGroups)
                              _ChatTile(
                                channel: c,
                                kind: 'GROUP',
                                currentUserId: me?.id,
                              ),
                          ],
                        ),
                        _Section(
                          title: 'Client channels',
                          icon: Icons.business_center_outlined,
                          count: filteredClients.length,
                          emptyHint:
                              'External client threads will appear here.',
                          children: [
                            for (final c in filteredClients)
                              _ChatTile(
                                channel: c,
                                kind: 'CLIENT',
                                currentUserId: me?.id,
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onHeaderMenu(BuildContext context, WidgetRef ref, String value) {
    switch (value) {
      case 'refresh':
        ref.invalidate(channelsProvider);
        break;
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
      case 'edit_org':
        _editOrgName(context, ref);
        break;
    }
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    final api = ref.read(apiProvider);
    final me = ref.read(authStoreProvider).user;
    final channels = ref.read(channelsProvider).asData?.value ?? const [];
    if (me == null) return;
    final unreadIds = channels
        .where((c) => ((c['unreadCount'] as num?)?.toInt() ?? 0) > 0)
        .map((c) => c['id'] as String)
        .toList();
    if (unreadIds.isEmpty) {
      bestieToast(context, 'Already all read', kind: BestieToastKind.info);
      return;
    }
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

  Future<void> _editOrgName(BuildContext context, WidgetRef ref) async {
    final branding = await ref.read(orgBrandingProvider.future);
    if (!context.mounted) return;
    final controller = TextEditingController(text: branding.name);
    final c = BestieColors.of(context);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Organization name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'MyTaskKing',
            labelText: 'Display name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null || !context.mounted) return;
    try {
      await ref.read(apiProvider).setSetting(
            scope: 'branding',
            key: 'name',
            value: saved,
          );
      ref.invalidate(orgBrandingProvider);
      if (context.mounted) {
        bestieToast(context, 'Organization name updated',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (context.mounted) {
        bestieToast(context, 'Could not save name',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
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
      fetchEmployees: (q) => api.listEmployees(
        q: q.trim().isEmpty ? null : q.trim(),
        forChat: true,
        pageSize: 200,
      ),
      onStartDm: (otherId) async {
        final ch = await api.createChannel(kind: 'DM', memberIds: [otherId]);
        return ch;
      },
      onStartGroup: (name, memberIds, {iconUrl}) async {
        final ch = await api.createChannel(
          kind: 'GROUP',
          name: name,
          memberIds: memberIds,
          iconUrl: iconUrl,
        );
        return ch;
      },
      pickGroupIcon: () async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );
        if (result == null ||
            result.files.isEmpty ||
            result.files.first.bytes == null) {
          return null;
        }
        final file = result.files.first;
        final asset = await api.uploadFile(
          bytes: file.bytes!,
          filename: file.name,
          mimeType: 'image/${file.extension ?? 'jpeg'}',
        );
        return asset['url']?.toString();
      },
      onStartCall: (user, mode) async {
        if (_isPlatformSuperAdmin(user)) {
          if (context.mounted) {
            bestieToast(
              context,
              'Calling unavailable',
              body:
                  'Platform administrators cannot be called from direct messages.',
              kind: BestieToastKind.warning,
            );
          }
          return;
        }
        final targetRole = user['role']?.toString();
        final viewerIsAdmin = me?.role == 'ADMIN' || me?.role == 'SUPER_ADMIN';
        if (!viewerIsAdmin && targetRole == 'ADMIN') {
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
                body: 'Waiting for them to accept and add you to their call.',
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
// header + chat tile
// ---------------------------------------------------------------------------

class _ChatsHeader extends ConsumerWidget {
  final BestieColors colors;
  final BestieUser? user;
  final ValueChanged<String> onMenuSelected;
  final VoidCallback? onEditOrg;

  const _ChatsHeader({
    required this.colors,
    required this.user,
    required this.onMenuSelected,
    this.onEditOrg,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(orgBrandingProvider).asData?.value;
    final isAdmin = _isOrgAdmin(user);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
      child: Row(
        children: [
          Expanded(child: _headerBrand(branding)),
          IconButton(
            tooltip: 'Refresh chats',
            icon: Icon(Icons.refresh_rounded, color: colors.text),
            onPressed: () => onMenuSelected('refresh'),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: colors.text),
            tooltip: 'More options',
            onSelected: onMenuSelected,
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh_rounded, color: colors.text, size: 22),
                    const SizedBox(width: 12),
                    const Text('Refresh'),
                  ],
                ),
              ),
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
                    Icon(Icons.group_add_outlined,
                        color: colors.text, size: 22),
                    const SizedBox(width: 12),
                    const Text('New group'),
                  ],
                ),
              ),
              if (isAdmin)
                PopupMenuItem(
                  value: 'edit_org',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, color: colors.brand, size: 22),
                      const SizedBox(width: 12),
                      const Text('Edit organization name'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerBrand(OrgBranding? branding) {
    const logoSize = 36.0;
    const myTaskKingFontSize = 21.0; // +6px over default wordmark (~15px)
    final orgName = branding?.name ?? 'MyTaskKing';
    final logoUrl = branding?.logoUrl;
    final isDefault = orgName == 'MyTaskKing' && logoUrl == null;
    if (isDefault) {
      return Row(
        children: [
          BestieLogo(size: logoSize, onTap: onEditOrg),
          SizedBox(width: logoSize * 0.30),
          GestureDetector(
            onTap: onEditOrg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Stroke so brand text stays readable on light/dark surfaces.
                Stack(
                  children: [
                    Text(
                      'MyTaskKing',
                      style: TextStyle(
                        fontSize: myTaskKingFontSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.54,
                        height: 1.05,
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 1.4
                          ..color = colors.text.withValues(alpha: 0.35),
                      ),
                    ),
                    ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (rect) => LinearGradient(
                        colors: [
                          BestieTokens.cAccent,
                          colors.brand,
                          const Color(0xFF3AA1FF),
                        ],
                      ).createShader(rect),
                      child: const Text(
                        'MyTaskKing',
                        style: TextStyle(
                          fontSize: myTaskKingFontSize,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.54,
                          height: 1.05,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: logoSize * 0.04),
                Text(
                  'Productivity',
                  style: TextStyle(
                    fontSize: logoSize * 0.22,
                    fontWeight: FontWeight.w600,
                    color: BestieTokens.cTextMuted,
                    letterSpacing: 0.06 * logoSize * 0.22,
                  ),
                ),
              ],
            ),
          ),
          if (onEditOrg != null) _editOrgButton(),
        ],
      );
    }
    return Row(
      children: [
        if (logoUrl != null)
          ClipOval(
            child: Image.network(
              logoUrl,
              width: logoSize,
              height: logoSize,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  BestieLogo(size: logoSize, ambient: false, onTap: onEditOrg),
            ),
          )
        else
          BestieLogo(size: logoSize, ambient: false, onTap: onEditOrg),
        const SizedBox(width: 10),
        Flexible(
          child: GestureDetector(
            onTap: onEditOrg,
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) => LinearGradient(
                colors: [
                  BestieTokens.cAccent,
                  colors.brand,
                  const Color(0xFF3AA1FF),
                ],
              ).createShader(rect),
              child: Text(
                orgName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        if (onEditOrg != null) _editOrgButton(),
      ],
    );
  }

  Widget _editOrgButton() {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: 'Edit organization name',
      icon: Icon(Icons.edit_outlined, size: 18, color: colors.textMuted),
      onPressed: onEditOrg,
    );
  }
}

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
    String? groupIconUrl;
    Map<String, dynamic>? dmOtherUser;
    if (kind == 'DM') {
      dmOtherUser = _resolveDmPeer(members, currentUserId);
      if (dmOtherUser != null) {
        displayName = _displayNameForUser(dmOtherUser, fallback: displayName);
        avatarUrl = dmOtherUser['avatarUrl']?.toString();
      }
    }
    if (displayName.isEmpty) displayName = 'Chat';
    if (kind != 'DM') {
      final icon = channel['iconUrl']?.toString();
      if (icon != null && icon.isNotEmpty) groupIconUrl = icon;
    }
    final timestamp = _timeLabel(_channelActivityTime(channel));

    final channelId = channel['id']?.toString() ?? '';
    final clearedAt = ref.watch(chatClearedAtProvider(channelId)).asData?.value;

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
      child: InkWell(
        onTap: () => context.push('/chat/${channel['id']}'),
        onLongPress: () => _showTileMenu(context, ref, muted),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  ProfileAvatarViewer.show(
                    context,
                    name: displayName,
                    imageUrl: kind == 'DM' ? avatarUrl : groupIconUrl,
                    isClient: isClient,
                  );
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    kind == 'DM'
                        ? BestieAvatar(
                            name: displayName,
                            imageUrl: avatarUrl,
                            isClient: isClient,
                            size: 52,
                          )
                        : groupIconUrl != null
                            ? ClipOval(
                                child: Image.network(
                                  groupIconUrl,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: isClient
                                          ? c.clientSoft
                                          : c.brandSoft,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      kind == 'CLIENT'
                                          ? Icons.business_center_outlined
                                          : Icons.groups_outlined,
                                      color: isClient
                                          ? c.client
                                          : c.brandStrong,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: isClient ? c.clientSoft : c.brandSoft,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              kind == 'CLIENT'
                                  ? Icons.business_center_outlined
                                  : Icons.groups_outlined,
                              color: isClient ? c.client : c.brandStrong,
                              size: 24,
                            ),
                          ),
                    if (kind == 'DM')
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: _presenceDotColor(dmOtherUser, c.brand),
                            shape: BoxShape.circle,
                            border: Border.all(color: c.surface, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: BestieUserName(
                            name: displayName,
                            isClient: isClient,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w600,
                              color: c.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: isTyping
                              ? Text(
                                  'typing…',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: c.brand,
                                    fontSize: 12,
                                    fontWeight: BestieTokens.fwSemibold,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : Text(
                                  previewLine.isEmpty
                                      ? 'No messages yet'
                                      : previewLine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: c.textMuted,
                                    fontSize: 12,
                                    fontWeight: unread
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    fontStyle: (lastKind == 'FILE' ||
                                            lastKind == 'IMAGE')
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timestamp,
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textMuted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (unread) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: muted ? c.textMuted : c.brand,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: BestieTokens.fwBold,
                          height: 1,
                        ),
                      ),
                    ),
                  ] else if (muted) ...[
                    const SizedBox(height: 6),
                    Icon(Icons.volume_off_rounded,
                        size: 14, color: c.textMuted),
                  ],
                ],
              ),
            ],
          ),
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
    final colors = BestieColors.of(context);
    return BestieEmptyState(
      icon: Icons.chat_bubble_outline_rounded,
      title: 'No chats yet',
      description: 'Start a direct message with a teammate or create a group.',
      action: FilledButton.icon(
        onPressed: onNewChat,
        style: FilledButton.styleFrom(
          backgroundColor: colors.brand,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: const Text('Start a chat'),
      ),
    );
  }
}
