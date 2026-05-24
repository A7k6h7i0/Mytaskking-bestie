import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Tasks home — single list view of every task the user can see, ordered by
/// most-recently-touched. Tapping a card pushes `/tasks/:id` for the
/// full-screen detail (no more bottom-sheet modal).
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});
  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  void Function()? _offAssigned;
  _TaskFilter _filter = _TaskFilter.all;
  final _searchCtl = TextEditingController();
  String _query = '';
  // Selection mode: when the user long-presses a task we flip into a
  // multi-select state with a contextual app bar and "Mark all done" /
  // "Cancel" actions. Stored as ids so toggling is O(1).
  final Set<String> _selectedIds = {};
  bool get _selecting => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Realtime toast when someone assigns me a task — connection is opened
    // lazily by the realtime provider, so we wait until after first paint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final me = ref.read(authStoreProvider).user;
      final rt = ref.read(realtimeProvider);
      _offAssigned = rt.on<Map>('task.assigned', (data) {
        if (!mounted || me == null) return;
        final task = (data['task'] as Map?)?.cast<String, dynamic>() ?? const {};
        final assignerName = data['assignerName'] ?? 'Someone';
        final assignees = (task['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final mine = assignees.any((a) => (a['user'] as Map?)?['id'] == me.id);
        if (!mine) return;
        final due = task['dueAt'] != null ? ' · due ${_fmt(task['dueAt'])}' : '';
        bestieToast(
          context,
          '$assignerName assigned you a task',
          body: '${task['title']}$due',
          kind: BestieToastKind.info,
        );
        ref.invalidate(tasksKanbanProvider);
        ref.invalidate(notificationsProvider);
      });
    });
  }

  @override
  void dispose() {
    _offAssigned?.call();
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final tasks = ref.watch(tasksKanbanProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: _selecting ? _selectionAppBar(c) : AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Tasks'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(tasksKanbanProvider.future),
        child: tasks.when(
          loading: () => const BestieSkeletonList(
            itemCount: 5,
            shape: BestieSkeletonShape.card,
          ),
          error: (e, _) => BestieEmptyState(
            icon: Icons.error_outline,
            iconColor: c.danger,
            title: 'Couldn\'t load tasks',
            description: formatApiError(e),
          ),
          data: (data) {
            // The provider still returns a kanban shape (columns keyed by
            // status) — flatten it for the list and sort by most-recent.
            final cols = (data['columns'] as Map?)?.cast<String, dynamic>() ?? const {};
            final all = cols.values
                .expand((v) => (v as List).cast<Map<String, dynamic>>())
                .toList();
            all.sort((a, b) => '${b['updatedAt']}'.compareTo('${a['updatedAt']}'));

            final me = ref.read(authStoreProvider).user;
            final counts = _countsFor(all, me?.id);
            var filtered = _applyFilter(all, _filter, me?.id);
            if (_query.isNotEmpty) {
              final q = _query.toLowerCase();
              filtered = filtered.where((t) =>
                ('${t['title'] ?? ''}').toLowerCase().contains(q) ||
                ('${t['description'] ?? ''}').toLowerCase().contains(q)
              ).toList();
            }

            if (all.isEmpty) {
              return BestieEmptyState(
                icon: Icons.task_alt,
                title: 'No tasks yet',
                description: 'Create one and assign it to anyone in the workspace.',
                action: FilledButton.icon(
                  onPressed: _newTask,
                  icon: const Icon(Icons.add),
                  label: const Text('New task'),
                ),
              );
            }

            return Column(
              children: [
                _searchBar(c),
                _filterRow(c, counts),
                Expanded(
                  child: filtered.isEmpty
                      ? BestieEmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          title: 'No tasks match',
                          description: 'Try a different filter or search term.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                          itemBuilder: (_, i) => _taskCard(filtered[i], c),
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemCount: filtered.length,
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTask,
        backgroundColor: BestieTokens.cBrand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New task'),
      ),
    );
  }

  Map<_TaskFilter, int> _countsFor(List<Map<String, dynamic>> all, String? meId) {
    final now = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;
    final out = {for (final f in _TaskFilter.values) f: 0};
    for (final t in all) {
      final status = (t['status'] ?? 'TODO').toString();
      final done = status == 'DONE' || status == 'CANCELLED';
      final assignees = (t['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final mine = meId != null && assignees.any((a) => (a['user'] as Map?)?['id'] == meId);
      final due = DateTime.tryParse('${t['dueAt']}')?.toLocal();
      out[_TaskFilter.all] = out[_TaskFilter.all]! + 1;
      if (mine && !done) out[_TaskFilter.mine] = out[_TaskFilter.mine]! + 1;
      if (due != null && isToday(due) && !done) {
        out[_TaskFilter.dueToday] = out[_TaskFilter.dueToday]! + 1;
      }
      if (due != null && due.isBefore(now) && !done) {
        out[_TaskFilter.overdue] = out[_TaskFilter.overdue]! + 1;
      }
      if (status == 'DONE') out[_TaskFilter.done] = out[_TaskFilter.done]! + 1;
    }
    return out;
  }

  List<Map<String, dynamic>> _applyFilter(
      List<Map<String, dynamic>> all, _TaskFilter f, String? meId) {
    if (f == _TaskFilter.all) return all;
    final now = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;
    return all.where((t) {
      final status = (t['status'] ?? 'TODO').toString();
      final done = status == 'DONE' || status == 'CANCELLED';
      final assignees = (t['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final mine = meId != null && assignees.any((a) => (a['user'] as Map?)?['id'] == meId);
      final due = DateTime.tryParse('${t['dueAt']}')?.toLocal();
      switch (f) {
        case _TaskFilter.mine:
          return mine && !done;
        case _TaskFilter.dueToday:
          return due != null && isToday(due) && !done;
        case _TaskFilter.overdue:
          return due != null && due.isBefore(now) && !done;
        case _TaskFilter.done:
          return status == 'DONE';
        case _TaskFilter.all:
          return true;
      }
    }).toList();
  }

  Widget _searchBar(BestieColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        controller: _searchCtl,
        textInputAction: TextInputAction.search,
        onChanged: (v) => setState(() => _query = v.trim()),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search tasks…',
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: c.textSoft),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchCtl.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: c.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BestieTokens.rPill),
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BestieTokens.rPill),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BestieTokens.rPill),
            borderSide: BorderSide(color: BestieTokens.cBrand),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _selectionAppBar(BestieColors c) {
    return AppBar(
      elevation: 0,
      backgroundColor: c.brandSoft,
      foregroundColor: c.brandStrong,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () => setState(_selectedIds.clear),
      ),
      title: Text('${_selectedIds.length} selected',
          style: TextStyle(color: c.brandStrong, fontWeight: BestieTokens.fwBold)),
      actions: [
        IconButton(
          icon: const Icon(Icons.check_circle_outline_rounded),
          tooltip: 'Mark as done',
          onPressed: _bulkMarkDone,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Future<void> _bulkMarkDone() async {
    final ids = _selectedIds.toList();
    setState(_selectedIds.clear);
    final api = ref.read(apiProvider);
    int ok = 0;
    int fail = 0;
    for (final id in ids) {
      try {
        // Sequential — bulk endpoints don't exist on the backend yet and
        // hitting them in parallel trips the per-route rate limiter.
        await api.updateTask(id, {'status': 'DONE'});
        ok += 1;
      } catch (_) { fail += 1; }
    }
    ref.invalidate(tasksKanbanProvider);
    if (mounted) {
      bestieToast(
        context,
        fail == 0 ? 'Marked $ok done' : 'Marked $ok · $fail failed',
        kind: fail == 0 ? BestieToastKind.success : BestieToastKind.warning,
      );
    }
  }

  Widget _filterRow(BestieColors c, Map<_TaskFilter, int> counts) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _TaskFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = _TaskFilter.values[i];
          final selected = _filter == f;
          final count = counts[f] ?? 0;
          return ChoiceChip(
            selected: selected,
            onSelected: (_) => setState(() => _filter = f),
            label: Text(count > 0 ? '${f.label} · $count' : f.label),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: BestieTokens.fwSemibold,
              color: selected ? Colors.white : c.textSoft,
            ),
            backgroundColor: c.surface,
            selectedColor: BestieTokens.cBrand,
            side: BorderSide(color: selected ? BestieTokens.cBrand : c.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BestieTokens.rPill)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        },
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> t, BestieColors c) {
    final priority = (t['priority'] as String? ?? 'MEDIUM').toLowerCase();
    final dueAt = t['dueAt'] as String?;
    final assignees = (t['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final me = ref.read(authStoreProvider).user;
    final mine = assignees.firstWhere(
      (a) => (a['user'] as Map?)?['id'] == me?.id,
      orElse: () => const {},
    );
    final myState = mine['state'] as String?;
    final myScore = mine['score'] is int ? mine['score'] as int : null;
    final status = (t['status'] ?? 'TODO').toString();

    final priorityColor = switch (priority) {
      'urgent' => c.danger,
      'high'   => c.warning,
      'medium' => c.info,
      _        => c.borderStrong,
    };

    final id = t['id'] as String;
    final selected = _selectedIds.contains(id);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(BestieTokens.rMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        onTap: () {
          if (_selecting) {
            setState(() {
              selected ? _selectedIds.remove(id) : _selectedIds.add(id);
            });
          } else {
            _openTask(id);
          }
        },
        onLongPress: () {
          // Long-press anywhere on a card flips into selection mode. Already-
          // selected cards become a no-op so a chain of long-presses doesn't
          // accidentally deselect.
          setState(() => _selectedIds.add(id));
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? c.brandSoft : c.surface,
            borderRadius: BorderRadius.circular(BestieTokens.rMd),
            border: Border.all(
              color: selected ? BestieTokens.cBrand : c.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // priority + status row
              Row(children: [
                Container(
                  width: 30, height: 4,
                  decoration: BoxDecoration(
                    color: priorityColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(BestieTokens.rPill),
                  ),
                  child: Text(
                    status.replaceAll('_', ' '),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: BestieTokens.fwBold,
                      color: c.textSoft,
                      letterSpacing: BestieTokens.lsWide,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, color: c.textFaint, size: 18),
              ]),
              const SizedBox(height: 8),
              Text(
                t['title'] ?? '',
                style: TextStyle(
                  fontWeight: BestieTokens.fwSemibold,
                  fontSize: 15,
                  color: c.text,
                  height: 1.3,
                ),
              ),
              if ((t['description'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  t['description'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.35),
                ),
              ],
              if (myState != null) ...[
                const SizedBox(height: 10),
                _stateBadge(myState, myScore),
              ],
              const SizedBox(height: 10),
              Row(children: [
                if (assignees.isNotEmpty)
                  SizedBox(
                    height: 24,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var i = 0; i < assignees.take(3).length; i++)
                          Positioned(
                            left: i * 16.0,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: c.surface, width: 2),
                              ),
                              child: BestieAvatar(
                                name: (assignees[i]['user'] as Map?)?['name']?.toString() ?? '?',
                                imageUrl: (assignees[i]['user'] as Map?)?['avatarUrl']?.toString(),
                                isClient: (assignees[i]['user'] as Map?)?['isClient'] ?? false,
                                size: 24,
                              ),
                            ),
                          ),
                        if (assignees.length > 3)
                          Positioned(
                            left: 3 * 16.0,
                            child: Container(
                              width: 24, height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c.surface2,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.surface, width: 2),
                              ),
                              child: Text(
                                '+${assignees.length - 3}',
                                style: TextStyle(
                                  fontSize: 9, color: c.textSoft,
                                  fontWeight: BestieTokens.fwBold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (dueAt != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.warningSoft,
                      borderRadius: BorderRadius.circular(BestieTokens.rPill),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.schedule_rounded, size: 12, color: c.warning),
                      const SizedBox(width: 4),
                      Text(
                        _fmt(dueAt),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: BestieTokens.fwSemibold,
                          color: c.warning,
                        ),
                      ),
                    ]),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stateBadge(String state, int? score) {
    switch (state) {
      case 'PENDING':
        return const BestieBadge(tone: BestieTone.warning, dot: true, child: Text('AWAITING ACCEPT'));
      case 'ACCEPTED':
        return const BestieBadge(tone: BestieTone.brand, dot: true, child: Text('ACCEPTED'));
      case 'DECLINED':
        return const BestieBadge(tone: BestieTone.danger, dot: true, child: Text('DECLINED'));
      case 'COMPLETED':
        final tone = score == null
            ? BestieTone.success
            : (score >= 80 ? BestieTone.success : score >= 50 ? BestieTone.warning : BestieTone.danger);
        return BestieBadge(tone: tone, dot: true, child: Text(score == null ? 'COMPLETED' : 'COMPLETED · $score/100'));
      default:
        return const SizedBox.shrink();
    }
  }

  void _openTask(String taskId) {
    // Full-screen detail with a real back button instead of a bottom sheet.
    context.push('/tasks/$taskId');
  }

  String _fmt(dynamic iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '$iso';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, $h:$m';
  }

  Future<void> _newTask() async {
    await bestieBottomSheet<void>(
      context,
      title: 'New task',
      builder: (ctx) => _NewTaskSheet(ref: ref),
    );
  }
}

enum _TaskFilter {
  all('All'),
  mine('Mine'),
  dueToday('Due today'),
  overdue('Overdue'),
  done('Done');

  final String label;
  const _TaskFilter(this.label);
}

// ─────────────────────────────────────────────────────────────────────────────
// Full create sheet: title + description + priority + date + time + assignees
// ─────────────────────────────────────────────────────────────────────────────

class _NewTaskSheet extends StatefulWidget {
  final WidgetRef ref;
  const _NewTaskSheet({required this.ref});
  @override
  State<_NewTaskSheet> createState() => _NewTaskSheetState();
}

class _NewTaskSheetState extends State<_NewTaskSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _peopleQuery = TextEditingController();

  String _priority = 'MEDIUM';
  DateTime? _due;
  final List<Map<String, dynamic>> _picked = [];
  bool _submitting = false;
  List<Map<String, dynamic>> _people = [];

  @override
  void initState() {
    super.initState();
    final tomorrowFive = DateTime.now().add(const Duration(days: 1));
    _due = DateTime(tomorrowFive.year, tomorrowFive.month, tomorrowFive.day, 17, 0);
    _loadPeople();
  }

  Future<void> _loadPeople([String? q]) async {
    try {
      final items = await widget.ref.read(apiProvider).listEmployees(q: q);
      if (mounted) setState(() => _people = items);
    } catch (_) {
      // swallow — empty suggestion list is fine
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      initialDate: _due ?? DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _due = DateTime(picked.year, picked.month, picked.day, _due?.hour ?? 17, _due?.minute ?? 0));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _due?.hour ?? 17, minute: _due?.minute ?? 0),
    );
    if (picked == null) return;
    final base = _due ?? DateTime.now();
    setState(() => _due = DateTime(base.year, base.month, base.day, picked.hour, picked.minute));
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      // We hit the raw API here instead of the helper because the helper's
      // signature doesn't take `dueAt`; the backend honors it directly.
      await widget.ref.read(apiProvider).post('/tasks', body: {
        'title': _title.text.trim(),
        if (_desc.text.trim().isNotEmpty) 'description': _desc.text.trim(),
        'priority': _priority,
        'status': 'TODO',
        'assigneeIds': _picked.map((p) => p['id'] as String).toList(),
        if (_due != null) 'dueAt': _due!.toUtc().toIso8601String(),
      });
      widget.ref.invalidate(tasksKanbanProvider);
      if (mounted) {
        final count = _picked.length;
        bestieToast(
          context,
          count == 0 ? 'Task created' : 'Assigned to $count ${count == 1 ? 'person' : 'people'}',
          body: _due != null ? 'Due ${_fmt(_due!)}' : null,
          kind: BestieToastKind.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) bestieToast(context, 'Could not create', body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _fmt(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final pickedIds = _picked.map((p) => p['id']).toSet();
    final candidates = _people.where((p) => !pickedIds.contains(p['id'])).take(8).toList();
    final me = widget.ref.read(authStoreProvider).user;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        BestieTokens.s4, 0, BestieTokens.s4,
        MediaQuery.of(context).viewInsets.bottom + BestieTokens.s4,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          BestieTextField(label: 'Title', controller: _title, hint: 'What needs to happen?'),
          const SizedBox(height: BestieTokens.s2),

          BestieTextField(label: 'Description (optional)', controller: _desc),
          const SizedBox(height: BestieTokens.s2),

          // ----- priority -----
          const Text('Priority',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BestieTokens.cTextSoft)),
          const SizedBox(height: 6),
          BestieSegmentedControl<String>(
            value: _priority,
            onChanged: (v) => setState(() => _priority = v),
            options: const [
              BestieSegmentOption(value: 'LOW',    label: 'Low'),
              BestieSegmentOption(value: 'MEDIUM', label: 'Medium'),
              BestieSegmentOption(value: 'HIGH',   label: 'High'),
              BestieSegmentOption(value: 'URGENT', label: 'Urgent'),
            ],
          ),
          const SizedBox(height: BestieTokens.s3),

          // ----- date + time pickers -----
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                onPressed: _pickDate,
                label: Text(_due != null
                    ? '${_due!.year}-${_due!.month.toString().padLeft(2, '0')}-${_due!.day.toString().padLeft(2, '0')}'
                    : 'Pick a date'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 16),
                onPressed: _pickTime,
                label: Text(_due != null
                    ? '${_due!.hour.toString().padLeft(2, '0')}:${_due!.minute.toString().padLeft(2, '0')}'
                    : 'Pick a time'),
              ),
            ),
          ]),
          if (_due != null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Pings 15 min, 5 min, and at the deadline — then every 30 min while overdue.',
                style: TextStyle(color: BestieTokens.cTextMuted, fontSize: 12),
              ),
            ),
          const SizedBox(height: BestieTokens.s3),

          // ----- assignees -----
          const Text('Assign to',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BestieTokens.cTextSoft)),
          if (_picked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6, runSpacing: 6,
                children: _picked.map((p) => InputChip(
                  avatar: BestieAvatar(name: p['name'] ?? '?', imageUrl: p['avatarUrl'], isClient: p['isClient'] ?? false, size: 18),
                  label: BestieUserName(name: p['name'] ?? '', isClient: p['isClient'] ?? false,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  onDeleted: () => setState(() => _picked.removeWhere((x) => x['id'] == p['id'])),
                )).toList(),
              ),
            ),
          const SizedBox(height: 6),
          BestieTextField(
            label: 'Search people',
            controller: _peopleQuery,
            icon: Icons.search,
            onChanged: (v) => _loadPeople(v),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: candidates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = candidates[i];
                final isMe = me?.id == p['id'];
                return ListTile(
                  dense: true,
                  leading: BestieAvatar(name: p['name'] ?? '?', imageUrl: p['avatarUrl'], isClient: p['isClient'] ?? false, size: 28),
                  title: BestieUserName(name: p['name'] ?? '', isClient: p['isClient'] ?? false,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${p['userId']} · ${p['role']?.toString().replaceAll('_', ' ') ?? ''}',
                    style: const TextStyle(color: BestieTokens.cTextMuted, fontSize: 12),
                  ),
                  trailing: isMe
                      ? const BestieBadge(child: Text('YOU'))
                      : const Icon(Icons.add, size: 16),
                  onTap: () {
                    setState(() {
                      _picked.add(p);
                      _peopleQuery.clear();
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: BestieTokens.s4),

          BestiePrimaryButton(
            label: _picked.isEmpty ? 'Create' : 'Create + notify',
            icon: Icons.send,
            onPressed: _submit,
            loading: _submitting,
          ),
        ],
      ),
    );
  }
}
