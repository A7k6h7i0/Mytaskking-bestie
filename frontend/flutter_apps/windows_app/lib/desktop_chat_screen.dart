import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_mobile/chat_clear.dart';
import 'package:mytaskking_mobile/screens.dart'
    show ChatDetailScreen, CallSession;
import 'package:mytaskking_mobile/windows_workspace.dart';
import 'package:mytaskking_core/mytaskking_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _desktopChatDirectoryProvider =
    FutureProvider.family.autoDispose<List<Map<String, dynamic>>, String>(
  (ref, q) => ref.watch(apiProvider).listChannelDirectory(
        q: q.trim().isEmpty ? null : q.trim(),
      ),
);

class DesktopChatScreen extends ConsumerStatefulWidget {
  const DesktopChatScreen({super.key});

  @override
  ConsumerState<DesktopChatScreen> createState() => _DesktopChatScreenState();
}

class _DesktopChatScreenState extends ConsumerState<DesktopChatScreen> {
  String? _selectedChannelId;
  String _query = '';
  String _filter = 'All';
  int _chatDetailEpoch = 0;

  @override
  Widget build(BuildContext context) {
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
            ref.watch(_desktopChatDirectoryProvider(_query)).asData?.value ??
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
              ),
            ),
            VerticalDivider(width: 1, color: colors.border),
            Expanded(
              child: selected == null
                  ? _EmptyChat(colors: colors)
                  : Builder(builder: (context) {
                      final selectedChannel = selected!;
                      return Column(
                        children: [
                          _ConversationHeader(
                            channel: selectedChannel,
                            onVoice: () => _startCall(selectedChannel, 'voice'),
                            onVideo: () => _startCall(selectedChannel, 'video'),
                            onMore: () => _showChatOptionsMenu(selectedChannel),
                          ),
                          Divider(height: 1, color: colors.border),
                          Expanded(
                            child: ChatDetailScreen(
                              key: ValueKey(
                                '${_selectedChannelId!}_$_chatDetailEpoch',
                              ),
                              channelId: _selectedChannelId!,
                              hideHeader: true,
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
        setState(() => _selectedChannelId = channel['id']?.toString());
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
    setState(() => _selectedChannelId = row['id']?.toString());
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
          _preview(channel).toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) => _activityTime(b).compareTo(_activityTime(a)));
    return list;
  }

  Future<void> _showChatOptionsMenu(Map<String, dynamic> channel) async {
    final action = await showDialog<_ChatMenuAction>(
      context: context,
      builder: (ctx) => _ChatOptionsDialog(channel: channel),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ChatMenuAction.clearChat:
        await _clearChat(_selectedChannelId!);
      case _ChatMenuAction.createGroup:
        await _openCreateGroup(channel);
    }
  }

  Future<void> _clearChat(String channelId) async {
    final ok = await bestieConfirm(
      context,
      title: 'Clear chat?',
      description:
          'All messages in this chat will be removed from this device only. '
          'The other person will still have the full conversation.',
      confirmLabel: 'Clear chat',
    );
    if (!ok) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await markChatCleared(prefs, channelId);
      ref.invalidate(chatClearedAtProvider(channelId));
      if (!mounted) return;
      setState(() => _chatDetailEpoch++);
      bestieToast(context, 'Chat cleared', kind: BestieToastKind.success);
    } catch (err) {
      if (!mounted) return;
      bestieToast(
        context,
        'Could not clear chat',
        body: formatApiError(err),
        kind: BestieToastKind.error,
      );
    }
  }

  Future<void> _openCreateGroup(Map<String, dynamic> channel) async {
    final me = ref.read(authStoreProvider).user;
    final peer = _dmPeer(channel, me?.id);
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CreateGroupDialog(
        me: me,
        preselectedPeer: peer,
      ),
    );
    if (created == null || !mounted) return;
    ref.invalidate(channelsProvider);
    final id = created['id']?.toString();
    if (id != null) {
      setState(() {
        _selectedChannelId = id;
        _chatDetailEpoch++;
      });
      bestieToast(context, 'Group created', kind: BestieToastKind.success);
    }
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

class _ChatRail extends StatelessWidget {
  const _ChatRail({
    required this.channels,
    required this.selectedId,
    required this.query,
    required this.filter,
    required this.onQuery,
    required this.onFilter,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> channels;
  final String? selectedId;
  final String query;
  final String filter;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onFilter;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return ColoredBox(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 18, 10),
            child: Text(
              'Chat',
              style: TextStyle(
                color: c.text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              onChanged: onQuery,
              decoration: InputDecoration(
                hintText: 'Search users, groups or messages...',
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: const Icon(Icons.tune_rounded, size: 18),
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
            child: ListView.builder(
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
    final title = _channelTitle(channel, meId);
    final peer = _dmPeer(channel, meId);
    final presence = _presenceLabel(peer);
    final online = _isReallyOnline(peer);
    final unread = (channel['unreadCount'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? c.brandSoft.withValues(alpha: 0.75) : c.bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    BestieAvatar(
                      name: title,
                      imageUrl: peer?['avatarUrl']?.toString(),
                      size: 44,
                    ),
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
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
                            _timeLabel(_activityTime(channel)),
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
                        _preview(channel),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textMuted, fontSize: 12),
                      ),
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
                  ),
                ),
                if (unread > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.brand,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
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
}

enum _ChatMenuAction { clearChat, createGroup }

class _ConversationHeader extends ConsumerWidget {
  const _ConversationHeader({
    required this.channel,
    required this.onVoice,
    required this.onVideo,
    required this.onMore,
  });

  final Map<String, dynamic> channel;
  final VoidCallback onVoice;
  final VoidCallback onVideo;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final meId = ref.watch(authStoreProvider).user?.id;
    final peer = _dmPeer(channel, meId);
    final title = _channelTitle(channel, meId);
    final presence = _presenceLabel(peer);
    final online = _isReallyOnline(peer);
    return Container(
      height: 76,
      color: c.surface,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () {},
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          BestieAvatar(
            name: title,
            imageUrl: peer?['avatarUrl']?.toString(),
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
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
                  presence,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: online
                        ? c.success
                        : presence == 'Busy' ||
                                presence == 'Lunch Time' ||
                                presence == 'On a call'
                            ? c.warning
                            : c.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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

String _preview(Map<String, dynamic> channel) {
  if (channel['_entryType'] == 'employee') {
    final employee = (channel['employee'] as Map?)?.cast<String, dynamic>();
    final title = (employee?['customTitle'] ?? employee?['role'] ?? '')
        .toString()
        .replaceAll('_', ' ')
        .trim();
    return title.isEmpty ? 'Start a direct message' : title;
  }
  final last = (channel['lastMessage'] as Map?)?.cast<String, dynamic>();
  final body = (last?['body'] ?? '').toString().trim();
  if (body.isNotEmpty) return body;
  final kind = (last?['kind'] ?? '').toString();
  if (kind == 'FILE') return 'File';
  if (kind == 'IMAGE') return 'Photo';
  if (kind == 'VOICE_NOTE') return 'Voice note';
  return 'No messages yet';
}

DateTime _activityTime(Map<String, dynamic> channel) {
  final last = (channel['lastMessage'] as Map?)?.cast<String, dynamic>();
  return DateTime.tryParse(last?['createdAt']?.toString() ?? '') ??
      DateTime.tryParse(channel['updatedAt']?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

String _timeLabel(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour == 0
      ? 12
      : local.hour > 12
          ? local.hour - 12
          : local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

class _ChatOptionsDialog extends ConsumerWidget {
  const _ChatOptionsDialog({required this.channel});

  final Map<String, dynamic> channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final meId = ref.watch(authStoreProvider).user?.id;
    final title = _channelTitle(channel, meId);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: Icon(Icons.group_add_outlined, color: c.brand),
                title: const Text(
                  'Create new group',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Add this chat and more teammates',
                  style: TextStyle(fontSize: 12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onTap: () =>
                    Navigator.pop(context, _ChatMenuAction.createGroup),
              ),
              ListTile(
                leading: Icon(Icons.delete_sweep_outlined, color: c.danger),
                title: Text(
                  'Clear chat',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c.danger,
                  ),
                ),
                subtitle: const Text(
                  'Remove messages on this device only',
                  style: TextStyle(fontSize: 12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onTap: () => Navigator.pop(context, _ChatMenuAction.clearChat),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateGroupDialog extends ConsumerStatefulWidget {
  const _CreateGroupDialog({
    required this.me,
    this.preselectedPeer,
  });

  final BestieUser? me;
  final Map<String, dynamic>? preselectedPeer;

  @override
  ConsumerState<_CreateGroupDialog> createState() =>
      _CreateGroupDialogState();
}

class _CreateGroupDialogState extends ConsumerState<_CreateGroupDialog> {
  final _nameCtl = TextEditingController();
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  String? _error;
  bool _submitting = false;
  List<Map<String, dynamic>> _employees = const [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    final peerId = widget.preselectedPeer?['id']?.toString();
    if (peerId != null && peerId.isNotEmpty) {
      _selected.add(peerId);
    }
    unawaited(_fetch(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _fetch(String q) async {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final meId = widget.me?.id;
        final res = await ref.read(apiProvider).listEmployees(
              q: q.trim().isEmpty ? null : q.trim(),
            );
        if (!mounted) return;
        setState(() {
          _employees = res
              .where((e) => meId == null || e['id']?.toString() != meId)
              .toList();
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = formatApiError(e);
          _loading = false;
        });
      }
    });
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      bestieToast(
        context,
        'Select teammates',
        body: 'Pick at least one person for the group.',
        kind: BestieToastKind.warning,
      );
      return;
    }
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      bestieToast(
        context,
        'Group needs a name',
        body: 'Give it a short, descriptive title.',
        kind: BestieToastKind.warning,
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final channel = await ref.read(apiProvider).createChannel(
            kind: 'GROUP',
            name: name,
            memberIds: _selected.toList(),
          );
      if (!mounted) return;
      Navigator.pop(context, channel);
    } catch (e) {
      if (!mounted) return;
      bestieToast(
        context,
        'Could not create group',
        body: formatApiError(e),
        kind: BestieToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final meName = widget.me?.name ?? 'You';
    final peerName = (widget.preselectedPeer?['name'] ?? '').toString();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Create new group',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: c.textMuted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MemberChip(
                    label: meName,
                    subtitle: 'You',
                    avatarUrl: widget.me?.avatarUrl,
                    locked: true,
                  ),
                  if (widget.preselectedPeer != null)
                    _MemberChip(
                      label: peerName.isEmpty ? 'Contact' : peerName,
                      subtitle: 'From this chat',
                      avatarUrl:
                          widget.preselectedPeer?['avatarUrl']?.toString(),
                      locked: true,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                controller: _nameCtl,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Group name',
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
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _searchCtl,
                onChanged: _fetch,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search employees...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
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
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Add more teammates',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.textMuted,
                ),
              ),
            ),
            Expanded(
              child: _loading && _employees.isEmpty
                  ? const Center(child: BestieSpinner())
                  : _error != null && _employees.isEmpty
                      ? Center(
                          child: Text(
                            _error!,
                            style: TextStyle(color: c.danger),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          itemCount: _employees.length,
                          itemBuilder: (ctx, i) {
                            final user = _employees[i];
                            final id = user['id']?.toString() ?? '';
                            final selected = _selected.contains(id);
                            final isLockedPeer =
                                id == widget.preselectedPeer?['id']?.toString();
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: isLockedPeer
                                    ? null
                                    : () => setState(() {
                                          if (selected) {
                                            _selected.remove(id);
                                          } else {
                                            _selected.add(id);
                                          }
                                        }),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      BestieAvatar(
                                        name: (user['name'] ?? '—').toString(),
                                        imageUrl:
                                            user['avatarUrl']?.toString(),
                                        size: 36,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              (user['name'] ?? '—').toString(),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: c.text,
                                              ),
                                            ),
                                            Text(
                                              (user['customTitle'] ??
                                                      user['role'] ??
                                                      '')
                                                  .toString()
                                                  .replaceAll('_', ' '),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: c.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isLockedPeer)
                                        Text(
                                          'Included',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: c.brand,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        )
                                      else
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? c.brand
                                                : Colors.transparent,
                                            border: Border.all(
                                              color: selected
                                                  ? c.brand
                                                  : c.borderStrong,
                                              width: 1.5,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: selected
                                              ? const Icon(
                                                  Icons.check_rounded,
                                                  size: 14,
                                                  color: Colors.white,
                                                )
                                              : null,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: BestieSpinner(size: 16),
                        )
                      : const Icon(Icons.group_add_rounded, size: 18),
                  label: Text(
                    _selected.isEmpty
                        ? 'Create group'
                        : 'Create group · ${_selected.length}',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.label,
    required this.subtitle,
    this.avatarUrl,
    this.locked = false,
  });

  final String label;
  final String subtitle;
  final String? avatarUrl;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BestieAvatar(name: label, imageUrl: avatarUrl, size: 28),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 10, color: c.textMuted),
              ),
            ],
          ),
          if (locked) ...[
            const SizedBox(width: 6),
            Icon(Icons.lock_outline_rounded, size: 14, color: c.textMuted),
          ],
        ],
      ),
    );
  }
}
