import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_mobile/active_call_state.dart';
import 'package:mytaskking_mobile/screens/call_screen.dart';
import 'package:mytaskking_mobile/state.dart';

enum _CallTab { all, missed, outgoing, incoming }

enum _KindFilter { all, oneToOne, group }

/// Windows call history — matches the Calls Dashboard HTML layout.
/// Data from `GET /calls/history` (paginated).
class DesktopCallsScreen extends ConsumerStatefulWidget {
  const DesktopCallsScreen({super.key});

  @override
  ConsumerState<DesktopCallsScreen> createState() =>
      _DesktopCallsScreenState();
}

class _DesktopCallsScreenState extends ConsumerState<DesktopCallsScreen> {
  static const _pageSize = 25;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtl = TextEditingController();

  final List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  _CallTab _tab = _CallTab.all;
  _KindFilter _kindFilter = _KindFilter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.offset;
    if (remaining < 240 && _hasMore && !_loading) _loadMore();
  }

  Future<void> _refresh() async {
    _page = 1;
    _hasMore = true;
    _items.clear();
    await _loadMore();
  }

  Future<void> _loadMore() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(apiProvider)
          .callHistory(page: _page, pageSize: _pageSize);
      final batch =
          ((res['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _items.addAll(batch);
        _hasMore = batch.length >= _pageSize;
        if (_hasMore) _page++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _filtered(String? myId) {
    final q = _query.trim().toLowerCase();
    return _items.where((call) {
      final initiator =
          (call['initiator'] as Map?)?.cast<String, dynamic>() ?? const {};
      final outgoing = initiator['id']?.toString() == myId;
      final status = (call['status'] ?? '').toString().toUpperCase();
      final kind = (call['kind'] ?? 'ONE_TO_ONE').toString().toUpperCase();

      switch (_tab) {
        case _CallTab.missed:
          if (status != 'MISSED') return false;
          break;
        case _CallTab.outgoing:
          if (!outgoing) return false;
          break;
        case _CallTab.incoming:
          if (outgoing) return false;
          break;
        case _CallTab.all:
          break;
      }

      switch (_kindFilter) {
        case _KindFilter.oneToOne:
          if (kind != 'ONE_TO_ONE') return false;
          break;
        case _KindFilter.group:
          if (kind != 'GROUP') return false;
          break;
        case _KindFilter.all:
          break;
      }

      if (q.isEmpty) return true;
      final label = _participantLabel(
        myId: myId,
        initiator: initiator,
        participants: (call['participants'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            const [],
      ).toLowerCase();
      return label.contains(q) ||
          kind.toLowerCase().contains(q) ||
          status.toLowerCase().contains(q);
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(
    List<Map<String, dynamic>> calls,
  ) {
    final groups = <String, List<Map<String, dynamic>>>{};
    final order = <String>[];
    for (final call in calls) {
      final dt = _callDateTime(call);
      final key = _dateGroupLabel(dt);
      if (!groups.containsKey(key)) {
        groups[key] = [];
        order.add(key);
      }
      groups[key]!.add(call);
    }
    return {for (final k in order) k: groups[k]!};
  }

  Future<void> _showNewCallPicker() async {
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _NewCallPickerDialog(),
    );
    if (picked == null || !mounted) return;
    final userId = picked['id']?.toString();
    if (userId == null) return;
    await _ringBack(
      userId: userId,
      name: picked['name']?.toString() ?? 'Contact',
      mode: 'VIDEO',
    );
  }

  Future<void> _ringBack({
    required String userId,
    required String name,
    required String mode,
  }) async {
    try {
      await CallSession.prepareForNewCall();
      final res = await ref.read(apiProvider).initiateCall(
            participantIds: [userId],
            kind: 'ONE_TO_ONE',
            mode: mode.toUpperCase() == 'VOICE' ? 'VOICE' : 'VIDEO',
          );
      final id = ((res['call'] as Map?)?['id'] ?? res['id'])?.toString();
      if (id != null && mounted) {
        context.go('/call/$id?mode=${mode.toLowerCase()}');
      }
    } catch (e) {
      if (mounted) {
        bestieToast(
          context,
          'Could not start call',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authStoreProvider).user;
    final filtered = _filtered(me?.id);
    final grouped = _groupByDate(filtered);

    return ColoredBox(
      color: _CallsUi.bgPage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
            child: Row(
              children: [
                const Text(
                  'Calls',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: _CallsUi.textMain,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _showNewCallPicker,
                  style: FilledButton.styleFrom(
                    backgroundColor: _CallsUi.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    'New call',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _TabsRow(
            tab: _tab,
            onSelect: (t) => setState(() => _tab = t),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtl,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search by name, number or type...',
                      hintStyle: const TextStyle(color: _CallsUi.textLight),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: _CallsUi.textLight, size: 20),
                      filled: true,
                      fillColor: const Color(0xFFFBFBFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide:
                            const BorderSide(color: _CallsUi.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide:
                            const BorderSide(color: _CallsUi.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide:
                            const BorderSide(color: _CallsUi.primaryBlue),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                _FilterChipButton(
                  label: switch (_kindFilter) {
                    _KindFilter.all => 'All types',
                    _KindFilter.oneToOne => 'One to one',
                    _KindFilter.group => 'Group',
                  },
                  onSelected: (next) => setState(() => _kindFilter = next),
                  kindFilter: _kindFilter,
                ),
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty && _loading
                ? const Center(child: BestieSpinner())
                : _items.isEmpty && _error != null
                    ? Center(
                        child: BestieEmptyState(
                          icon: Icons.error_outline_rounded,
                          iconColor: _CallsUi.statusRed,
                          title: 'Could not load calls',
                          description: formatApiError(_error!),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: BestieEmptyState(
                              icon: Icons.phone_outlined,
                              title: _items.isEmpty
                                  ? 'No calls yet'
                                  : 'No calls match',
                              description: _items.isEmpty
                                  ? 'Voice and video calls will show up here.'
                                  : 'Try a different tab or search term.',
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            child: ListView(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
                              children: [
                                for (final entry in grouped.entries) ...[
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(top: 16, bottom: 12),
                                    child: Text(
                                      entry.key,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _CallsUi.textMuted,
                                      ),
                                    ),
                                  ),
                                  for (final call in entry.value)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _CallHistoryCard(
                                        call: call,
                                        myId: me?.id,
                                        myRole: me?.role,
                                        onRefresh: () => setState(() {}),
                                      ),
                                    ),
                                ],
                                if (_loading)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  )
                                else if (!_hasMore && _items.isNotEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: Text(
                                        'End of history',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _CallsUi.textLight,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _CallsUi {
  static const primaryBlue = Color(0xFF3B82F6);
  static const textMain = Color(0xFF1E293B);
  static const textMuted = Color(0xFF64748B);
  static const textLight = Color(0xFF94A3B8);
  static const borderColor = Color(0xFFE2E8F0);
  static const bgPage = Color(0xFFFFFFFF);
  static const statusRed = Color(0xFFEF4444);
  static const statusGreen = Color(0xFF22C55E);
}

class _TabsRow extends StatelessWidget {
  const _TabsRow({required this.tab, required this.onSelect});

  final _CallTab tab;
  final ValueChanged<_CallTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _CallsUi.borderColor)),
      ),
      child: Row(
        children: [
          _TabChip(
            label: 'All calls',
            active: tab == _CallTab.all,
            onTap: () => onSelect(_CallTab.all),
          ),
          _TabChip(
            label: 'Missed',
            active: tab == _CallTab.missed,
            onTap: () => onSelect(_CallTab.missed),
          ),
          _TabChip(
            label: 'Outgoing',
            active: tab == _CallTab.outgoing,
            onTap: () => onSelect(_CallTab.outgoing),
          ),
          _TabChip(
            label: 'Incoming',
            active: tab == _CallTab.incoming,
            onTap: () => onSelect(_CallTab.incoming),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 32),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? _CallsUi.primaryBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: active ? _CallsUi.primaryBlue : _CallsUi.textMuted,
          ),
        ),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.onSelected,
    required this.kindFilter,
  });

  final String label;
  final ValueChanged<_KindFilter> onSelected;
  final _KindFilter kindFilter;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_KindFilter>(
      initialValue: kindFilter,
      onSelected: onSelected,
      itemBuilder: (_) => const [
        PopupMenuItem(value: _KindFilter.all, child: Text('All types')),
        PopupMenuItem(value: _KindFilter.oneToOne, child: Text('One to one')),
        PopupMenuItem(value: _KindFilter.group, child: Text('Group')),
      ],
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: _CallsUi.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _CallsUi.textMain,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: _CallsUi.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallHistoryCard extends ConsumerWidget {
  const _CallHistoryCard({
    required this.call,
    required this.myId,
    required this.myRole,
    required this.onRefresh,
  });

  final Map<String, dynamic> call;
  final String? myId;
  final String? myRole;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initiator =
        (call['initiator'] as Map?)?.cast<String, dynamic>() ?? const {};
    final participants =
        (call['participants'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
    final outgoing = initiator['id']?.toString() == myId;
    final header = _headerPerson(
      myId: myId,
      initiator: initiator,
      participants: participants,
      outgoing: outgoing,
    );
    final name = _participantLabel(
      myId: myId,
      initiator: initiator,
      participants: participants,
    );
    final status = (call['status'] ?? 'ENDED').toString().toUpperCase();
    final kind = (call['kind'] ?? 'ONE_TO_ONE').toString();
    final duration = call['durationSeconds'] as int?;
    final viewerIsAdmin = myRole == 'ADMIN' || myRole == 'SUPER_ADMIN';
    final targetIsAdmin =
        header['role'] == 'ADMIN' || header['role'] == 'SUPER_ADMIN';
    final canCallBack = viewerIsAdmin || !targetIsAdmin;

    final myPart = _myParticipantRow(myId, participants);
    final userLeft = myPart?['leftAt'] != null;
    final isActive = status == 'ACTIVE';
    final showJoin = isActive && userLeft;
    final showReturn = isActive && !userLeft;

    final statusStyle = _statusStyle(outgoing, status);
    final subtitle = _statusSubtitle(
      outgoing: outgoing,
      kind: kind,
      status: status,
      durationSeconds: duration,
      showJoin: showJoin,
      showReturn: showReturn,
    );
    final timeLabel = _timeLabel(_callDateTime(call));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _CallsUi.borderColor),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x03000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          BestieAvatar(
            name: name == '—' ? '?' : name,
            imageUrl: header['avatarUrl']?.toString(),
            isClient: header['isClient'] == true,
            size: 40,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _CallsUi.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      statusStyle.icon,
                      size: 14,
                      color: statusStyle.color,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: statusStyle.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            timeLabel,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _CallsUi.textMuted,
            ),
          ),
          const SizedBox(width: 24),
          if (showJoin || showReturn)
            _RoundActionButton(
              icon: showJoin ? Icons.login_rounded : Icons.phone_in_talk_rounded,
              color: _CallsUi.statusGreen,
              onTap: () => showJoin
                  ? _joinCall(context, ref)
                  : _returnToCall(context),
            )
          else if (canCallBack) ...[
            _RoundActionButton(
              icon: Icons.videocam_outlined,
              color: _CallsUi.primaryBlue,
              onTap: () => _ringBack(context, ref, header['id']?.toString(), 'VIDEO'),
            ),
            const SizedBox(width: 12),
            _RoundActionButton(
              icon: Icons.call_rounded,
              color: _CallsUi.statusGreen,
              onTap: () => _ringBack(context, ref, header['id']?.toString(), 'VOICE'),
            ),
          ],
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: _CallsUi.textLight),
            onSelected: (value) {
              if (value == 'notes') _editNotes(context, ref);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'notes',
                child: Row(
                  children: [
                    Icon(
                      Icons.note_alt_outlined,
                      size: 18,
                      color: (call['notes'] ?? '').toString().trim().isNotEmpty
                          ? Colors.orange
                          : _CallsUi.textMuted,
                    ),
                    const SizedBox(width: 10),
                    const Text('Call notes'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _joinCall(BuildContext context, WidgetRef ref) async {
    final id = call['id']?.toString();
    if (id == null) return;
    try {
      if (CallSession.activeCallId == id && CallSession.engine != null) {
        CallSession.onCallScreen = true;
        CallSession.notifyRevision();
        if (context.mounted) context.go('/call/$id?mode=video');
        return;
      }
      await CallSession.prepareForNewCall();
      final joined = await ref.read(apiProvider).joinCall(id);
      _seedCallSessionFromHistory(
        joined,
        myId: ref.read(authStoreProvider).user?.id,
        callId: id,
      );
      CallSession.onCallScreen = true;
      CallSession.notifyRevision();
      if (context.mounted) context.go('/call/$id?mode=video');
    } catch (e) {
      if (context.mounted) {
        bestieToast(
          context,
          'Could not join call',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    }
  }

  void _returnToCall(BuildContext context) {
    final id = call['id']?.toString();
    if (id == null) return;
    CallSession.onCallScreen = true;
    CallSession.notifyRevision();
    context.go('/call/$id?mode=video');
  }

  Future<void> _ringBack(
    BuildContext context,
    WidgetRef ref,
    String? userId,
    String mode,
  ) async {
    if (userId == null) return;
    try {
      await CallSession.prepareForNewCall();
      final res = await ref.read(apiProvider).initiateCall(
            participantIds: [userId],
            kind: 'ONE_TO_ONE',
            mode: mode,
          );
      final id = ((res['call'] as Map?)?['id'] ?? res['id'])?.toString();
      if (id != null && context.mounted) {
        context.go('/call/$id?mode=${mode.toLowerCase()}');
      }
    } catch (e) {
      if (context.mounted) {
        bestieToast(
          context,
          'Could not call',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    }
  }

  Future<void> _editNotes(BuildContext context, WidgetRef ref) async {
    final id = call['id']?.toString();
    if (id == null) return;
    final controller =
        TextEditingController(text: (call['notes'] ?? '').toString());
    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Call notes'),
        content: TextField(
          controller: controller,
          minLines: 5,
          maxLines: 10,
          maxLength: 4000,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (notes == null) return;
    try {
      await ref.read(apiProvider).dio.patch('/calls/$id/notes', data: {
        'notes': notes,
      });
      call['notes'] = notes;
      onRefresh();
      if (context.mounted) {
        bestieToast(context, 'Call notes saved', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (context.mounted) {
        bestieToast(
          context,
          'Could not save notes',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    }
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(
        side: BorderSide(color: _CallsUi.borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

class _NewCallPickerDialog extends ConsumerStatefulWidget {
  const _NewCallPickerDialog();

  @override
  ConsumerState<_NewCallPickerDialog> createState() =>
      _NewCallPickerDialogState();
}

class _NewCallPickerDialogState extends ConsumerState<_NewCallPickerDialog> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _people = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load([String? q]) async {
    setState(() => _loading = true);
    try {
      final items = await ref.read(apiProvider).listEmployees(q: q);
      if (mounted) setState(() => _people = items);
    } catch (_) {
      if (mounted) setState(() => _people = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.read(authStoreProvider).user?.id;
    return AlertDialog(
      title: const Text('New call'),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _query,
              decoration: const InputDecoration(
                hintText: 'Search people…',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _load(v.trim().isEmpty ? null : v.trim()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      itemCount: _people.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _people[i];
                        if (p['id'] == me) return const SizedBox.shrink();
                        return ListTile(
                          leading: BestieAvatar(
                            name: p['name']?.toString() ?? '?',
                            imageUrl: p['avatarUrl']?.toString(),
                            isClient: p['isClient'] == true,
                            size: 32,
                          ),
                          title: BestieUserName(
                            name: p['name']?.toString() ?? '',
                            isClient: p['isClient'] == true,
                          ),
                          subtitle: Text(
                            p['role']?.toString().replaceAll('_', ' ') ?? '',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _StatusStyle {
  const _StatusStyle({required this.color, required this.icon});
  final Color color;
  final IconData icon;
}

_StatusStyle _statusStyle(bool outgoing, String status) {
  if (status == 'MISSED') {
    return const _StatusStyle(
      color: _CallsUi.statusRed,
      icon: Icons.call_missed_outgoing_rounded,
    );
  }
  if (outgoing && status != 'MISSED' && status != 'ENDED') {
    return const _StatusStyle(
      color: _CallsUi.statusGreen,
      icon: Icons.call_made_rounded,
    );
  }
  if (outgoing && (status == 'ENDED' || status == 'ACTIVE')) {
    return const _StatusStyle(
      color: _CallsUi.statusGreen,
      icon: Icons.call_made_rounded,
    );
  }
  return const _StatusStyle(
    color: _CallsUi.textMuted,
    icon: Icons.call_received_rounded,
  );
}

String _statusSubtitle({
  required bool outgoing,
  required String kind,
  required String status,
  required int? durationSeconds,
  required bool showJoin,
  required bool showReturn,
}) {
  if (showJoin) return 'Active group call · tap to join';
  if (showReturn) return 'Ongoing · tap to return';
  final direction = outgoing ? 'Outgoing' : 'Incoming';
  final statusLower = status.toLowerCase();
  final duration = _fmtDuration(durationSeconds);
  if (status == 'MISSED') {
    return '$direction · $kind · missed';
  }
  if (duration.isNotEmpty &&
      (status == 'ENDED' || status == 'ACTIVE' || status == 'DONE')) {
    if (status == 'ENDED') {
      return '$direction · $kind · ended · $duration';
    }
    return '$direction · $kind · $duration';
  }
  return '$direction · $kind · $statusLower';
}

String _fmtDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m > 0 && s > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  if (m > 0) return '${m}m';
  return '${s}s';
}

DateTime? _callDateTime(Map<String, dynamic> call) {
  return DateTime.tryParse(
        '${call['endedAt'] ?? call['startedAt'] ?? call['createdAt']}',
      )?.toLocal() ??
      DateTime.tryParse('${call['createdAt']}')?.toLocal();
}

String _dateGroupLabel(DateTime? dt) {
  if (dt == null) return 'Unknown date';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

String _timeLabel(DateTime? dt) {
  if (dt == null) return '—';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final hour = dt.hour == 0
      ? 12
      : dt.hour > 12
          ? dt.hour - 12
          : dt.hour;
  final minute = dt.minute.toString().padLeft(2, '0');
  final suffix = dt.hour >= 12 ? 'PM' : 'AM';
  final clock = '$hour:$minute $suffix';
  if (day == today) return clock;
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Yesterday, $clock';
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}, $clock';
}

String _participantLabel({
  required String? myId,
  required Map<String, dynamic> initiator,
  required List<Map<String, dynamic>> participants,
}) {
  final names = <String>[];
  void addName(String? raw) {
    final n = raw?.trim();
    if (n == null || n.isEmpty) return;
    if (!names.contains(n)) names.add(n);
  }

  for (final p in participants) {
    final uid = (p['userId'] ?? (p['user'] as Map?)?['id'])?.toString();
    if (uid == myId) continue;
    addName((p['user'] as Map?)?['name']?.toString());
  }
  if (initiator['id']?.toString() != myId) {
    addName(initiator['name']?.toString());
  }
  if (names.isEmpty) return '—';
  if (names.length == 1) return names.first;
  if (names.length == 2) return '${names[0]} & ${names[1]}';
  return '${names[0]}, ${names[1]} +${names.length - 2}';
}

Map<String, dynamic> _headerPerson({
  required String? myId,
  required Map<String, dynamic> initiator,
  required List<Map<String, dynamic>> participants,
  required bool outgoing,
}) {
  for (final p in participants) {
    final uid = (p['userId'] ?? (p['user'] as Map?)?['id'])?.toString();
    if (uid != null && uid != myId) {
      return (p['user'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
    }
  }
  if (!outgoing && initiator['id']?.toString() != myId) return initiator;
  if (participants.isNotEmpty) {
    return (participants.first['user'] as Map?)?.cast<String, dynamic>() ??
        initiator;
  }
  return initiator;
}

Map<String, dynamic>? _myParticipantRow(
  String? myId,
  List<Map<String, dynamic>> participants,
) {
  for (final p in participants) {
    final uid = (p['userId'] ?? (p['user'] as Map?)?['id'])?.toString();
    if (uid == myId) return p;
  }
  return null;
}

void _seedCallSessionFromHistory(
  Map<String, dynamic> joined, {
  required String? myId,
  required String callId,
}) {
  CallSession.callMeta = {'call': joined};
  final initiator =
      (joined['initiator'] as Map?)?.cast<String, dynamic>() ?? const {};
  final participants =
      (joined['participants'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
  final title = _participantLabel(
    myId: myId,
    initiator: initiator,
    participants: participants,
  );
  CallSession.remotePeerName = title == '—' ? 'Call' : title;
  ActiveCallState.start(
    callId: callId,
    meetingSlug: null,
    mode: 'video',
    title: CallSession.remotePeerName ?? 'Call',
  );
}
