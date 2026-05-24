import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import 'task_actions_sheet.dart';

/// Full-screen detail for a single task. Wraps the existing
/// [TaskActionsSheet] body in a Scaffold so users get a real back button +
/// dedicated route (`/tasks/:id`) instead of a bottom sheet.
///
/// All accept / decline / complete actions inside the sheet pop the current
/// route on success — same behavior as the modal version had.
class TaskDetailScreen extends ConsumerWidget {
  final String taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          // Prefer the navigator stack pop so we land on whatever screen
          // pushed us (chat list, tasks, search results, notifications).
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/tasks');
            }
          },
        ),
        title: const Text('Task'),
      ),
      body: SafeArea(
        child: TaskActionsSheet(taskId: taskId, parentRef: ref),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'task_pomodoro',
        onPressed: () => _openPomodoro(context),
        backgroundColor: BestieTokens.cBrand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.timer_rounded),
        label: const Text('Focus'),
      ),
    );
  }

  void _openPomodoro(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PomodoroSheet(taskId: taskId),
    );
  }
}

/// Pomodoro focus timer for the active task. Classic 25-on / 5-off cadence
/// — the timer keeps running while the sheet stays open. Closing the sheet
/// cancels the session (no background timer, no notification — kept simple
/// on purpose so it can ship without platform-channel work).
class _PomodoroSheet extends StatefulWidget {
  final String taskId;
  const _PomodoroSheet({required this.taskId});
  @override
  State<_PomodoroSheet> createState() => _PomodoroSheetState();
}

class _PomodoroSheetState extends State<_PomodoroSheet> {
  static const _focusSeconds = 25 * 60;
  static const _breakSeconds = 5 * 60;

  Timer? _tick;
  int _remaining = _focusSeconds;
  bool _running = false;
  bool _onBreak = false;
  // Count of completed focus sprints in this session — surfaces progress
  // even when the user re-opens the sheet between sprints.
  int _completedSprints = 0;

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
        if (_remaining <= 0) _onPhaseDone();
      });
    });
  }

  void _onPhaseDone() {
    _tick?.cancel();
    HapticFeedback.heavyImpact();
    if (!_onBreak) _completedSprints += 1;
    _onBreak = !_onBreak;
    _remaining = _onBreak ? _breakSeconds : _focusSeconds;
    _running = false;
    // Auto-show a toast so even with the screen backgrounded briefly the
    // user knows the phase flipped when they look back.
    if (mounted) {
      bestieToast(
        context,
        _onBreak ? 'Break time — 5 minutes' : 'Focus time — 25 minutes',
        body: _onBreak
            ? 'Step away from the screen.'
            : 'Sprint ${_completedSprints + 1} starting.',
        kind: BestieToastKind.success,
      );
    }
  }

  void _reset() {
    _tick?.cancel();
    setState(() {
      _running = false;
      _onBreak = false;
      _remaining = _focusSeconds;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final total = _onBreak ? _breakSeconds : _focusSeconds;
    final progress = (total - _remaining) / total;
    final mins = (_remaining ~/ 60).toString().padLeft(2, '0');
    final secs = (_remaining % 60).toString().padLeft(2, '0');
    final accent = _onBreak ? c.success : c.brand;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      padding: EdgeInsets.fromLTRB(
        20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: c.borderStrong,
            borderRadius: BorderRadius.circular(BestieTokens.rPill),
          ),
        ),
        Text(
          _onBreak ? 'BREAK' : 'FOCUS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: BestieTokens.fwBold,
            color: accent,
            letterSpacing: BestieTokens.lsEyebrow,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 220, height: 220,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: const Size(220, 220),
              painter: _RingPainter(
                progress: progress.clamp(0.0, 1.0),
                trackColor: c.surface2,
                fillColor: accent,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$mins:$secs',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: BestieTokens.fwBold,
                    color: c.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sprint ${_completedSprints + 1}',
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ],
            ),
          ]),
        ),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            iconSize: 28,
            color: c.textSoft,
            tooltip: 'Reset',
            onPressed: _reset,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.35),
                    blurRadius: 18, offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 36,
              ),
            ),
          ),
          const SizedBox(width: 20),
          IconButton(
            iconSize: 28,
            color: c.textSoft,
            tooltip: 'Skip phase',
            onPressed: _onPhaseDone,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ]),
        if (_completedSprints > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: c.successSoft,
              borderRadius: BorderRadius.circular(BestieTokens.rPill),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, size: 14, color: c.success),
              const SizedBox(width: 6),
              Text(
                '$_completedSprints ${_completedSprints == 1 ? 'sprint' : 'sprints'} done',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: BestieTokens.fwSemibold,
                  color: c.success,
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 4),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color fillColor;
  _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.fillColor != fillColor;
}
