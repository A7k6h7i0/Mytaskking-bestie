import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_core/mytaskking_core.dart';

import 'branding.dart';
import 'call_event_text.dart';
import 'chat_clear.dart';
import 'chat_mute.dart';
import 'chat_typing.dart';
import 'screens/call_screen.dart';
import 'screens/chat_detail_screen.dart';
import 'state.dart';
import 'widgets/profile_avatar_viewer.dart';
import 'windows_workspace.dart';

final desktopChatDirectoryProvider =
    FutureProvider.family.autoDispose<List<Map<String, dynamic>>, String>(
  (ref, q) => ref.watch(apiProvider).listChannelDirectory(
        q: q.trim().isEmpty ? null : q.trim(),
      ),
);

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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

String _desktopTimeLabel(DateTime time) {
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

bool _isOrgAdmin(BestieUser? user) {
  final role = user?.role ?? '';
  return role == 'ADMIN' || role == 'SUPER_ADMIN';
}

/// Split-pane chat workspace shared by Windows and Linux desktop apps.
class DesktopChatScreen extends ConsumerStatefulWidget {
  const DesktopChatScreen({super.key, this.initialChannelId});

  final String? initialChannelId;

  @override
  ConsumerState<DesktopChatScreen> createState() => _DesktopChatScreenState();
}

class _DesktopChatScreenState extends ConsumerState<DesktopChatScreen> {
  String? _selectedChannelId;
  String _query = '';
  String _filter = 'All';
  int _chatDetailEpoch = 0;
  final _chatDetailKey = GlobalKey<ChatDetailScreenState>();
  bool _appliedInitialChannel = false;

  @override
  void initState() {
    super.initState();
    _selectedChannelId = widget.initialChannelId;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(typingChannelsProvider);
    final colors = BestieColors.of(context);
    final channels = ref.watch(channelsProvider);
    return channels.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(
          formatApiError(err),
          style: TextStyle(color: colors.danger),
        ),
      ),
      data: (items) {
        final directory =
            ref.watch(desktopChatDirectoryProvider(_query)).asData?.value ??
                const <Map<String, dynamic>>[];
        final filtered = _filtered(_withDirectoryRows(items, directory));
        if (_selectedChannelId == null && filtered.isNotEmpty) {
          Map<String, dynamic>? firstChannel;
          for (final row in filtered) {
            if (row['_entryType'] != 'employee') {
              firstChannel = row;
              break;
            }
          }
          _selectedChannelId = firstChannel?['id']?.toString();
        } else if (!_appliedInitialChannel &&
            widget.initialChannelId != null &&
            filtered.any(
              (c) => c['id']?.toString() == widget.initialChannelId,
            )) {
          _selectedChannelId = widget.initialChannelId;
          _appliedInitialChannel = true;
        }
        Map<String, dynamic>? selected;
        for (final channel in filtered) {
          if (channel['id']?.toString() == _selectedChannelId) {
            selected = channel;
            break;
          }
        }

        return Row(
          children: [
            SizedBox(
              width: 330,
              child: _ChatRail(
                channels: filtered,
                selectedId: _selectedChannelId,
                query: _query,
                filter: _filter,
                onQuery: (value) => setState(() => _query = value),
                onFilter: (value) => setState(() => _filter = value),
                onSelect: _selectRow,
                onRefresh: () async => ref.refresh(channelsProvider.future),
                onGlobalSearch: () => context.go('/search'),
                onMarkAllRead: () => _markAllRead(context),
                onNewChat: () => _newChat(context, initialTabIndex: 0),
                onNewGroup: () => _newChat(context, initialTabIndex: 1),
                onEditOrg:
                    _isOrgAdmin(ref.read(authStoreProvider).user)
                        ? () => _editOrgName(context)
                        : null,
                onDeletedChats: _isOrgAdmin(ref.read(authStoreProvider).user)
                    ? () => context.go('/deleted-chats')
                    : null,
              ),
            ),
            VerticalDivider(width: 1, color: colors.border),
            Expanded(
              child: selected == null
                  ? _EmptyChat(colors: colors)
                  : Builder(builder: (context) {
                      final selectedChannel = selected!;
                      final detailState = _chatDetailKey.currentState;
                      return Column(
                        children: [
                          _ConversationHeader(
                            key: ValueKey(_selectedChannelId),
                            channel: selectedChannel,
                            detailState: detailState,
                            onBack: () =>
                                setState(() => _selectedChannelId = null),
                            onVoice: () => _startCall(selectedChannel, 'voice'),
                            onVideo: () => _startCall(selectedChannel, 'video'),
                            onMore: () {
                              if (detailState != null &&
                                  detailState.widget.channelId ==
                                      _selectedChannelId) {
                                detailState.showMoreMenu();
                              } else {
                                _showFallbackMenu(selectedChannel);
                              }
                            },
                            onTitleTap: () {
                              if (detailState != null &&
                                  detailState.widget.channelId ==
                                      _selectedChannelId) {
                                detailState.openContactScreen();
                              }
                            },
                            onAvatarTap: () {
                              if (detailState != null &&
                                  detailState.widget.channelId ==
                                      _selectedChannelId) {
                                detailState.showProfileAvatar();
                              } else {
                                ProfileAvatarViewer.show(
                                  context,
                                  name: _channelTitle(
                                    selectedChannel,
                                    ref.read(authStoreProvider).user?.id,
                                  ),
                                  imageUrl: _dmPeer(
                                    selectedChannel,
                                    ref.read(authStoreProvider).user?.id,
                                  )?['avatarUrl']
                                      ?.toString(),
                                  isClient:
                                      selectedChannel['isClientChannel'] ==
                                          true,
                                );
                              }
                            },
                          ),
                          Divider(height: 1, color: colors.border),
                          Expanded(
                            child: KeyedSubtree(
                              key: ValueKey(
                                '${_selectedChannelId!}_$_chatDetailEpoch',
                              ),
                              child: ChatDetailScreen(
                                key: _chatDetailKey,
                                channelId: _selectedChannelId!,
                                hideHeader: true,
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _withDirectoryRows(
    List<Map<String, dynamic>> channels,
    List<Map<String, dynamic>> directory,
  ) {
    final meId = ref.read(authStoreProvider).user?.id;
    final dmPeerIds = <String>{};
    for (final channel in channels) {
      if ((channel['kind'] ?? '').toString().toUpperCase() != 'DM') continue;
      final peer = _dmPeer(channel, meId);
      final id = peer?['id']?.toString();
      if (id != null && id.isNotEmpty) dmPeerIds.add(id);
    }
    final rows = [...channels];
    for (final user in directory) {
      final id = user['id']?.toString();
      if (id == null || id == meId || dmPeerIds.contains(id)) continue;
      rows.add({
        '_entryType': 'employee',
        'id': 'employee:$id',
        'employee': user,
        'kind': 'DM',
        'updatedAt': user['updatedAt'],
      });
    }
    return rows;
  }

  Future<void> _selectRow(Map<String, dynamic> row) async {
    if (row['_entryType'] == 'employee') {
      final employee = (row['employee'] as Map?)?.cast<String, dynamic>();
      final id = employee?['id']?.toString();
      if (id == null) return;
      try {
        final channel = await ref
            .read(apiProvider)
            .createChannel(kind: 'DM', memberIds: [id]);
        ref.invalidate(channelsProvider);
        if (!mounted) return;
        setState(() {
          _selectedChannelId = channel['id']?.toString();
          _chatDetailEpoch++;
        });
      } catch (err) {
        if (!mounted) return;
        bestieToast(
          context,
          'Could not open chat',
          body: formatApiError(err),
          kind: BestieToastKind.error,
        );
      }
      return;
    }
    setState(() {
      _selectedChannelId = row['id']?.toString();
      _chatDetailEpoch++;
    });
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> items) {
    final q = _query.trim().toLowerCase();
    final meId = ref.read(authStoreProvider).user?.id;
    final list = items.where((channel) {
      final kind = (channel['kind'] ?? 'GROUP').toString().toUpperCase();
      if (_filter == 'Direct' && kind != 'DM') return false;
      if (_filter == 'Groups' && kind == 'DM') return false;
      if (_filter == 'Channels' &&
          kind != 'CLIENT' &&
          channel['isClientChannel'] != true) {
        return false;
      }
      if (q.isEmpty) return true;
      return _channelTitle(channel, meId).toLowerCase().contains(q) ||
          _previewLine(channel, meId, ref).toLowerCase().contains(q);
    }).toList();
    _sortChannelsByRecent(list);
    return list;
  }

  Future<void> _markAllRead(BuildContext context) async {
    final api = ref.read(apiProvider);
    final channels = ref.read(channelsProvider).asData?.value ?? const [];
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
      bestieToast(
        context,
        'Marked ${unreadIds.length} chat${unreadIds.length == 1 ? '' : 's'} read',
        kind: BestieToastKind.success,
      );
    }
  }

  Future<void> _editOrgName(BuildContext context) async {
    final branding = await ref.read(orgBrandingProvider.future);
    final ctl = TextEditingController(text: branding.name);
    if (!context.mounted) return;
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit organization name'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Organization name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (saved == null || saved.isEmpty || !context.mounted) return;
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
    BuildContext context, {
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
      onStartDm: (otherId) async =>
          api.createChannel(kind: 'DM', memberIds: [otherId]),
      onStartGroup: (name, memberIds, {iconUrl}) async => api.createChannel(
        kind: 'GROUP',
        name: name,
        memberIds: memberIds,
        iconUrl: iconUrl,
      ),
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
    );
    if (channel == null || !mounted) return;
    ref.invalidate(channelsProvider);
    final id = channel['id']?.toString();
    if (id != null) {
      setState(() {
        _selectedChannelId = id;
        _chatDetailEpoch++;
      });
    }
  }

  void _showFallbackMenu(Map<String, dynamic> channel) {
    bestieToast(
      context,
      'Loading chat…',
      body: 'Try again in a moment.',
      kind: BestieToastKind.info,
    );
  }

  Future<void> _startCall(Map<String, dynamic> channel, String mode) async {
    final peer = _dmPeer(channel, ref.read(authStoreProvider).user?.id);
    if (peer == null) return;
    final me = ref.read(authStoreProvider).user;
    final viewerIsAdmin = me?.role == 'ADMIN' || me?.role == 'SUPER_ADMIN';
    final peerRole = peer['role']?.toString();
    if (!viewerIsAdmin && (peerRole == 'ADMIN' || peerRole == 'SUPER_ADMIN')) {
      bestieToast(
        context,
        'Calling unavailable',
        body: 'Only admins can start calls with administrators.',
        kind: BestieToastKind.warning,
      );
      return;
    }
    try {
      await CallSession.prepareForNewCall();
      final res = await ref.read(apiProvider).initiateCall(
            participantIds: [peer['id'].toString()],
            kind: 'ONE_TO_ONE',
            channelId: channel['id']?.toString(),
            mode: mode == 'voice' ? 'VOICE' : 'VIDEO',
          );
      final id = (res['call'] as Map?)?['id']?.toString();
      if (id != null && mounted) context.go('/call/$id?mode=$mode');
    } catch (err) {
      if (!mounted) return;
      bestieToast(
        context,
        'Could not start call',
        body: formatApiError(err),
        kind: BestieToastKind.error,
      );
    }
  }
}

class _ChatRail extends ConsumerWidget {
  const _ChatRail({
    required this.channels,
    required this.selectedId,
    required this.query,
    required this.filter,
    required this.onQuery,
    required this.onFilter,
    required this.onSelect,
    required this.onRefresh,
    required this.onGlobalSearch,
    required this.onMarkAllRead,
    required this.onNewChat,
    required this.onNewGroup,
    this.onEditOrg,
    this.onDeletedChats,
  });

  final List<Map<String, dynamic>> channels;
  final String? selectedId;
  final String query;
  final String filter;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onFilter;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final Future<void> Function() onRefresh;
  final VoidCallback onGlobalSearch;
  final VoidCallback onMarkAllRead;
  final VoidCallback onNewChat;
  final VoidCallback onNewGroup;
  final VoidCallback? onEditOrg;
  final VoidCallback? onDeletedChats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    return ColoredBox(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Chat',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Global search',
                  onPressed: onGlobalSearch,
                  icon: Icon(Icons.search_rounded, color: c.textMuted, size: 22),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Chat actions',
                  icon: Icon(Icons.more_vert_rounded, color: c.textMuted),
                  onSelected: (value) {
                    switch (value) {
                      case 'refresh':
                        onRefresh();
                      case 'mark_read':
                        onMarkAllRead();
                      case 'new_chat':
                        onNewChat();
                      case 'new_group':
                        onNewGroup();
                      case 'edit_org':
                        onEditOrg?.call();
                      case 'deleted':
                        onDeletedChats?.call();
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        leading: Icon(Icons.refresh_rounded),
                        title: Text('Refresh'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'mark_read',
                      child: ListTile(
                        leading: Icon(Icons.done_all_rounded),
                        title: Text('Mark all chats read'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'new_chat',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('New chat'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'new_group',
                      child: ListTile(
                        leading: Icon(Icons.group_add_outlined),
                        title: Text('New group'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (onEditOrg != null)
                      const PopupMenuItem(
                        value: 'edit_org',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit organization name'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (onDeletedChats != null)
                      const PopupMenuItem(
                        value: 'deleted',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Deleted chats'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              onChanged: onQuery,
              decoration: InputDecoration(
                hintText: 'Search chats…',
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: IconButton(
                  tooltip: 'Search messages & files',
                  onPressed: onGlobalSearch,
                  icon: const Icon(Icons.manage_search_rounded, size: 20),
                ),
                filled: true,
                fillColor: c.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: c.border),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'All', label: Text('All')),
                  ButtonSegment(value: 'Direct', label: Text('Direct')),
                  ButtonSegment(value: 'Groups', label: Text('Groups')),
                  ButtonSegment(value: 'Channels', label: Text('Channels')),
                ],
                selected: {filter},
                onSelectionChanged: (next) => onFilter(next.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 24, color: c.border),
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  final id = channel['id']?.toString() ?? '';
                  return _ChatTile(
                    channel: channel,
                    selected: id == selectedId,
                    onTap: () => onSelect(channel),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends ConsumerWidget {
  const _ChatTile({
    required this.channel,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> channel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final meId = ref.watch(authStoreProvider).user?.id;
    final kind = (channel['kind'] ?? 'GROUP').toString().toUpperCase();
    final title = _channelTitle(channel, meId);
    final peer = _dmPeer(channel, meId);
    final presence = kind == 'DM' ? _presenceLabel(peer) : '';
    final online = _isReallyOnline(peer);
    final unreadCount = (channel['unreadCount'] as num?)?.toInt() ?? 0;
    final unreadMentionCount =
        (channel['unreadMentionCount'] as num?)?.toInt() ?? 0;
    final hasUnreadMention = unreadMentionCount > 0 && kind != 'DM';
    final channelId = channel['id']?.toString() ?? '';
    final isTyping = ref
        .watch(typingChannelsProvider)
        .contains(channelId);
    final muted = ref
            .watch(chatMutedChannelsProvider)
            .asData
            ?.value
            .contains(channelId) ??
        false;
    final groupIconUrl = kind != 'DM'
        ? channel['iconUrl']?.toString()
        : null;
    final isClient =
        channel['isClientChannel'] == true || kind == 'CLIENT';
    final preview = isTyping
        ? 'typing…'
        : _previewLine(channel, meId, ref);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? c.brandSoft.withValues(alpha: 0.75) : c.bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: channel['_entryType'] == 'employee'
              ? null
              : () => _showTileMenu(context, ref, channelId, muted),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    ProfileAvatarViewer.show(
                      context,
                      name: title,
                      imageUrl: kind == 'DM'
                          ? (peer?['avatarUrl'])?.toString()
                          : groupIconUrl,
                      isClient: isClient,
                    );
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      kind == 'DM'
                          ? BestieAvatar(
                              name: title,
                              imageUrl: (peer?['avatarUrl'])?.toString(),
                              isClient: isClient,
                              size: 44,
                            )
                          : groupIconUrl != null && groupIconUrl.isNotEmpty
                              ? ClipOval(
                                  child: Image.network(
                                    groupIconUrl,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => BestieAvatar(
                                      name: title,
                                      size: 44,
                                    ),
                                  ),
                                )
                              : BestieAvatar(name: title, size: 44),
                      if (kind == 'DM')
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: online ? c.success : c.textFaint,
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
                          if (muted)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.volume_off_rounded,
                                  size: 14, color: c.textMuted),
                            ),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            _desktopTimeLabel(_channelActivityTime(channel)),
                            style: TextStyle(
                              color: c.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isTyping ? c.brand : c.textMuted,
                          fontSize: 12,
                          fontStyle:
                              isTyping ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                      if (presence.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          presence,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: online ? c.success : c.warning,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasUnreadMention) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.danger,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '@',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                if (unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.brand,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTileMenu(
    BuildContext context,
    WidgetRef ref,
    String channelId,
    bool currentlyMuted,
  ) {
    final c = BestieColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                currentlyMuted
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
              ),
              title: Text(currentlyMuted
                  ? 'Unmute notifications'
                  : 'Mute notifications'),
              onTap: () async {
                Navigator.pop(ctx);
                if (currentlyMuted) {
                  await writeChatUnmuted(channelId);
                  ref.invalidate(chatMutedUntilProvider);
                  ref.invalidate(chatMutedChannelsProvider);
                } else if (context.mounted) {
                  await showChatMuteDurationPicker(context, ref, channelId);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.done_all_rounded),
              title: const Text('Mark as read'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(apiProvider).markChannelRead(channelId);
                  ref.invalidate(channelsProvider);
                } catch (e) {
                  if (context.mounted) {
                    bestieToast(context, 'Could not mark read',
                        body: formatApiError(e), kind: BestieToastKind.error);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationHeader extends ConsumerWidget {
  const _ConversationHeader({
    super.key,
    required this.channel,
    required this.detailState,
    required this.onBack,
    required this.onVoice,
    required this.onVideo,
    required this.onMore,
    required this.onTitleTap,
    required this.onAvatarTap,
  });

  final Map<String, dynamic> channel;
  final ChatDetailScreenState? detailState;
  final VoidCallback onBack;
  final VoidCallback onVoice;
  final VoidCallback onVideo;
  final VoidCallback onMore;
  final VoidCallback onTitleTap;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final meId = ref.watch(authStoreProvider).user?.id;
    final channelId = channel['id']?.toString() ?? '';
    final fallbackTitle = _channelTitle(channel, meId);
    final fallbackPeer = _dmPeer(channel, meId);
    // detailState can still point at the previous chat for a frame (or until
    // the new ChatDetailScreen loads). Never show stale header data.
    final detailMatches = detailState != null &&
        detailState!.widget.channelId == channelId;
    final title =
        detailMatches ? detailState!.headerTitle() : fallbackTitle;
    final subtitle = detailMatches
        ? detailState!.headerSubtitle()
        : _presenceLabel(fallbackPeer);
    final avatarUrl = detailMatches
        ? detailState!.headerAvatarUrl()
        : (fallbackPeer?['avatarUrl'])?.toString();
    final groupIcon = detailMatches
        ? detailState!.groupIconUrl()
        : channel['iconUrl']?.toString();
    final isDm = detailMatches
        ? detailState!.isDmChannel
        : (channel['kind'] ?? '').toString().toUpperCase() == 'DM';
    final isClient = detailMatches
        ? detailState!.isClientChannel
        : channel['isClientChannel'] == true;
    final online = _isReallyOnline(fallbackPeer);

    return Container(
      height: 76,
      color: c.surface,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          GestureDetector(
            onTap: onAvatarTap,
            child: isDm
                ? BestieAvatar(
                    name: title,
                    imageUrl: avatarUrl,
                    isClient: isClient,
                    size: 38,
                  )
                : groupIcon != null && groupIcon.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          groupIcon,
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              BestieAvatar(name: title, size: 38),
                        ),
                      )
                    : BestieAvatar(name: title, size: 38),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTitleTap,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: subtitle == 'Online' || online
                          ? c.success
                          : subtitle == 'Busy' ||
                                  subtitle == 'Lunch Time' ||
                                  subtitle == 'On a call'
                              ? c.warning
                              : c.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!kWindowsWorkspaceNoCalls) ...[
            _HeaderButton(icon: Icons.call_rounded, onTap: onVoice),
            const SizedBox(width: 10),
            _HeaderButton(icon: Icons.videocam_rounded, onTap: onVideo),
            const SizedBox(width: 10),
          ],
          _HeaderButton(icon: Icons.more_vert_rounded, onTap: onMore),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Material(
      color: c.bg,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: '',
        onPressed: onTap,
        icon: Icon(icon, color: c.brand, size: 20),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.colors});

  final BestieColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Select a conversation',
        style: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _previewLine(
  Map<String, dynamic> channel,
  String? meId,
  WidgetRef ref,
) {
  if (channel['_entryType'] == 'employee') {
    final employee = (channel['employee'] as Map?)?.cast<String, dynamic>();
    final title = (employee?['customTitle'] ?? employee?['role'] ?? '')
        .toString()
        .replaceAll('_', ' ')
        .trim();
    return title.isEmpty ? 'Start a direct message' : title;
  }

  final kind = (channel['kind'] ?? 'GROUP').toString().toUpperCase();
  final channelId = channel['id']?.toString() ?? '';
  final clearedAt =
      ref.watch(chatClearedAtProvider(channelId)).asData?.value;
  final lastMessage =
      (channel['lastMessage'] as Map?)?.cast<String, dynamic>();
  final lastCleared = isLastMessageCleared(lastMessage, clearedAt);
  final lastBody = (lastMessage?['body'] ?? '').toString();
  final lastKind = (lastMessage?['kind'] ?? 'TEXT').toString();
  final hasLast = lastMessage != null && !lastCleared;

  if (!hasLast) {
    if (lastCleared) return 'Chat cleared';
    return kind == 'DM' ? 'No messages yet' : 'No messages yet';
  }

  final callPipe = lastBody.indexOf('|call:');
  final cleanBody = callPipe >= 0 ? lastBody.substring(0, callPipe) : lastBody;
  var previewBody = cleanBody;
  if (lastKind == 'CALL_EVENT' && callPipe >= 0) {
    previewBody = CallEventText.previewForViewer(
      rawBody: lastBody,
      viewerId: meId,
      authorIdFallback: lastMessage['authorId']?.toString(),
    );
  }

  final base = switch (lastKind) {
    'IMAGE' => 'Photo',
    'FILE' => 'File',
    'VOICE_NOTE' => 'Voice note',
    'CALL_EVENT' => previewBody.isEmpty ? 'Call' : previewBody,
    'SYSTEM' => cleanBody,
    _ => cleanBody.isEmpty ? '' : cleanBody,
  };

  final lastAuthorId = lastMessage['authorId']?.toString();
  final author = (lastMessage['author'] as Map?)?.cast<String, dynamic>();
  final isMine = lastAuthorId != null && lastAuthorId == meId;
  if (lastKind == 'SYSTEM' || lastKind == 'CALL_EVENT' || base.isEmpty) {
    return base;
  }
  if (isMine) return 'You: $base';
  if (kind != 'DM') {
    final n = (author?['name'] ?? '').toString().trim();
    final first = n.isEmpty ? '' : n.split(' ').first;
    return first.isEmpty ? base : '$first: $base';
  }
  return base;
}

Map<String, dynamic>? _dmPeer(Map<String, dynamic> channel, String? meId) {
  final employee = (channel['employee'] as Map?)?.cast<String, dynamic>();
  if (employee != null) return employee;
  final members =
      (channel['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  for (final member in members) {
    if (meId != null && member['userId']?.toString() == meId) continue;
    final user = (member['user'] as Map?)?.cast<String, dynamic>();
    if (user != null) return user;
  }
  return null;
}

String _channelTitle(Map<String, dynamic> channel, String? meId) {
  final employee = (channel['employee'] as Map?)?.cast<String, dynamic>();
  if (employee != null) {
    final name =
        (employee['name'] ?? employee['userId'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
  }
  final kind = (channel['kind'] ?? 'GROUP').toString().toUpperCase();
  if (kind == 'DM') {
    final peer = _dmPeer(channel, meId);
    final name = (peer?['name'] ?? peer?['userId'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
  }
  final name = (channel['name'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  return kind == 'DM' ? 'Direct message' : 'Group chat';
}

String _presenceLabel(Map<String, dynamic>? user) {
  final presence = (user?['presence'] as Map?)?.cast<String, dynamic>();
  final custom = (presence?['customStatus'] ??
          user?['customStatus'] ??
          user?['presenceStatus'] ??
          '')
      .toString()
      .trim();
  if (custom.isNotEmpty) return custom;
  final status = (presence?['status'] ?? user?['status'] ?? '').toString();
  if (_isReallyOnline(user) && (status == 'ACTIVE' || status == 'ONLINE')) {
    return 'Online';
  }
  if (status == 'BUSY') return 'Busy';
  if (status == 'LUNCH') return 'Lunch Time';
  if (status == 'ON_CALL') return 'On a call';
  return 'Offline';
}

bool _isReallyOnline(Map<String, dynamic>? user) =>
    user?['online'] == true ||
    (((user?['presence'] as Map?)?.cast<String, dynamic>())?['online'] == true);
