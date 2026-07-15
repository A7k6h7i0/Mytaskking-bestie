import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

String? _assigneeRecordUserId(Map<String, dynamic> assignee) {
  final nested = (assignee['user'] as Map?)?['id']?.toString();
  if (nested != null && nested.isNotEmpty) return nested;
  return assignee['userId']?.toString();
}

bool _isAssignedToMe(Map<String, dynamic> task, String? meId) {
  if (meId == null) return false;
  final assignees =
      (task['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  return assignees.any((a) => _assigneeRecordUserId(a) == meId);
}

Map<String, dynamic>? _myAssignment(Map<String, dynamic> task, String? meId) {
  if (meId == null) return null;
  final assignees =
      (task['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  for (final a in assignees) {
    if (_assigneeRecordUserId(a) == meId) return a;
  }
  return null;
}

/// Tasks home — single list view of every task the user can see, ordered by
/// most-recently-touched. Tapping a card pushes `/tasks/:id` for the
/// full-screen detail (no more bottom-sheet modal).
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});
  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen>
    with WidgetsBindingObserver {
  void Function()? _offAssigned;
  void Function()? _offAutoPromoted;
  _TaskFilter _filter = _TaskFilter.all;
  final _searchCtl = TextEditingController();
  String _query = '';
  String? _priorityToastKey;
  // Selection mode: when the user long-presses a task we flip into a
  // multi-select state with a contextual app bar and "Mark all done" /
  // "Cancel" actions. Stored as ids so toggling is O(1).
  final Set<String> _selectedIds = {};
  bool get _selecting => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Realtime toast when someone assigns me a task — connection is opened
    // lazily by the realtime provider, so we wait until after first paint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(tasksKanbanProvider);
      final me = ref.read(authStoreProvider).user;
      final rt = ref.read(realtimeProvider);
      _offAssigned = rt.on<Map>('task.assigned', (data) {
        if (!mounted || me == null) return;
        final task =
            (data['task'] as Map?)?.cast<String, dynamic>() ?? const {};
        final assignerName = data['assignerName'] ?? 'Someone';
        final assignees =
            (task['assignees'] as List?)?.cast<Map<String, dynamic>>() ??
                const [];
        final mine = assignees.any((a) => _assigneeRecordUserId(a) == me.id);
        if (!mine) return;
        final due =
            task['dueAt'] != null ? ' · due ${_fmt(task['dueAt'])}' : '';
        bestieToast(
          context,
          '$assignerName assigned you a task',
          body: '${task['title']}$due',
          kind: BestieToastKind.info,
        );
        ref.invalidate(tasksKanbanProvider);
        ref.invalidate(notificationsProvider);
      });
      _offAutoPromoted = rt.on<Map>('task.auto_promoted', (data) {
        if (!mounted) return;
        final task =
            (data['task'] as Map?)?.cast<String, dynamic>() ?? const {};
        bestieToast(
          context,
          '${task['title'] ?? 'Next task'} moved to In progress',
          body: '${task['priority'] ?? 'Next'} priority is next in your queue.',
          kind: BestieToastKind.info,
        );
        ref.invalidate(tasksKanbanProvider);
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offAssigned?.call();
    _offAutoPromoted?.call();
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(tasksKanbanProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final tasks = ref.watch(tasksKanbanProvider);

    // Clear the shell nav without an empty Scaffold bottom bar (white strip).
    final shellNavClearance =
        70.0 + 24 + MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: c.surface,
      appBar: _selecting
          ? _selectionAppBar(c)
          : AppBar(
              elevation: 0,
              backgroundColor: c.surface,
              foregroundColor: c.text,
              title: const Text('Tasks'),
            ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(tasksKanbanProvider.future),
        child: tasks.when(
          loading: () => BestieSkeletonList(
            itemCount: 5,
            shape: BestieSkeletonShape.card,
            padding: EdgeInsets.fromLTRB(12, 8, 12, shellNavClearance),
          ),
          error: (e, _) => bestieEmptyScrollable(
            context,
            BestieEmptyState(
              icon: Icons.error_outline,
              iconColor: c.danger,
              title: 'Couldn\'t load tasks',
              description: formatApiError(e),
            ),
          ),
          data: (data) {
            final all = flattenTasksResponse(data);
            all.sort(
                (a, b) => '${b['updatedAt']}'.compareTo('${a['updatedAt']}'));

            final me = ref.read(authStoreProvider).user;
            final counts = _countsFor(all, me?.id);
            var filtered = _applyFilter(all, _filter, me?.id);
            if (_query.isNotEmpty) {
              final q = _query.toLowerCase();
              filtered = filtered
                  .where((t) =>
                      ('${t['title'] ?? ''}').toLowerCase().contains(q) ||
                      ('${t['description'] ?? ''}').toLowerCase().contains(q))
                  .toList();
            }
            _showPriorityToastFor(all, me?.id);

            final assignedPending = all.where((t) {
              final status = (t['status'] ?? 'TODO').toString();
              if (status == 'DONE' || status == 'CANCELLED') return false;
              final mine = _myAssignment(t, me?.id);
              return mine != null && mine['state']?.toString() == 'PENDING';
            }).toList();
            // Hide pending-accept block on due/overdue filters so it doesn't
            // sit above the "no tasks" empty state (user sees both).
            final showAssignedPending = assignedPending.isNotEmpty &&
                (_filter == _TaskFilter.all || _filter == _TaskFilter.mine);
            final pendingIds = showAssignedPending
                ? assignedPending.map((t) => t['id']?.toString()).toSet()
                : <String?>{};
            if (pendingIds.isNotEmpty) {
              filtered = filtered
                  .where((t) => !pendingIds.contains(t['id']?.toString()))
                  .toList();
            }

            if (all.isEmpty) {
              return bestieEmptyScrollable(
                context,
                BestieEmptyState(
                  icon: Icons.task_alt,
                  title: 'No tasks yet',
                  description:
                      'Create one and assign it to anyone in the workspace.',
                  action: FilledButton.icon(
                    onPressed: _newTask,
                    icon: const Icon(Icons.add),
                    label: const Text('New task'),
                  ),
                ),
              );
            }

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _searchBar(c)),
                SliverToBoxAdapter(child: _filterRow(c, counts)),
                if (showAssignedPending) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'ASSIGNED TO YOU',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: BestieTokens.fwBold,
                          color: c.textMuted,
                          letterSpacing: BestieTokens.lsEyebrow,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    sliver: SliverList.separated(
                      itemCount: assignedPending.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _taskCard(assignedPending[i], c),
                    ),
                  ),
                ],
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: BestieEmptyState(
                      icon: Icons.filter_alt_off_outlined,
                      title: switch (_filter) {
                        _TaskFilter.mine => 'No tasks assigned to you',
                        _TaskFilter.dueToday => 'No tasks due today',
                        _TaskFilter.overdue => 'No overdue tasks',
                        _TaskFilter.done => 'No completed tasks',
                        _ => 'No tasks match',
                      },
                      description: switch (_filter) {
                        _TaskFilter.mine =>
                          'Tasks assigned to you will appear here.',
                        _TaskFilter.dueToday => 'Nothing is due today.',
                        _TaskFilter.overdue =>
                          'You\'re all caught up — no overdue tasks.',
                        _TaskFilter.done =>
                          'Completed tasks will show here.',
                        _ => 'Try a different filter or search term.',
                      },
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(12, 4, 12, shellNavClearance),
                    sliver: SliverList.separated(
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
      floatingActionButton: _selecting
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: shellNavClearance - 24),
              child: FloatingActionButton.extended(
                onPressed: _newTask,
                backgroundColor: c.brand,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New task'),
              ),
            ),
    );
  }

  void _showPriorityToastFor(List<Map<String, dynamic>> all, String? meId) {
    if (meId == null) return;
    final task = _pickPriorityTaskForMe(all, meId);
    if (task == null) return;
    final priority = task['priority']?.toString() ?? '';
    if (priority != 'URGENT' && priority != 'HIGH') return;
    final key = '${task['id']}:${task['status']}';
    if (_priorityToastKey == key) return;
    _priorityToastKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bestieToast(
        context,
        '${task['title']} is $priority',
        body: 'Please try to complete it first.',
        kind: BestieToastKind.warning,
      );
    });
  }

  Map<String, dynamic>? _pickPriorityTaskForMe(
      List<Map<String, dynamic>> all, String meId) {
    final open = all.where((t) {
      final status = (t['status'] ?? 'TODO').toString();
      if (!['IN_PROGRESS', 'REVIEW', 'TODO'].contains(status)) return false;
      final assignees =
          (t['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      return assignees.any((a) {
        final state = a['state']?.toString();
        return _assigneeRecordUserId(a) == meId &&
            state != 'COMPLETED' &&
            state != 'DECLINED';
      });
    }).toList();
    const weights = {'URGENT': 0, 'HIGH': 1, 'MEDIUM': 2, 'LOW': 3};
    open.sort((a, b) {
      final byPriority =
          (weights[a['priority']] ?? 99) - (weights[b['priority']] ?? 99);
      if (byPriority != 0) return byPriority;
      final aDue =
          DateTime.tryParse('${a['dueAt']}')?.millisecondsSinceEpoch ?? 1 << 62;
      final bDue =
          DateTime.tryParse('${b['dueAt']}')?.millisecondsSinceEpoch ?? 1 << 62;
      return aDue.compareTo(bDue);
    });
    return open.isEmpty ? null : open.first;
  }

  DateTime? _dueDateOnly(dynamic dueAt) {
    final due = DateTime.tryParse('$dueAt')?.toLocal();
    if (due == null) return null;
    return DateTime(due.year, due.month, due.day);
  }

  Map<_TaskFilter, int> _countsFor(
      List<Map<String, dynamic>> all, String? meId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = {for (final f in _TaskFilter.values) f: 0};
    for (final t in all) {
      final status = (t['status'] ?? 'TODO').toString();
      final done = status == 'DONE' || status == 'CANCELLED';
      final mine = meId != null && _isAssignedToMe(t, meId);
      final due = DateTime.tryParse('${t['dueAt']}')?.toLocal();
      final dueDay = due == null ? null : DateTime(due.year, due.month, due.day);
      out[_TaskFilter.all] = out[_TaskFilter.all]! + 1;
      if (mine && !done) out[_TaskFilter.mine] = out[_TaskFilter.mine]! + 1;
      // Due today: same calendar day and not yet past the due time (or all-day).
      if (dueDay != null && dueDay == today && !done && !due!.isBefore(now)) {
        out[_TaskFilter.dueToday] = out[_TaskFilter.dueToday]! + 1;
      }
      // Overdue: past due datetime (includes earlier today).
      if (due != null && due.isBefore(now) && !done) {
        out[_TaskFilter.overdue] = out[_TaskFilter.overdue]! + 1;
      }
      final myDone = meId != null &&
          _myAssignment(t, meId)?['state']?.toString() == 'COMPLETED';
      if (status == 'DONE' || myDone) {
        out[_TaskFilter.done] = out[_TaskFilter.done]! + 1;
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _applyFilter(
      List<Map<String, dynamic>> all, _TaskFilter f, String? meId) {
    if (f == _TaskFilter.all) return all;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return all.where((t) {
      final status = (t['status'] ?? 'TODO').toString();
      final done = status == 'DONE' || status == 'CANCELLED';
      final mine = meId != null && _isAssignedToMe(t, meId);
      final due = DateTime.tryParse('${t['dueAt']}')?.toLocal();
      final dueDay = due == null ? null : DateTime(due.year, due.month, due.day);
      switch (f) {
        case _TaskFilter.mine:
          return mine && !done;
        case _TaskFilter.dueToday:
          return dueDay != null &&
              dueDay == today &&
              !done &&
              !due!.isBefore(now);
        case _TaskFilter.overdue:
          return due != null && due.isBefore(now) && !done;
        case _TaskFilter.done:
          // Show full DONE tasks or tasks I personally completed (others may
          // still be pending — user expects to see their completion here).
          final myDone = meId != null &&
              _myAssignment(t, meId)?['state']?.toString() == 'COMPLETED';
          return status == 'DONE' || myDone;
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            borderSide: BorderSide(color: c.brand),
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
          style:
              TextStyle(color: c.brandStrong, fontWeight: BestieTokens.fwBold)),
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
      } catch (_) {
        fail += 1;
      }
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
            selectedColor: c.brand,
            side: BorderSide(color: selected ? c.brand : c.border),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BestieTokens.rPill)),
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
    final assignees =
        (t['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final me = ref.read(authStoreProvider).user;
    final mine = _myAssignment(t, me?.id) ?? const {};
    final myState = mine['state'] as String?;
    final myScore = mine['score'] is int ? mine['score'] as int : null;
    final status = (t['status'] ?? 'TODO').toString();
    final createdBy = (t['createdBy'] as Map?)?.cast<String, dynamic>();
    final assignerName = (createdBy?['name'] ?? '').toString().trim();

    final priorityColor = switch (priority) {
      'urgent' => c.danger,
      'high' => c.warning,
      'medium' => c.info,
      _ => c.borderStrong,
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
              color: selected ? c.brand : c.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // priority + status row
              Row(children: [
                Container(
                  width: 30,
                  height: 4,
                  decoration: BoxDecoration(
                    color: priorityColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                  style:
                      TextStyle(color: c.textMuted, fontSize: 13, height: 1.35),
                ),
              ],
              if (assignerName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.assignment_ind_outlined,
                        size: 14, color: c.textMuted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Assigned by $assignerName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 12,
                          fontWeight: BestieTokens.fwSemibold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (myState != null) ...[
                const SizedBox(height: 10),
                _stateBadge(myState, myScore),
              ],
              const SizedBox(height: 10),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (assignees.isNotEmpty) ...[
                      Builder(builder: (context) {
                        final slots = assignees.length > 3
                            ? 4
                            : assignees.length.clamp(1, 3);
                        final stackWidth = 24.0 + (slots - 1) * 16.0;
                        return SizedBox(
                          height: 24,
                          width: stackWidth,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (var i = 0; i < assignees.take(3).length; i++)
                                Positioned(
                                  left: i * 16.0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: c.surface, width: 2),
                                    ),
                                    child: BestieAvatar(
                                      name: (assignees[i]['user']
                                                  as Map?)?['name']
                                              ?.toString() ??
                                          '?',
                                      imageUrl: (assignees[i]['user']
                                              as Map?)?['avatarUrl']
                                          ?.toString(),
                                      isClient: (assignees[i]['user']
                                              as Map?)?['isClient'] ??
                                          false,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              if (assignees.length > 3)
                                Positioned(
                                  left: 3 * 16.0,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: c.surface2,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: c.surface, width: 2),
                                    ),
                                    child: Text(
                                      '+${assignees.length - 3}',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: c.textSoft,
                                        fontWeight: BestieTokens.fwBold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                    if (dueAt != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.warningSoft,
                          borderRadius:
                              BorderRadius.circular(BestieTokens.rPill),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.schedule_rounded,
                              size: 12, color: c.warning),
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
        return const BestieBadge(
            tone: BestieTone.warning,
            dot: true,
            child: Text('AWAITING ACCEPT'));
      case 'ACCEPTED':
        return const BestieBadge(
            tone: BestieTone.brand, dot: true, child: Text('ACCEPTED'));
      case 'DECLINED':
        return const BestieBadge(
            tone: BestieTone.danger, dot: true, child: Text('DECLINED'));
      case 'COMPLETED':
        final tone = score == null
            ? BestieTone.success
            : (score >= 80
                ? BestieTone.success
                : score >= 50
                    ? BestieTone.warning
                    : BestieTone.danger);
        return BestieBadge(
            tone: tone,
            dot: true,
            child:
                Text(score == null ? 'COMPLETED' : 'COMPLETED · $score/100'));
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
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
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
  DateTime? _scheduledAt;
  final List<Map<String, dynamic>> _picked = [];
  bool _submitting = false;
  List<Map<String, dynamic>> _people = [];

  @override
  void initState() {
    super.initState();
    final tomorrowFive = DateTime.now().add(const Duration(days: 1));
    _due = DateTime(
        tomorrowFive.year, tomorrowFive.month, tomorrowFive.day, 17, 0);
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
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      firstDate: todayStart,
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      initialDate:
          (_due != null && !_due!.isBefore(todayStart)) ? _due! : todayStart,
    );
    if (picked == null) return;
    setState(() => _due = DateTime(picked.year, picked.month, picked.day,
        _due?.hour ?? 17, _due?.minute ?? 0));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _due?.hour ?? 17, minute: _due?.minute ?? 0),
    );
    if (picked == null) return;
    final base = _due ?? DateTime.now();
    final next = DateTime(
        base.year, base.month, base.day, picked.hour, picked.minute);
    if (next.isBefore(DateTime.now())) {
      if (mounted) {
        bestieToast(
          context,
          'Time must be in the future',
          body: 'Pick a later time for today, or choose a future date.',
          kind: BestieToastKind.warning,
        );
      }
      return;
    }
    setState(() => _due = next);
  }

  /// Two-step date + time picker for "deliver to assignee at" — when set,
  /// the task is hidden from the assignee until that moment and the
  /// backend cron triggers the assignment notification at exactly that
  /// time. Default to 1 hour in the future.
  Future<void> _pickScheduledAt() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final initial = _scheduledAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      firstDate: todayStart,
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDate: initial.isBefore(todayStart) ? todayStart : initial,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (time == null) return;
    final scheduled =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (scheduled.isBefore(now)) {
      if (mounted) {
        bestieToast(
          context,
          'Schedule must be in the future',
          body: 'Pick a present or future date and time.',
          kind: BestieToastKind.warning,
        );
      }
      return;
    }
    setState(() => _scheduledAt = scheduled);
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) return;
    if (_picked.isEmpty) {
      bestieToast(
        context,
        'Assign someone',
        body: 'Pick at least one person before creating this task.',
        kind: BestieToastKind.warning,
      );
      return;
    }
    if (_due != null && _due!.isBefore(DateTime.now())) {
      bestieToast(
        context,
        'Time must be in the future',
        body: 'Pick a later due date and time.',
        kind: BestieToastKind.warning,
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.ref.read(apiProvider).post('/tasks', body: {
        'title': _title.text.trim(),
        if (_desc.text.trim().isNotEmpty) 'description': _desc.text.trim(),
        'priority': _priority,
        'status': 'TODO',
        'assigneeIds': _picked.map((p) => p['id'] as String).toList(),
        if (_due != null) 'dueAt': _due!.toUtc().toIso8601String(),
        if (_scheduledAt != null)
          'scheduledAt': _scheduledAt!.toUtc().toIso8601String(),
      });
      widget.ref.invalidate(tasksKanbanProvider);
      if (mounted) {
        final count = _picked.length;
        final subtitle = _scheduledAt != null
            ? 'Delivers ${_fmt(_scheduledAt!)}'
            : (_due != null ? 'Due ${_fmt(_due!)}' : null);
        bestieToast(
          context,
          _scheduledAt != null
              ? 'Scheduled for delivery'
              : (count == 0
                  ? 'Task created'
                  : 'Assigned to $count ${count == 1 ? 'person' : 'people'}'),
          body: subtitle,
          kind: BestieToastKind.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
        bestieToast(context, 'Could not create',
            body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _fmt(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final pickedIds = _picked.map((p) => p['id']).toSet();
    final candidates =
        _people.where((p) => !pickedIds.contains(p['id'])).take(8).toList();
    final me = widget.ref.read(authStoreProvider).user;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        BestieTokens.s4,
        0,
        BestieTokens.s4,
        MediaQuery.of(context).viewInsets.bottom + BestieTokens.s4,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          BestieTextField(
              label: 'Title',
              controller: _title,
              hint: 'What needs to happen?'),
          const SizedBox(height: BestieTokens.s2),

          BestieTextField(label: 'Description (optional)', controller: _desc),
          const SizedBox(height: BestieTokens.s2),

          // ----- priority -----
          Text('Priority',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textMuted)),
          const SizedBox(height: 6),
          BestieSegmentedControl<String>(
            value: _priority,
            onChanged: (v) => setState(() => _priority = v),
            options: const [
              BestieSegmentOption(value: 'LOW', label: 'Low'),
              BestieSegmentOption(value: 'MEDIUM', label: 'Medium'),
              BestieSegmentOption(value: 'HIGH', label: 'High'),
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
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Pings 15 min, 5 min, and at the deadline — then every 30 min while overdue.',
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ),
          const SizedBox(height: BestieTokens.s3),

          // ----- deliver-at (scheduled task) -----
          Text('Deliver to assignee at (optional)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textMuted)),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            icon: Icon(
              _scheduledAt == null
                  ? Icons.schedule_send_outlined
                  : Icons.schedule_send_rounded,
              size: 16,
            ),
            label: Text(_scheduledAt == null
                ? 'Send immediately (tap to schedule)'
                : 'Delivers ${_fmt(_scheduledAt!)}'),
            onPressed: _pickScheduledAt,
          ),
          if (_scheduledAt != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(
                  'Assignee won\'t see this task or get notified until then.',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _scheduledAt = null),
                child: const Text('Clear'),
              ),
            ]),
          ],
          const SizedBox(height: BestieTokens.s3),

          // ----- assignees -----
          Text('Assign to',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textMuted)),
          if (_picked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _picked
                    .map((p) => InputChip(
                          avatar: BestieAvatar(
                              name: p['name'] ?? '?',
                              imageUrl: p['avatarUrl'],
                              isClient: p['isClient'] ?? false,
                              size: 18),
                          label: BestieUserName(
                              name: p['name'] ?? '',
                              isClient: p['isClient'] ?? false,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                          onDeleted: () => setState(() =>
                              _picked.removeWhere((x) => x['id'] == p['id'])),
                        ))
                    .toList(),
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
                  leading: BestieAvatar(
                      name: p['name'] ?? '?',
                      imageUrl: p['avatarUrl'],
                      isClient: p['isClient'] ?? false,
                      size: 28),
                  title: BestieUserName(
                      name: p['name'] ?? '',
                      isClient: p['isClient'] ?? false,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${p['userId']} · ${p['role']?.toString().replaceAll('_', ' ') ?? ''}',
                    style: TextStyle(color: c.textMuted, fontSize: 12),
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
            label: 'Create + notify',
            icon: Icons.send,
            onPressed: _picked.isEmpty || _submitting ? null : _submit,
            loading: _submitting,
          ),
        ],
      ),
    );
  }
}
