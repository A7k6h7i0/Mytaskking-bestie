import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';
import 'task_actions_sheet.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});
  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String _view = 'kanban';
  void Function()? _offAssigned;

  static const _columns = [
    ('BACKLOG',     'Backlog'),
    ('TODO',        'To do'),
    ('IN_PROGRESS', 'In progress'),
    ('REVIEW',      'Review'),
    ('DONE',        'Done'),
  ];

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
    super.dispose();
  }

  Future<void> _move(String taskId, String targetStatus) async {
    try {
      await ref.read(apiProvider).moveTask(taskId, status: targetStatus);
      ref.invalidate(tasksKanbanProvider);
    } catch (e) {
      if (mounted) bestieToast(context, 'Could not move', body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksKanbanProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Tasks'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: BestieSegmentedControl<String>(
                value: _view,
                onChanged: (v) => setState(() => _view = v),
                options: const [
                  BestieSegmentOption(value: 'kanban', label: 'Board', icon: Icons.view_kanban_outlined),
                  BestieSegmentOption(value: 'list',   label: 'List',  icon: Icons.list_alt_outlined),
                ],
              ),
            ),
          ),
        ],
      ),
      body: tasks.when(
        loading: () => const Center(child: BestieSpinner()),
        error: (e, _) => BestieEmptyState(
          icon: Icons.error_outline, iconColor: BestieTokens.cDanger,
          title: 'Couldn\'t load tasks', description: formatApiError(e),
        ),
        data: (data) {
          final cols = (data['columns'] as Map?)?.cast<String, dynamic>() ?? const {};
          if (cols.values.every((v) => (v as List).isEmpty)) {
            return BestieEmptyState(
              icon: Icons.task_alt,
              title: 'No tasks yet',
              description: 'Create one and assign it to anyone in the workspace.',
              action: FilledButton.icon(onPressed: _newTask, icon: const Icon(Icons.add), label: const Text('New task')),
            );
          }
          if (_view == 'list') return _buildList(cols);
          return _buildKanban(cols);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTask,
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
    );
  }

  Widget _buildKanban(Map<String, dynamic> cols) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(BestieTokens.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _columns.map((col) {
          final items = (cols[col.$1] as List?)?.cast<Map<String, dynamic>>() ?? const [];
          return Container(
            width: 280,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: DragTarget<String>(
              onAcceptWithDetails: (d) => _move(d.data, col.$1),
              builder: (ctx, _, __) => Container(
                decoration: BoxDecoration(
                  color: BestieTokens.cSurface1,
                  borderRadius: BorderRadius.circular(BestieTokens.rMd),
                  border: Border.all(color: BestieTokens.cBorder),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(children: [
                        Expanded(child: Text(col.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                        BestieBadge(child: Text('${items.length}')),
                      ]),
                    ),
                    ...items.map((t) => _taskCard(t)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildList(Map<String, dynamic> cols) {
    final all = cols.values.expand((v) => (v as List).cast<Map<String, dynamic>>()).toList();
    all.sort((a, b) => '${b['updatedAt']}'.compareTo('${a['updatedAt']}'));
    return ListView.separated(
      padding: const EdgeInsets.all(BestieTokens.s3),
      itemBuilder: (_, i) => _taskCard(all[i]),
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemCount: all.length,
    );
  }

  Widget _taskCard(Map<String, dynamic> t) {
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

    final color = switch (priority) {
      'urgent' => BestieTokens.cDanger,
      'high'   => BestieTokens.cWarning,
      'medium' => BestieTokens.cInfo,
      _        => BestieTokens.cBorderStrong,
    };

    return LongPressDraggable<String>(
      data: t['id'] as String,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(BestieTokens.rSm),
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(BestieTokens.rSm)),
          child: Text(t['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      child: GestureDetector(
        onTap: () => _openTask(t['id'] as String),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(BestieTokens.rSm),
            border: Border.all(color: BestieTokens.cBorder),
            boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 2, offset: Offset(0, 1))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 24, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 6),
              Text(t['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              if (myState != null) ...[
                const SizedBox(height: 6),
                _stateBadge(myState, myScore),
              ],
              const SizedBox(height: 8),
              Row(children: [
                if (assignees.isNotEmpty)
                  Row(children: assignees.take(3).map((a) {
                    final u = (a['user'] as Map?)?.cast<String, dynamic>() ?? const {};
                    return Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: BestieAvatar(name: u['name'] ?? '?', imageUrl: u['avatarUrl'], isClient: u['isClient'] ?? false, size: 22),
                    );
                  }).toList()),
                const Spacer(),
                if (dueAt != null) BestieBadge(
                  tone: BestieTone.warning,
                  child: Text(_fmt(dueAt)),
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
    bestieBottomSheet<void>(
      context,
      title: 'Task',
      builder: (ctx) => TaskActionsSheet(taskId: taskId, parentRef: ref),
    );
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
                'Reminder pings 15 minutes before due.',
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
