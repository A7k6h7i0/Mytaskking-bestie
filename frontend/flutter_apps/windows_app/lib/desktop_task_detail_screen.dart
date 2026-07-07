import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_mobile/state.dart';

/// Windows task detail — matches the provided HTML layout; all fields from
/// `GET /tasks/:id` (createdBy, assignees, subtasks, comments, attachments).
class DesktopTaskDetailScreen extends ConsumerStatefulWidget {
  const DesktopTaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<DesktopTaskDetailScreen> createState() =>
      _DesktopTaskDetailScreenState();
}

enum _TaskDetailTab { overview, subtasks, comments, files, activity }

class _DesktopTaskDetailScreenState
    extends ConsumerState<DesktopTaskDetailScreen> {
  Map<String, dynamic>? _task;
  bool _loading = true;
  bool _busy = false;
  String? _err;
  _TaskDetailTab _tab = _TaskDetailTab.overview;
  final _commentCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final t = await ref.read(apiProvider).getTask(widget.taskId);
      if (!mounted) return;
      setState(() {
        _task = t;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = formatApiError(e);
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _myAssignment(Map<String, dynamic> task) {
    final meId = ref.read(authStoreProvider).user?.id;
    if (meId == null) return null;
    final assignees =
        (task['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final a in assignees) {
      final uid = (a['user'] as Map?)?['id']?.toString() ?? a['userId']?.toString();
      if (uid == meId) return a;
    }
    return null;
  }

  Future<void> _act(
    Future<Map<String, dynamic>> Function() op,
    String successMsg,
  ) async {
    setState(() => _busy = true);
    try {
      final row = await op();
      ref.invalidate(tasksKanbanProvider);
      ref.invalidate(notificationsProvider);
      if (!mounted) return;
      final score = row['score'] as int?;
      final reason = row['scoreReason'] as String?;
      bestieToast(
        context,
        score != null ? 'Completed · $score/100' : successMsg,
        body: reason,
        kind: BestieToastKind.success,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(
          context,
          'Action failed',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleSubtask(String id, bool done) async {
    try {
      await ref.read(apiProvider).toggleSubtask(id, !done);
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(
          context,
          'Could not update checklist item',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    }
  }

  Future<void> _addComment() async {
    final body = _commentCtl.text.trim();
    if (body.isEmpty) return;
    try {
      await ref.read(apiProvider).addTaskComment(widget.taskId, body);
      _commentCtl.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(
          context,
          'Could not add comment',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    }
  }

  void _openPomodoro() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DesktopPomodoroSheet(taskId: widget.taskId),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _TaskUi.bgPage,
        body: Center(child: BestieSpinner()),
      );
    }
    if (_err != null || _task == null) {
      return Scaffold(
        backgroundColor: _TaskUi.bgPage,
        appBar: AppBar(
          backgroundColor: _TaskUi.bgCard,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _goBack(context),
          ),
        ),
        body: BestieEmptyState(
          icon: Icons.error_outline,
          iconColor: _TaskUi.tagRedText,
          title: 'Could not load task',
          description: _err,
        ),
      );
    }

    final task = _task!;
    final subtasks =
        (task['subtasks'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final comments =
        (task['comments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final files =
        (task['attachments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final mine = _myAssignment(task);
    final myState = mine?['state']?.toString();
    final myScore = mine?['score'] is int ? mine!['score'] as int : null;
    final scoreReason = mine?['scoreReason']?.toString();

    return Scaffold(
      backgroundColor: _TaskUi.bgPage,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _TaskUi.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 6,
                          offset: Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Color(0x08000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Back',
                              onPressed: () => _goBack(context),
                              icon: const Icon(Icons.arrow_back_rounded,
                                  color: _TaskUi.textMuted),
                            ),
                            const Spacer(),
                          ],
                        ),
                        Text(
                          '${task['title'] ?? 'Task'}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: _TaskUi.textMain,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _StatusBadges(task: task),
                        const SizedBox(height: 24),
                        _AssigneesRow(task: task, myScore: myScore),
                        if (myState == 'COMPLETED' && myScore != null) ...[
                          const SizedBox(height: 24),
                          _ScoreBanner(score: myScore, reason: scoreReason),
                        ],
                        if (myState != null && myState != 'COMPLETED' && myState != 'DECLINED') ...[
                          const SizedBox(height: 20),
                          _ActionBar(
                            state: myState,
                            busy: _busy,
                            onAccept: () => _act(
                              () => ref.read(apiProvider).acceptTask(widget.taskId),
                              'Accepted',
                            ),
                            onDecline: () => _act(
                              () => ref.read(apiProvider).declineTask(widget.taskId),
                              'Declined',
                            ),
                            onComplete: () => _completeWithReport(task),
                          ),
                        ],
                        const SizedBox(height: 24),
                        _TabBar(
                          tab: _tab,
                          subtasks: subtasks.length,
                          comments: comments.length,
                          files: files.length,
                          onSelect: (t) => setState(() => _tab = t),
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 820;
                            final left = _LeftPanel(
                              tab: _tab,
                              task: task,
                              subtasks: subtasks,
                              comments: comments,
                              files: files,
                              commentCtl: _commentCtl,
                              onToggleSubtask: _toggleSubtask,
                              onAddComment: _addComment,
                            );
                            final right = _DetailsPanel(task: task, mine: mine);
                            if (stacked) {
                              return Column(
                                children: [
                                  left,
                                  const SizedBox(height: 24),
                                  right,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: left),
                                const SizedBox(width: 24),
                                SizedBox(width: 340, child: right),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 32,
              bottom: 32,
              child: Material(
                elevation: 0,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  onTap: _openPomodoro,
                  borderRadius: BorderRadius.circular(24),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: _TaskUi.primaryBlue,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: _TaskUi.primaryBlue.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Focus',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/tasks');
    }
  }

  Future<void> _completeWithReport(Map<String, dynamic> task) async {
    final result = await showDialog<_CompletionResult>(
      context: context,
      builder: (_) => _CompletionReportDialog(ref: ref, task: task),
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
}

class _TaskUi {
  static const textMain = Color(0xFF111827);
  static const textMuted = Color(0xFF6B7280);
  static const borderLight = Color(0xFFE5E7EB);
  static const bgPage = Color(0xFFF9FAFB);
  static const bgCard = Color(0xFFFFFFFF);
  static const primaryBlue = Color(0xFF3B82F6);
  static const tagGreenBg = Color(0xFFDCFCE7);
  static const tagGreenText = Color(0xFF166534);
  static const tagBlueBg = Color(0xFFE0F2FE);
  static const tagBlueText = Color(0xFF0369A1);
  static const tagYellowBg = Color(0xFFFEF9C3);
  static const tagYellowText = Color(0xFFB45309);
  static const tagRedBg = Color(0xFFFEE2E2);
  static const tagRedText = Color(0xFFB91C1C);
  static const tagPurpleBg = Color(0xFFF3E8FF);
  static const tagPurpleText = Color(0xFF7E22CE);
  static const tagGreyBg = Color(0xFFF3F4F6);
  static const tagGreyText = Color(0xFF4B5563);
  static const dueBg = Color(0xFFFFF7ED);
  static const dueText = Color(0xFFC2410C);
}

class _StatusBadges extends StatelessWidget {
  const _StatusBadges({required this.task});

  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final status = (task['status'] ?? 'TODO').toString().replaceAll('_', ' ');
    final priority = (task['priority'] ?? 'MEDIUM').toString();
    final dueAt = task['dueAt'];

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _TagPill(
          label: status.toUpperCase(),
          bg: _statusBg(task['status']?.toString()),
          fg: _statusFg(task['status']?.toString()),
          uppercase: true,
        ),
        _TagPill(
          label: priority,
          bg: _priorityBg(priority),
          fg: _priorityFg(priority),
          uppercase: true,
        ),
        if (dueAt != null)
          _TagPill(
            label: 'Due ${_fmtDate(dueAt)}',
            bg: _TaskUi.dueBg,
            fg: _TaskUi.dueText,
            dotColor: const Color(0xFFF59E0B),
            uppercase: false,
          ),
      ],
    );
  }
}

class _AssigneesRow extends StatelessWidget {
  const _AssigneesRow({required this.task, this.myScore});

  final Map<String, dynamic> task;
  final int? myScore;

  @override
  Widget build(BuildContext context) {
    final creator = (task['createdBy'] as Map?)?.cast<String, dynamic>();
    final assignees =
        (task['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final primary = assignees.isNotEmpty
        ? (assignees.first['user'] as Map?)?.cast<String, dynamic>()
        : null;
    final displayScore = myScore ??
        (assignees
            .map((a) => a['score'])
            .whereType<int>()
            .cast<int?>()
            .firstWhere((s) => s != null, orElse: () => null));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 48,
            runSpacing: 16,
            children: [
              if (creator != null)
                _AssigneeBlock(label: 'Assigned by', user: creator),
              if (primary != null)
                _AssigneeBlock(label: 'Assigned to', user: primary)
              else if (assignees.isEmpty)
                const _AssigneeBlock(
                  label: 'Assigned to',
                  user: {'name': 'Unassigned'},
                ),
            ],
          ),
        ),
        if (displayScore != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _TaskUi.tagRedBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$displayScore/100',
                  style: const TextStyle(
                    color: _TaskUi.tagRedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AssigneeBlock extends StatelessWidget {
  const _AssigneeBlock({required this.label, required this.user});

  final String label;
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] ?? user['userId'] ?? '—').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: _TaskUi.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BestieAvatar(
              name: name,
              imageUrl: user['avatarUrl']?.toString(),
              isClient: user['isClient'] == true,
              size: 28,
            ),
            const SizedBox(width: 8),
            BestieUserName(
              name: name,
              isClient: user['isClient'] == true,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _TaskUi.textMain,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScoreBanner extends StatelessWidget {
  const _ScoreBanner({required this.score, this.reason});

  final int score;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? _TaskUi.tagGreenText
        : score >= 50
            ? _TaskUi.tagYellowText
            : _TaskUi.tagRedText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FBF8),
        border: Border.all(color: const Color(0xFFD1FAE5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(44, 44),
                  painter: _ScoreRingPainter(
                    progress: score / 100,
                    trackColor: _TaskUi.borderLight,
                    fillColor: color,
                  ),
                ),
                Text(
                  '$score',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _TaskUi.textMain,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your score',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _TaskUi.textMain,
                  ),
                ),
                if (reason != null && reason!.isNotEmpty)
                  Text(
                    reason!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _TaskUi.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  _ScoreRingPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
  });

  final double progress;
  final Color trackColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const radius = 18.0;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) =>
      old.progress != progress || old.fillColor != fillColor;
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.state,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onComplete,
  });

  final String state;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    if (state == 'PENDING') {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onDecline,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Decline'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _TaskUi.tagRedText,
                side: const BorderSide(color: _TaskUi.tagRedBg),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: busy ? null : onAccept,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: const Text('Accept'),
              style: FilledButton.styleFrom(
                backgroundColor: _TaskUi.primaryBlue,
              ),
            ),
          ),
        ],
      );
    }
    if (state == 'ACCEPTED') {
      return FilledButton.icon(
        onPressed: busy ? null : onComplete,
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Mark complete'),
        style: FilledButton.styleFrom(
          backgroundColor: _TaskUi.tagGreenText,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tab,
    required this.subtasks,
    required this.comments,
    required this.files,
    required this.onSelect,
  });

  final _TaskDetailTab tab;
  final int subtasks;
  final int comments;
  final int files;
  final ValueChanged<_TaskDetailTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _TaskUi.borderLight)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _TabItem(
              label: 'Overview',
              active: tab == _TaskDetailTab.overview,
              onTap: () => onSelect(_TaskDetailTab.overview),
            ),
            _TabItem(
              label: 'Subtasks',
              count: subtasks,
              active: tab == _TaskDetailTab.subtasks,
              onTap: () => onSelect(_TaskDetailTab.subtasks),
            ),
            _TabItem(
              label: 'Comments',
              count: comments,
              active: tab == _TaskDetailTab.comments,
              onTap: () => onSelect(_TaskDetailTab.comments),
            ),
            _TabItem(
              label: 'Files',
              count: files,
              active: tab == _TaskDetailTab.files,
              onTap: () => onSelect(_TaskDetailTab.files),
            ),
            _TabItem(
              label: 'Activity',
              active: tab == _TaskDetailTab.activity,
              onTap: () => onSelect(_TaskDetailTab.activity),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 24),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? _TaskUi.primaryBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: active ? _TaskUi.primaryBlue : _TaskUi.textMuted,
              ),
            ),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _TaskUi.tagGreyBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _TaskUi.tagGreyText,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LeftPanel extends StatelessWidget {
  const _LeftPanel({
    required this.tab,
    required this.task,
    required this.subtasks,
    required this.comments,
    required this.files,
    required this.commentCtl,
    required this.onToggleSubtask,
    required this.onAddComment,
  });

  final _TaskDetailTab tab;
  final Map<String, dynamic> task;
  final List<Map<String, dynamic>> subtasks;
  final List<Map<String, dynamic>> comments;
  final List<Map<String, dynamic>> files;
  final TextEditingController commentCtl;
  final Future<void> Function(String id, bool done) onToggleSubtask;
  final Future<void> Function() onAddComment;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: switch (tab) {
        _TaskDetailTab.overview => _OverviewContent(
            task: task,
            subtasks: subtasks,
            onToggleSubtask: onToggleSubtask,
          ),
        _TaskDetailTab.subtasks => _SubtasksContent(
            subtasks: subtasks,
            onToggleSubtask: onToggleSubtask,
          ),
        _TaskDetailTab.comments => _CommentsContent(
            comments: comments,
            controller: commentCtl,
            onSubmit: onAddComment,
          ),
        _TaskDetailTab.files => _FilesContent(files: files),
        _TaskDetailTab.activity => _ActivityContent(task: task),
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: _TaskUi.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _OverviewContent extends StatelessWidget {
  const _OverviewContent({
    required this.task,
    required this.subtasks,
    required this.onToggleSubtask,
  });

  final Map<String, dynamic> task;
  final List<Map<String, dynamic>> subtasks;
  final Future<void> Function(String id, bool done) onToggleSubtask;

  @override
  Widget build(BuildContext context) {
    final description = (task['description'] ?? '').toString().trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          iconBg: const Color(0xFFEEF2FF),
          iconColor: const Color(0xFF6366F1),
          icon: Icons.description_outlined,
          title: 'Description',
          child: Text(
            description.isEmpty ? 'No description provided.' : description,
            style: TextStyle(
              fontSize: 14,
              color: description.isEmpty ? _TaskUi.textMuted : const Color(0xFF374151),
              height: 1.5,
            ),
          ),
        ),
        if (subtasks.isNotEmpty)
          _Section(
            iconBg: const Color(0xFFECFDF5),
            iconColor: const Color(0xFF10B981),
            icon: Icons.checklist_rounded,
            title: 'Checklist',
            child: _Checklist(
              subtasks: subtasks,
              onToggle: onToggleSubtask,
            ),
          ),
      ],
    );
  }
}

class _SubtasksContent extends StatelessWidget {
  const _SubtasksContent({
    required this.subtasks,
    required this.onToggleSubtask,
  });

  final List<Map<String, dynamic>> subtasks;
  final Future<void> Function(String id, bool done) onToggleSubtask;

  @override
  Widget build(BuildContext context) {
    if (subtasks.isEmpty) {
      return const Text(
        'No subtasks yet.',
        style: TextStyle(color: _TaskUi.textMuted, fontSize: 14),
      );
    }
    return _Checklist(subtasks: subtasks, onToggle: onToggleSubtask);
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.subtasks, required this.onToggle});

  final List<Map<String, dynamic>> subtasks;
  final Future<void> Function(String id, bool done) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in subtasks) ...[
          InkWell(
            onTap: () => onToggle(item['id'].toString(), item['done'] == true),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _RoundCheck(checked: item['done'] == true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${item['title'] ?? 'Subtask'}',
                      style: TextStyle(
                        fontSize: 14,
                        color: const Color(0xFF374151),
                        decoration: item['done'] == true
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RoundCheck extends StatelessWidget {
  const _RoundCheck({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? _TaskUi.primaryBlue : Colors.transparent,
        border: Border.all(
          color: checked ? _TaskUi.primaryBlue : const Color(0xFFD1D5DB),
          width: 2,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 12, color: Colors.white)
          : null,
    );
  }
}

class _CommentsContent extends StatelessWidget {
  const _CommentsContent({
    required this.comments,
    required this.controller,
    required this.onSubmit,
  });

  final List<Map<String, dynamic>> comments;
  final TextEditingController controller;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (comments.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'No comments yet.',
              style: TextStyle(color: _TaskUi.textMuted, fontSize: 14),
            ),
          )
        else
          ...comments.map((c) {
            final author =
                (c['author'] as Map?)?.cast<String, dynamic>() ?? const {};
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BestieAvatar(
                    name: author['name']?.toString() ?? '?',
                    imageUrl: author['avatarUrl']?.toString(),
                    isClient: author['isClient'] == true,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              author['name']?.toString() ?? 'User',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _fmtDate(c['createdAt']),
                              style: const TextStyle(
                                color: _TaskUi.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${c['body'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF374151),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Write a comment…',
            filled: true,
            fillColor: _TaskUi.bgPage,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _TaskUi.borderLight),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: _TaskUi.primaryBlue,
            ),
            child: const Text('Post comment'),
          ),
        ),
      ],
    );
  }
}

class _FilesContent extends StatelessWidget {
  const _FilesContent({required this.files});

  final List<Map<String, dynamic>> files;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const Text(
        'No files attached.',
        style: TextStyle(color: _TaskUi.textMuted, fontSize: 14),
      );
    }
    return Column(
      children: files.map((f) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.insert_drive_file_outlined,
              color: _TaskUi.primaryBlue),
          title: Text(
            f['originalName']?.toString() ??
                f['mimeType']?.toString() ??
                'File',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            f['mimeType']?.toString() ?? '',
            style: const TextStyle(color: _TaskUi.textMuted, fontSize: 12),
          ),
        );
      }).toList(),
    );
  }
}

