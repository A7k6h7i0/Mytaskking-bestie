import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Detail view + action buttons for a single task. Shown as a bottom sheet
/// when the user taps a card.
///
/// State machine:
///   PENDING   â†’ Accept / Decline buttons
///   ACCEPTED  â†’ Mark complete
///   DECLINED  â†’ "You declined" note
///   COMPLETED â†’ Score ring + reason
///
/// On any transition we invalidate the kanban + notifications providers and
/// pop a toast â€” the same `task.assignment.changed` socket event also fires
/// to every other connected client.
class TaskActionsSheet extends ConsumerStatefulWidget {
  final String taskId;
  final WidgetRef parentRef;
  const TaskActionsSheet(
      {super.key, required this.taskId, required this.parentRef});

  @override
  ConsumerState<TaskActionsSheet> createState() => _TaskActionsSheetState();
}

class _TaskActionsSheetState extends ConsumerState<TaskActionsSheet> {
  Map<String, dynamic>? _task;
  bool _loading = true;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await ref.read(apiProvider).getTask(widget.taskId);
      if (mounted)
        setState(() {
          _task = t;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _err = formatApiError(e);
          _loading = false;
        });
    }
  }

  Future<void> _act(
      Future<Map<String, dynamic>> Function() op, String successMsg) async {
    setState(() => _busy = true);
    try {
      final row = await op();
      widget.parentRef.invalidate(tasksKanbanProvider);
      widget.parentRef.invalidate(notificationsProvider);
      if (mounted) {
        // After accept/decline/complete the row carries fresh state â€” show
        // the score in the toast when present.
        final score = row['score'] as int?;
        final reason = row['scoreReason'] as String?;
        final promoted =
            (row['autoPromotedTask'] as Map?)?.cast<String, dynamic>();
        bestieToast(
          context,
          score != null ? 'Completed - $score/100' : successMsg,
          body: promoted != null
              ? '${promoted['title']} moved to In progress'
              : reason,
          kind: BestieToastKind.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
        bestieToast(context, 'Action failed',
            body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
          padding: EdgeInsets.all(BestieTokens.s5),
          child: Center(child: BestieSpinner()));
    }
    if (_err != null || _task == null) {
      return Padding(
        padding: const EdgeInsets.all(BestieTokens.s5),
        child: BestieEmptyState(
          icon: Icons.error_outline,
          iconColor: BestieTokens.cDanger,
          title: 'Couldn\'t load task',
          description: _err,
        ),
      );
    }

    final t = _task!;
    final c = BestieColors.of(context);
    final me = ref.read(authStoreProvider).user;
    final assignees =
        (t['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final mine = assignees.firstWhere(
      (a) => (a['user'] as Map?)?['id'] == me?.id,
      orElse: () => const {},
    );
    final myState = mine['state'] as String?;
    final myScore = mine['score'] as int?;
    final scoreReason = mine['scoreReason'] as String?;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        BestieTokens.s4,
        0,
        BestieTokens.s4,
        MediaQuery.of(context).viewInsets.bottom + BestieTokens.s4,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ----- header -----
            Text(t['title'] ?? '',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              BestieBadge(
                  child:
                      Text(t['status']?.toString().replaceAll('_', ' ') ?? '')),
              BestieBadge(
                tone: _priorityTone(t['priority']),
                child: Text(t['priority'] ?? 'â€”'),
              ),
              if (t['dueAt'] != null)
                BestieBadge(
                  tone: BestieTone.warning,
                  dot: true,
                  child: Text('Due ${_fmt(t['dueAt'])}'),
                ),
            ]),

            if ((t['description'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: BestieTokens.s3),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surface2,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(BestieTokens.rSm),
                ),
                child: Text(
                  t['description'],
                  style: TextStyle(color: c.text),
                ),
              ),
            ],

            // ----- assigned by -----
            if ((t['createdBy'] as Map?)?['name'] != null) ...[
              const SizedBox(height: BestieTokens.s4),
              const Text('Assigned by',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: BestieTokens.cTextMuted,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Row(children: [
                BestieAvatar(
                    name: (t['createdBy'] as Map)['name'] ?? '?',
                    imageUrl: (t['createdBy'] as Map)['avatarUrl'],
                    isClient: (t['createdBy'] as Map)['isClient'] ?? false,
                    size: 28),
                const SizedBox(width: 10),
                Expanded(
                    child: BestieUserName(
                  name: (t['createdBy'] as Map)['name'] ?? '',
                  isClient: (t['createdBy'] as Map)['isClient'] ?? false,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )),
              ]),
            ],

            // ----- assignees -----
            const SizedBox(height: BestieTokens.s4),
            Text(
                assignees.length == 1 ? 'Assigned to' : 'Assigned to (${assignees.length})',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: BestieTokens.cTextMuted,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            ...assignees.map((a) {
              final u =
                  (a['user'] as Map?)?.cast<String, dynamic>() ?? const {};
              final state = a['state'] as String? ?? 'PENDING';
              final s = a['score'] as int?;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  BestieAvatar(
                      name: u['name'] ?? '?',
                      imageUrl: u['avatarUrl'],
                      isClient: u['isClient'] ?? false,
                      size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                      child: BestieUserName(
                    name: u['name'] ?? '',
                    isClient: u['isClient'] ?? false,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  )),
                  _stateChip(state, s),
                ]),
              );
            }),

            // ----- score panel (mine, only when completed) -----
            if (myState == 'COMPLETED' && myScore != null) ...[
              const SizedBox(height: BestieTokens.s4),
              Container(
                padding: const EdgeInsets.all(BestieTokens.s3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      BestieTokens.cSuccess.withOpacity(0.12),
                      Colors.transparent
                    ],
                  ),
                  border:
                      Border.all(color: BestieTokens.cSuccess.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(BestieTokens.rMd),
                ),
                child: Row(children: [
                  BestieProgressRing(
                    value: myScore / 100,
                    size: 64,
                    color: myScore >= 80
                        ? BestieTokens.cSuccess
                        : myScore >= 50
                            ? BestieTokens.cWarning
                            : BestieTokens.cDanger,
                    label: Text('$myScore',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your score',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      if (scoreReason != null)
                        Text(scoreReason,
                            style: const TextStyle(
                                color: BestieTokens.cTextMuted, fontSize: 12)),
                    ],
                  )),
                ]),
              ),
            ],

            // ----- action buttons -----
            const SizedBox(height: BestieTokens.s4),
            _actionsFor(myState),
          ],
        ),
      ),
    );
  }

  Widget _actionsFor(String? state) {
    switch (state) {
      case 'PENDING':
        return Column(children: [
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('Decline'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: BestieTokens.cDanger),
                onPressed: _busy
                    ? null
                    : () => _act(
                          () =>
                              ref.read(apiProvider).declineTask(widget.taskId),
                          'Declined',
                        ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BestiePrimaryButton(
                label: 'Accept',
                icon: Icons.check,
                loading: _busy,
                onPressed: () => _act(
                  () => ref.read(apiProvider).acceptTask(widget.taskId),
                  'Accepted',
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _snoozeRow(),
        ]);
      case 'ACCEPTED':
        return Column(children: [
          BestiePrimaryButton(
            label: 'Mark complete',
            icon: Icons.check_circle,
            loading: _busy,
            color: BestieTokens.cSuccess,
            onPressed: _completeWithReport,
          ),
          const SizedBox(height: 8),
          _snoozeRow(),
        ]);
      case 'COMPLETED':
      case 'DECLINED':
      default:
        // Either we're not an assignee or the lifecycle is over.
        return const SizedBox.shrink();
    }
  }

  Future<void> _completeWithReport() async {
    if (_task == null) return;
    final result = await bestieBottomSheet<_CompletionReportResult>(
      context,
      title: 'Complete with report',
      builder: (_) => _CompletionReportSheet(
        ref: ref,
        task: _task!,
      ),
    );
    if (result == null) return;
    await _act(
      () => ref.read(apiProvider).completeTask(
            widget.taskId,
            reportBody: result.body,
            reportRecipientIds: result.recipientIds,
          ),
      'Marked complete',
    );
  }

  /// Quick "kick the can" row â€” pushes the task's due date forward without
  /// reopening the create sheet. Designed for the common "I'll get to it
  /// after lunch / tomorrow / next sprint" pattern.
  Widget _snoozeRow() {
    final options = <(String, Duration)>[
      ('1h', const Duration(hours: 1)),
      ('Tomorrow', const Duration(days: 1)),
      ('Next week', const Duration(days: 7)),
    ];
    return Row(children: [
      const Icon(Icons.snooze_rounded,
          size: 14, color: BestieTokens.cTextMuted),
      const SizedBox(width: 6),
      const Text('Snooze:',
          style: TextStyle(
              fontSize: 12,
              color: BestieTokens.cTextMuted,
              fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      for (final opt in options) ...[
        OutlinedButton(
          onPressed: _busy ? null : () => _snooze(opt.$2, opt.$1),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            minimumSize: const Size(0, 30),
            visualDensity: VisualDensity.compact,
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          child: Text(opt.$1),
        ),
        const SizedBox(width: 6),
      ],
    ]);
  }

  Future<void> _snooze(Duration delta, String label) async {
    setState(() => _busy = true);
    try {
      final newDue = DateTime.now().add(delta);
      await ref.read(apiProvider).updateTask(widget.taskId, {
        'dueAt': newDue.toUtc().toIso8601String(),
      });
      widget.parentRef.invalidate(tasksKanbanProvider);
      if (mounted) {
        bestieToast(context, 'Snoozed Â· $label',
            body: 'New due ${newDue.toLocal()}'.split('.').first,
            kind: BestieToastKind.success);
        // Close the detail screen so the user lands back where they came
        // from â€” matches the existing accept/decline/complete flow.
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not snooze',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stateChip(String state, int? score) {
    switch (state) {
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
            child: Text(score == null ? 'COMPLETED' : '$score/100'));
      case 'PENDING':
      default:
        return const BestieBadge(
            tone: BestieTone.warning, dot: true, child: Text('PENDING'));
    }
  }

  BestieTone _priorityTone(dynamic p) {
    switch (p) {
      case 'URGENT':
        return BestieTone.danger;
      case 'HIGH':
        return BestieTone.warning;
      case 'MEDIUM':
        return BestieTone.info;
      default:
        return BestieTone.neutral;
    }
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
}

class _CompletionReportResult {
  final String body;
  final List<String> recipientIds;
  const _CompletionReportResult({
    required this.body,
    required this.recipientIds,
  });
}

class _CompletionReportSheet extends StatefulWidget {
  final WidgetRef ref;
  final Map<String, dynamic> task;
  const _CompletionReportSheet({required this.ref, required this.task});

  @override
  State<_CompletionReportSheet> createState() => _CompletionReportSheetState();
}

class _CompletionReportSheetState extends State<_CompletionReportSheet> {
  final _body = TextEditingController();
  final _peopleQuery = TextEditingController();
  final List<Map<String, dynamic>> _picked = [];
  List<Map<String, dynamic>> _people = [];
  bool _drafting = false;

  Future<void> _draftWithAi() async {
    setState(() => _drafting = true);
    try {
      final res = await widget.ref
          .read(apiProvider)
          .draftCompletionReport(widget.task['id'] as String);
      final draft = (res['draft'] ?? '').toString().trim();
      if (!mounted) return;
      if (draft.isEmpty) {
        bestieToast(context, 'AI draft unavailable',
            body: 'Write your report manually.',
            kind: BestieToastKind.warning);
      } else {
        setState(() => _body.text = draft);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Couldn\'t draft',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _picked.addAll(_defaultRecipients());
    _loadPeople();
  }

  @override
  void dispose() {
    _body.dispose();
    _peopleQuery.dispose();
    super.dispose();
  }

  int get _words =>
      _body.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  List<Map<String, dynamic>> _defaultRecipients() {
    final me = widget.ref.read(authStoreProvider).user;
    final out = <String, Map<String, dynamic>>{};
    final creator = (widget.task['createdBy'] as Map?)?.cast<String, dynamic>();
    if (creator != null && creator['id'] != me?.id)
      out[creator['id'] as String] = creator;
    final assignees =
        (widget.task['assignees'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
    for (final assignee in assignees) {
      final user = (assignee['user'] as Map?)?.cast<String, dynamic>();
      final id = user?['id']?.toString();
      if (id != null && id != me?.id && out.length < 3) out[id] = user!;
    }
    return out.values.toList();
  }

  Future<void> _loadPeople([String? q]) async {
    try {
      final items = await widget.ref.read(apiProvider).listEmployees(q: q);
      if (mounted) setState(() => _people = items);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final pickedIds = _picked.map((p) => p['id']).toSet();
    final candidates =
        _people.where((p) => !pickedIds.contains(p['id'])).take(8).toList();
    final canSubmit =
        _body.text.trim().isNotEmpty && _words <= 120 && _picked.isNotEmpty;

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
          Text(
            'Before completing, add a short report and choose who receives it.',
            style: TextStyle(color: c.textMuted, fontSize: 13),
          ),
          const SizedBox(height: BestieTokens.s3),
          Row(children: [
            const Expanded(
              child: Text(
                'Report (120 words max)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: _drafting ? null : _draftWithAi,
              icon: _drafting
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded, size: 16),
              label: Text(_drafting ? 'Drafting…' : 'Draft with AI'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: _body,
            minLines: 4,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText:
                  'What did you finish, what changed, and anything the reviewer should know?',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$_words/120 words',
              style: TextStyle(
                color: _words > 120 ? c.danger : c.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: BestieTokens.s3),
          const Text(
            'Report to',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
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
                            size: 18,
                          ),
                          label: BestieUserName(
                            name: p['name'] ?? '',
                            isClient: p['isClient'] ?? false,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          onDeleted: () => setState(() =>
                              _picked.removeWhere((x) => x['id'] == p['id'])),
                        ))
                    .toList(),
              ),
            ),
          const SizedBox(height: 8),
          BestieTextField(
            label: 'Search people',
            controller: _peopleQuery,
            icon: Icons.search,
            onChanged: (v) => _loadPeople(v),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: candidates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = candidates[i];
                return ListTile(
                  dense: true,
                  leading: BestieAvatar(
                    name: p['name'] ?? '?',
                    imageUrl: p['avatarUrl'],
                    isClient: p['isClient'] ?? false,
                    size: 28,
                  ),
                  title: BestieUserName(
                    name: p['name'] ?? '',
                    isClient: p['isClient'] ?? false,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${p['userId'] ?? ''} - ${p['role']?.toString().replaceAll('_', ' ') ?? ''}',
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.add, size: 16),
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
            label: 'Complete task',
            icon: Icons.check_circle,
            color: BestieTokens.cSuccess,
            onPressed: canSubmit
                ? () => Navigator.pop(
                      context,
                      _CompletionReportResult(
                        body: _body.text.trim(),
                        recipientIds:
                            _picked.map((p) => p['id'] as String).toList(),
                      ),
                    )
                : null,
          ),
        ],
      ),
    );
  }
}
