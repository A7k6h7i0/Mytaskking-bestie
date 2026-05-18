import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bestie_design/bestie_design.dart';

import '../state.dart';

/// Detail view + action buttons for a single task. Shown as a bottom sheet
/// when the user taps a card.
///
/// State machine:
///   PENDING   → Accept / Decline buttons
///   ACCEPTED  → Mark complete
///   DECLINED  → "You declined" note
///   COMPLETED → Score ring + reason
///
/// On any transition we invalidate the kanban + notifications providers and
/// pop a toast — the same `task.assignment.changed` socket event also fires
/// to every other connected client.
class TaskActionsSheet extends ConsumerStatefulWidget {
  final String taskId;
  final WidgetRef parentRef;
  const TaskActionsSheet({super.key, required this.taskId, required this.parentRef});

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
      if (mounted) setState(() { _task = t; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _err = formatApiError(e); _loading = false; });
    }
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() op, String successMsg) async {
    setState(() => _busy = true);
    try {
      final row = await op();
      widget.parentRef.invalidate(tasksKanbanProvider);
      widget.parentRef.invalidate(notificationsProvider);
      if (mounted) {
        // After accept/decline/complete the row carries fresh state — show
        // the score in the toast when present.
        final score = row['score'] as int?;
        final reason = row['scoreReason'] as String?;
        bestieToast(
          context,
          score != null ? 'Completed · $score/100' : successMsg,
          body: reason,
          kind: BestieToastKind.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) bestieToast(context, 'Action failed', body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(BestieTokens.s5), child: Center(child: BestieSpinner()));
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
    final me = ref.read(authStoreProvider).user;
    final assignees = (t['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final mine = assignees.firstWhere(
      (a) => (a['user'] as Map?)?['id'] == me?.id,
      orElse: () => const {},
    );
    final myState = mine['state'] as String?;
    final myScore = mine['score'] as int?;
    final scoreReason = mine['scoreReason'] as String?;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        BestieTokens.s4, 0, BestieTokens.s4,
        MediaQuery.of(context).viewInsets.bottom + BestieTokens.s4,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ----- header -----
            Text(t['title'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              BestieBadge(child: Text(t['status']?.toString().replaceAll('_', ' ') ?? '')),
              BestieBadge(
                tone: _priorityTone(t['priority']),
                child: Text(t['priority'] ?? '—'),
              ),
              if (t['dueAt'] != null) BestieBadge(
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
                  color: BestieTokens.cSurface1,
                  border: Border.all(color: BestieTokens.cBorder),
                  borderRadius: BorderRadius.circular(BestieTokens.rSm),
                ),
                child: Text(t['description']),
              ),
            ],

            // ----- assignees -----
            const SizedBox(height: BestieTokens.s4),
            const Text('Assignees',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BestieTokens.cTextMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            ...assignees.map((a) {
              final u = (a['user'] as Map?)?.cast<String, dynamic>() ?? const {};
              final state = a['state'] as String? ?? 'PENDING';
              final s = a['score'] as int?;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  BestieAvatar(name: u['name'] ?? '?', imageUrl: u['avatarUrl'], isClient: u['isClient'] ?? false, size: 28),
                  const SizedBox(width: 10),
                  Expanded(child: BestieUserName(
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
                    colors: [BestieTokens.cSuccess.withOpacity(0.12), Colors.transparent],
                  ),
                  border: Border.all(color: BestieTokens.cSuccess.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(BestieTokens.rMd),
                ),
                child: Row(children: [
                  BestieProgressRing(
                    value: myScore / 100,
                    size: 64,
                    color: myScore >= 80 ? BestieTokens.cSuccess :
                           myScore >= 50 ? BestieTokens.cWarning : BestieTokens.cDanger,
                    label: Text('$myScore', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your score', style: TextStyle(fontWeight: FontWeight.w700)),
                      if (scoreReason != null) Text(scoreReason,
                          style: const TextStyle(color: BestieTokens.cTextMuted, fontSize: 12)),
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
        return Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('Decline'),
              style: OutlinedButton.styleFrom(foregroundColor: BestieTokens.cDanger),
              onPressed: _busy ? null : () => _act(
                () => ref.read(apiProvider).declineTask(widget.taskId),
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
        ]);
      case 'ACCEPTED':
        return BestiePrimaryButton(
          label: 'Mark complete',
          icon: Icons.check_circle,
          loading: _busy,
          color: BestieTokens.cSuccess,
          onPressed: () => _act(
            () => ref.read(apiProvider).completeTask(widget.taskId),
            'Marked complete',
          ),
        );
      case 'COMPLETED':
      case 'DECLINED':
      default:
        // Either we're not an assignee or the lifecycle is over.
        return const SizedBox.shrink();
    }
  }

  Widget _stateChip(String state, int? score) {
    switch (state) {
      case 'ACCEPTED':  return const BestieBadge(tone: BestieTone.brand,   dot: true, child: Text('ACCEPTED'));
      case 'DECLINED':  return const BestieBadge(tone: BestieTone.danger,  dot: true, child: Text('DECLINED'));
      case 'COMPLETED':
        final tone = score == null
            ? BestieTone.success
            : (score >= 80 ? BestieTone.success : score >= 50 ? BestieTone.warning : BestieTone.danger);
        return BestieBadge(tone: tone, dot: true, child: Text(score == null ? 'COMPLETED' : '$score/100'));
      case 'PENDING':
      default:
        return const BestieBadge(tone: BestieTone.warning, dot: true, child: Text('PENDING'));
    }
  }

  BestieTone _priorityTone(dynamic p) {
    switch (p) {
      case 'URGENT': return BestieTone.danger;
      case 'HIGH':   return BestieTone.warning;
      case 'MEDIUM': return BestieTone.info;
      default:       return BestieTone.neutral;
    }
  }

  String _fmt(dynamic iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '$iso';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, $h:$m';
  }
}