class _ActivityContent extends StatelessWidget {
  const _ActivityContent({required this.task});

  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final events = _buildActivityEvents(task);
    if (events.isEmpty) {
      return const Text(
        'No activity recorded yet.',
        style: TextStyle(color: _TaskUi.textMuted, fontSize: 14),
      );
    }
    return Column(
      children: events.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  color: _TaskUi.primaryBlue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _TaskUi.textMain,
                      ),
                    ),
                    if (e.subtitle != null)
                      Text(
                        e.subtitle!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: _TaskUi.textMuted,
                        ),
                      ),
                    Text(
                      _fmtDate(e.at),
                      style: const TextStyle(
                        fontSize: 11,
                        color: _TaskUi.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ActivityEvent {
  const _ActivityEvent({
    required this.at,
    required this.title,
    this.subtitle,
  });

  final dynamic at;
  final String title;
  final String? subtitle;
}

List<_ActivityEvent> _buildActivityEvents(Map<String, dynamic> task) {
  final events = <_ActivityEvent>[];
  events.add(_ActivityEvent(
    at: task['createdAt'],
    title: 'Task created',
    subtitle: (task['createdBy'] as Map?)?['name']?.toString(),
  ));
  if (task['updatedAt'] != null &&
      task['updatedAt'].toString() != task['createdAt'].toString()) {
    events.add(_ActivityEvent(
      at: task['updatedAt'],
      title: 'Task updated',
    ));
  }
  final assignees =
      (task['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  for (final a in assignees) {
    final user = (a['user'] as Map?)?.cast<String, dynamic>();
    final name = user?['name']?.toString() ?? 'Assignee';
    if (a['acceptedAt'] != null) {
      events.add(_ActivityEvent(
        at: a['acceptedAt'],
        title: '$name accepted the task',
      ));
    }
    if (a['declinedAt'] != null) {
      events.add(_ActivityEvent(
        at: a['declinedAt'],
        title: '$name declined the task',
      ));
    }
    if (a['completedAt'] != null) {
      events.add(_ActivityEvent(
        at: a['completedAt'],
        title: '$name completed the task',
        subtitle: a['score'] != null ? 'Score ${a['score']}/100' : null,
      ));
    }
  }
  final comments =
      (task['comments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  for (final c in comments) {
    events.add(_ActivityEvent(
      at: c['createdAt'],
      title: 'Comment added',
      subtitle: (c['author'] as Map?)?['name']?.toString(),
    ));
  }
  final reports =
      (task['completionReports'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
  for (final r in reports) {
    events.add(_ActivityEvent(
      at: r['createdAt'],
      title: 'Completion report submitted',
      subtitle: (r['author'] as Map?)?['name']?.toString(),
    ));
  }
  events.sort((a, b) {
    final left = DateTime.tryParse('${a.at}') ?? DateTime.fromMillisecondsSinceEpoch(0);
    final right = DateTime.tryParse('${b.at}') ?? DateTime.fromMillisecondsSinceEpoch(0);
    return right.compareTo(left);
  });
  return events;
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.task, this.mine});

  final Map<String, dynamic> task;
  final Map<String, dynamic>? mine;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Details',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _TaskUi.textMain,
            ),
          ),
          const SizedBox(height: 20),
          _DetailRow(
            icon: Icons.flag_outlined,
            label: 'Priority',
            value: '${task['priority'] ?? '—'}',
            valueBg: _priorityBg('${task['priority']}'),
            valueFg: _priorityFg('${task['priority']}'),
          ),
          if (task['dueAt'] != null)
            _DetailRow(
              icon: Icons.calendar_today_outlined,
              label: 'Due',
              value: _fmtDate(task['dueAt']),
              valueBg: _TaskUi.dueBg,
              valueFg: _TaskUi.dueText,
              uppercase: false,
            ),
          _DetailRow(
            icon: Icons.radio_button_checked_outlined,
            label: 'Status',
            value: (task['status'] ?? '—').toString().replaceAll('_', ' '),
            valueBg: _statusBg(task['status']?.toString()),
            valueFg: _statusFg(task['status']?.toString()),
          ),
          if (task['scheduledAt'] != null)
            _DetailRow(
              icon: Icons.schedule_send_outlined,
              label: 'Scheduled',
              value: _fmtDate(task['scheduledAt']),
              valueBg: _TaskUi.tagPurpleBg,
              valueFg: _TaskUi.tagPurpleText,
              uppercase: false,
            ),
          _DetailRow(
            icon: Icons.add_circle_outline,
            label: 'Created',
            value: _fmtDate(task['createdAt']),
            valueBg: _TaskUi.tagGreyBg,
            valueFg: _TaskUi.tagGreyText,
            uppercase: false,
          ),
          if (mine != null)
            _DetailRow(
              icon: Icons.person_outline,
              label: 'Your status',
              value: (mine!['state'] ?? '—').toString().replaceAll('_', ' '),
              valueBg: _TaskUi.tagBlueBg,
              valueFg: _TaskUi.tagBlueText,
            ),
          if ((task['assignees'] as List?)?.length != null &&
              (task['assignees'] as List).length > 1)
            _DetailRow(
              icon: Icons.groups_outlined,
              label: 'Assignees',
              value: '${(task['assignees'] as List).length} people',
              valueBg: _TaskUi.tagGreyBg,
              valueFg: _TaskUi.tagGreyText,
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueBg,
    required this.valueFg,
    this.uppercase = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueBg;
  final Color valueFg;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(icon, size: 16, color: _TaskUi.textMuted),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _TaskUi.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: valueBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              uppercase ? value.toUpperCase() : value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: valueFg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.child,
  });

  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _TaskUi.textMain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({
    required this.label,
    required this.bg,
    required this.fg,
    this.dotColor,
    this.uppercase = true,
  });

  final String label;
  final Color bg;
  final Color fg;
  final Color? dotColor;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            uppercase ? label.toUpperCase() : label,
            style: TextStyle(
              fontSize: dotColor != null ? 12 : 11,
              fontWeight: dotColor != null ? FontWeight.w600 : FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

Color _priorityBg(String priority) {
  switch (priority.toUpperCase()) {
    case 'URGENT':
      return _TaskUi.tagRedBg;
    case 'HIGH':
      return _TaskUi.tagYellowBg;
    case 'LOW':
      return _TaskUi.tagGreyBg;
    default:
      return _TaskUi.tagBlueBg;
  }
}

Color _priorityFg(String priority) {
  switch (priority.toUpperCase()) {
    case 'URGENT':
      return _TaskUi.tagRedText;
    case 'HIGH':
      return _TaskUi.tagYellowText;
    case 'LOW':
      return _TaskUi.tagGreyText;
    default:
      return _TaskUi.tagBlueText;
  }
}

Color _statusBg(String? status) {
  switch (status?.toUpperCase()) {
    case 'DONE':
      return _TaskUi.tagGreenBg;
    case 'IN_PROGRESS':
      return _TaskUi.tagBlueBg;
    case 'REVIEW':
      return _TaskUi.tagPurpleBg;
    case 'CANCELLED':
      return _TaskUi.tagRedBg;
    default:
      return _TaskUi.tagGreyBg;
  }
}

Color _statusFg(String? status) {
  switch (status?.toUpperCase()) {
    case 'DONE':
      return _TaskUi.tagGreenText;
    case 'IN_PROGRESS':
      return _TaskUi.tagBlueText;
    case 'REVIEW':
      return _TaskUi.tagPurpleText;
    case 'CANCELLED':
      return _TaskUi.tagRedText;
    default:
      return _TaskUi.tagGreyText;
  }
}

String _fmtDate(dynamic iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '$iso';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day}, $h:$m';
}

class _CompletionResult {
  const _CompletionResult({required this.body, required this.recipientIds});
  final String body;
  final List<String> recipientIds;
}

class _CompletionReportDialog extends StatefulWidget {
  const _CompletionReportDialog({required this.ref, required this.task});

  final WidgetRef ref;
  final Map<String, dynamic> task;

  @override
  State<_CompletionReportDialog> createState() =>
      _CompletionReportDialogState();
}

class _CompletionReportDialogState extends State<_CompletionReportDialog> {
  final _body = TextEditingController();
  final List<Map<String, dynamic>> _picked = [];

  @override
  void initState() {
    super.initState();
    final me = widget.ref.read(authStoreProvider).user;
    final creator =
        (widget.task['createdBy'] as Map?)?.cast<String, dynamic>();
    if (creator != null && creator['id'] != me?.id) _picked.add(creator);
    final assignees =
        (widget.task['assignees'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
    for (final a in assignees) {
      final user = (a['user'] as Map?)?.cast<String, dynamic>();
      if (user != null &&
          user['id'] != me?.id &&
          !_picked.any((p) => p['id'] == user['id'])) {
        _picked.add(user);
      }
      if (_picked.length >= 3) break;
    }
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  int get _words =>
      _body.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _body.text.trim().isNotEmpty && _words <= 120 && _picked.isNotEmpty;
    return AlertDialog(
      title: const Text('Complete with report'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add a short report (120 words max) before completing.',
              style: TextStyle(color: _TaskUi.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              minLines: 4,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'What did you finish?',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$_words/120 words',
                style: TextStyle(
                  fontSize: 12,
                  color: _words > 120 ? _TaskUi.tagRedText : _TaskUi.textMuted,
                ),
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
        FilledButton(
          onPressed: canSubmit
              ? () => Navigator.pop(
                    context,
                    _CompletionResult(
                      body: _body.text.trim(),
                      recipientIds:
                          _picked.map((p) => p['id'].toString()).toList(),
                    ),
                  )
              : null,
          child: const Text('Complete task'),
        ),
      ],
    );
  }
}

class _DesktopPomodoroSheet extends StatefulWidget {
  const _DesktopPomodoroSheet({required this.taskId});
  final String taskId;

  @override
  State<_DesktopPomodoroSheet> createState() => _DesktopPomodoroSheetState();
}

class _DesktopPomodoroSheetState extends State<_DesktopPomodoroSheet> {
  static const _focusSeconds = 25 * 60;
  static const _breakSeconds = 5 * 60;

  Timer? _tick;
  int _remaining = _focusSeconds;
  bool _running = false;
  bool _onBreak = false;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_running) {
      _tick?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining -= 1;
        if (_remaining <= 0) {
          _tick?.cancel();
          _running = false;
          _onBreak = !_onBreak;
          _remaining = _onBreak ? _breakSeconds : _focusSeconds;
          HapticFeedback.heavyImpact();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _onBreak ? _breakSeconds : _focusSeconds;
    final progress = (total - _remaining) / total;
    final mins = (_remaining ~/ 60).toString().padLeft(2, '0');
    final secs = (_remaining % 60).toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _TaskUi.bgCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _onBreak ? 'Break' : 'Focus',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: _TaskUi.primaryBlue,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  strokeWidth: 8,
                  color: _TaskUi.primaryBlue,
                  backgroundColor: _TaskUi.borderLight,
                ),
                Text(
                  '$mins:$secs',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _toggle,
            style: FilledButton.styleFrom(
              backgroundColor: _TaskUi.primaryBlue,
            ),
            child: Text(_running ? 'Pause' : 'Start'),
          ),
        ],
      ),
    );
  }
}
