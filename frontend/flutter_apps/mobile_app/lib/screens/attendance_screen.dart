import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

final workdaySummaryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, dateKey) async {
  return ref.read(apiProvider).attendanceSummary(date: dateKey);
});

final workdayUserDayProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String userId, String date})>(
        (ref, args) async {
  return ref.read(apiProvider).attendanceUserDay(
        userId: args.userId,
        date: args.date,
      );
});

bool canViewWorkdaySummary(String? role) {
  return role == 'ADMIN' ||
      role == 'SUPER_ADMIN' ||
      role == 'MANAGER' ||
      role == 'PROJECT_COORDINATOR_MANAGER';
}

/// Daily workday log screen — backed by `/attendance/*`.
///
/// Three-phase flow that mirrors the backend's lifecycle:
///   1. **Check-in**  → write today's plan (≥ 10 words) and clock in.
///   2. **Lunch**     → toggle start / end of the lunch break (gated by the
///                      server's lunchStartHour / lunchEndHour config).
///   3. **Check-out** → write a logout report (≥ 10 words) and clock out.
///
/// Each phase opens at a configurable hour. Word count enforcement lives on
/// the server too — we surface the live count up front so the user knows
/// before they press submit.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  Map<String, dynamic>? _today;
  Map<String, dynamic>? _config;
  bool _loading = true;
  String? _error;
  // Consecutive workdays (incl. today, if checked in) the user has logged.
  int _streak = 0;

  final _plan = TextEditingController();
  final _report = TextEditingController();
  final _lunchNote = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _plan.addListener(() => setState(() {}));
    _report.addListener(() => setState(() {}));
    _refresh();
  }

  @override
  void dispose() {
    _plan.dispose();
    _report.dispose();
    _lunchNote.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // `/attendance/today` returns the full config inline (minRequiredWords,
      // hours, lunch window) alongside today's entry — one round trip is enough.
      final today = await ref.read(apiProvider).attendanceToday();
      if (!mounted) return;
      final dateKey = today['today']?.toString();
      if (dateKey != null &&
          canViewWorkdaySummary(ref.read(authStoreProvider).user?.role)) {
        ref.invalidate(workdaySummaryProvider(dateKey));
      }
      setState(() {
        _today = today;
        _config = {
          'minRequiredWords': today['minRequiredWords'],
          'checkInHour': (today['opensAt'] as Map?)?['hour'],
          'checkOutHour': (today['checkOutAt'] as Map?)?['hour'],
          'lunchStartHour': (today['lunchWindow'] as Map?)?['startHour'],
          'lunchEndHour': (today['lunchWindow'] as Map?)?['endHour'],
        };
        _loading = false;
      });
      // Best-effort streak fetch — don't fail the screen if it errors.
      _refreshStreak();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = formatApiError(e);
        _loading = false;
      });
    }
  }

  /// Walks backward from today through the last 60 days of workday entries
  /// and counts the longest unbroken run of check-ins. Weekends are skipped
  /// (a missing Saturday or Sunday doesn't break the streak).
  Future<void> _refreshStreak() async {
    try {
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 60));
      final resp =
          await ref.read(apiProvider).attendanceRange(from: from, to: now);
      final items =
          (resp['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final byDate = <String, Map<String, dynamic>>{
        for (final e in items)
          if (e['localDate'] != null) '${e['localDate']}': e,
      };
      String fmt(DateTime d) {
        return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }

      int streak = 0;
      var day = DateTime(now.year, now.month, now.day);
      // If today isn't checked in yet, start counting from yesterday so we
      // don't penalize someone for opening the screen before clocking in.
      final todayKey = fmt(day);
      if (byDate[todayKey]?['checkInAt'] == null) {
        day = day.subtract(const Duration(days: 1));
      }
      for (var i = 0; i < 60; i++) {
        // Weekend: skip without breaking.
        if (day.weekday == DateTime.saturday ||
            day.weekday == DateTime.sunday) {
          day = day.subtract(const Duration(days: 1));
          continue;
        }
        final entry = byDate[fmt(day)];
        if (entry == null || entry['checkInAt'] == null) break;
        streak += 1;
        day = day.subtract(const Duration(days: 1));
      }
      if (mounted) setState(() => _streak = streak);
    } catch (_) {/* silent — streak is decorative */}
  }

  int _wordCount(String text) =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

  int get _minWords {
    final entry = _today?['entry'] as Map<String, dynamic>?;
    final viaEntry = (entry?['minRequiredWords'] as num?)?.toInt();
    if (viaEntry != null && viaEntry > 0) return viaEntry;
    final viaConfig = (_config?['minRequiredWords'] as num?)?.toInt();
    return viaConfig ?? 10;
  }

  Future<void> _checkIn() async {
    final count = _wordCount(_plan.text);
    if (count < _minWords) {
      bestieToast(context, 'Plan needs at least $_minWords words',
          body: 'You\'ve written $count.', kind: BestieToastKind.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).attendanceCheckIn(plan: _plan.text.trim());
      _plan.clear();
      await _refresh();
      if (mounted)
        bestieToast(context, 'Checked in',
            body: 'Have a productive day.', kind: BestieToastKind.success);
    } catch (e) {
      if (mounted)
        bestieToast(context, 'Could not check in',
            body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleLunch() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).attendanceLunch(
            note:
                _lunchNote.text.trim().isEmpty ? null : _lunchNote.text.trim(),
          );
      _lunchNote.clear();
      await _refresh();
      if (mounted) {
        final state = (_today?['entry'] as Map?)?['lunchState'];
        bestieToast(context, state == 'ENDED' ? 'Lunch ended' : 'Lunch started',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted)
        bestieToast(context, 'Lunch toggle failed',
            body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleBreak() async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(apiProvider).attendanceBreak();
      final onBreak = res['onBreak'] == true;
      await _refresh();
      if (mounted) {
        bestieToast(
          context,
          onBreak ? 'Break started' : 'Welcome back',
          body: onBreak
              ? 'Your supervisor was notified you stepped away.'
              : 'Your supervisor was notified you\'re back.',
          kind: BestieToastKind.success,
        );
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Break toggle failed',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkOut() async {
    final count = _wordCount(_report.text);
    if (count < _minWords) {
      bestieToast(context, 'Logout report needs at least $_minWords words',
          body: 'You\'ve written $count.', kind: BestieToastKind.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .attendanceCheckOut(report: _report.text.trim());
      _report.clear();
      await _refresh();
      if (mounted)
        bestieToast(context, 'Logged out for the day',
            body: 'See you tomorrow.', kind: BestieToastKind.success);
    } catch (e) {
      if (mounted)
        bestieToast(context, 'Could not check out',
            body: formatApiError(e), kind: BestieToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final role = ref.watch(authStoreProvider).user?.role;
    final showSummary = canViewWorkdaySummary(role);
    final dateKey = _today?['today']?.toString() ?? '';

    // Pad the list bottom past the shell's floating nav (70 + margin +
    // safe-area) so the checkout section clears it — without an empty
    // bottomNavigationBar SizedBox that rendered as a white strip.
    final bottomPad = 70.0 + 24 + MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.textMuted,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/chat');
            }
          },
        ),
        title: Text(
          'Workday',
          style: TextStyle(color: c.textMuted),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: BestieSpinner())
          : _error != null
              ? BestieEmptyState(
                  icon: Icons.error_outline_rounded,
                  iconColor: c.danger,
                  title: 'Could not load today',
                  description: _error,
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    // AlwaysScrollable so pull-to-refresh works even when
                    // content is short, and the list always reaches its end.
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
                    children: [
                      _StatusCard(today: _today, colors: c),
                      if (showSummary && dateKey.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _WorkdaySummarySection(dateKey: dateKey),
                      ],
                      if (_streak > 0) ...[
                        const SizedBox(height: 12),
                        _streakCard(c),
                      ],
                      if (_isCheckedOut()) ...[
                        const SizedBox(height: 12),
                        _digestCard(c),
                      ],
                      const SizedBox(height: 16),
                      _checkInSection(c),
                      const SizedBox(height: 16),
                      _breakSection(c),
                      const SizedBox(height: 16),
                      _lunchSection(c),
                      const SizedBox(height: 16),
                      _checkOutSection(c),
                    ],
                  ),
                ),
    );
  }

  bool _isCheckedOut() {
    final entry = (_today?['entry'] as Map?)?.cast<String, dynamic>();
    return entry?['checkOutAt'] != null;
  }

  /// "Day at a glance" recap shown once the user has clocked out — lists
  /// hours worked, lunch duration (if recorded), and a gentle prompt to
  /// celebrate before signing off. Lives below the streak card so the
  /// page tells a clean morning → working → wrap-up story.
  Widget _digestCard(BestieColors c) {
    final entry = (_today?['entry'] as Map?)?.cast<String, dynamic>();
    final inAt = DateTime.tryParse('${entry?['checkInAt']}')?.toLocal();
    final outAt = DateTime.tryParse('${entry?['checkOutAt']}')?.toLocal();
    final lunchStart =
        DateTime.tryParse('${entry?['lunchStartedAt']}')?.toLocal();
    final lunchEnd = DateTime.tryParse('${entry?['lunchEndedAt']}')?.toLocal();
    if (inAt == null || outAt == null) return const SizedBox.shrink();
    var worked = outAt.difference(inAt);
    if (lunchStart != null && lunchEnd != null) {
      worked -= lunchEnd.difference(lunchStart);
    }
    if (worked.isNegative) worked = Duration.zero;
    String fmtDur(Duration d) => '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    String fmtTime(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.success.withOpacity(0.14),
            c.brand.withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: c.success.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.check_circle_rounded, color: c.success, size: 18),
            const SizedBox(width: 6),
            Text("Today's wrap-up",
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 14,
                  fontWeight: BestieTokens.fwBold,
                )),
          ]),
          const SizedBox(height: 8),
          _digestRow(c, '⏰', '${fmtTime(inAt)} → ${fmtTime(outAt)}'),
          _digestRow(c, '🛠', 'Worked ${fmtDur(worked)}'),
          if (lunchStart != null && lunchEnd != null)
            _digestRow(
                c, '🍽', 'Lunch ${fmtDur(lunchEnd.difference(lunchStart))}'),
          if (_streak > 0)
            _digestRow(c, '🔥', '$_streak-day streak — see you tomorrow.'),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _digestRow(BestieColors c, String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
            width: 20,
            child: Text(emoji, style: const TextStyle(fontSize: 14))),
        const SizedBox(width: 8),
        Expanded(
            child:
                Text(text, style: TextStyle(color: c.textMuted, fontSize: 13))),
      ]),
    );
  }

  /// Gentle dopamine hit — surfaces consecutive workdays the user has
  /// checked in. Plays the same role as a Duolingo streak: tiny visible
  /// reward that nudges people to keep the chain unbroken. Weekends don't
  /// reset it (computed in `_refreshStreak`).
  Widget _streakCard(BestieColors c) {
    final label = _streak == 1 ? 'day' : 'days';
    final encourage = switch (_streak) {
      < 3 => 'Nice start — keep it rolling.',
      < 7 => 'You\'re on a roll.',
      < 14 => "Habit forming. Don't break it.",
      < 30 => 'Two-week streak — keep showing up.',
      _ => "Legend. ${_streak ~/ 7} weeks strong.",
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.warning.withOpacity(0.18),
            c.danger.withOpacity(0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: c.warning.withOpacity(0.30)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: c.warning.withOpacity(0.20),
            borderRadius: BorderRadius.circular(BestieTokens.rMd),
          ),
          child: Icon(Icons.local_fire_department_rounded,
              color: c.warning, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: TextStyle(
                      color: c.textMuted,
                      fontSize: 16,
                      fontWeight: BestieTokens.fwBold),
                  children: [
                    TextSpan(text: '$_streak '),
                    TextSpan(
                      text: '$label streak',
                      style: TextStyle(
                          color: c.textMuted,
                          fontWeight: BestieTokens.fwSemibold,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(encourage,
                  style: TextStyle(color: c.textMuted, fontSize: 12)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _checkInSection(BestieColors c) {
    final entry = (_today?['entry'] as Map?)?.cast<String, dynamic>();
    final checkedIn = entry?['checkInAt'] != null;
    final cfg = _config;
    final hour = (cfg?['checkInHour'] as num?)?.toInt() ?? 9;
    final count = _wordCount(_plan.text);

    return _SectionCard(
      icon: Icons.flag_rounded,
      iconColor: c.brand,
      title: 'Morning check-in',
      subtitle: checkedIn
          ? 'Clocked in at ${_formatTime(entry?['checkInAt']?.toString())}'
          : 'Opens at ${hour.toString().padLeft(2, '0')}:00 · ≥ $_minWords words',
      done: checkedIn,
      colors: c,
      children: [
        if (checkedIn && (entry?['checkInPlan'] ?? '').toString().isNotEmpty)
          _ReadOnlyEntry(
              label: 'Today\'s plan',
              text: entry!['checkInPlan'].toString(),
              colors: c)
        else ...[
          TextField(
            controller: _plan,
            minLines: 5,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: c.textMuted, height: 1.45),
            decoration: InputDecoration(
              hintText:
                  'Write today\'s plan in ≥ $_minWords words. Mention top priorities, dependencies, and what "done" looks like by end of day.',
              hintStyle: TextStyle(color: c.textFaint),
              filled: true,
              fillColor: c.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BestieTokens.rMd),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BestieTokens.rMd),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BestieTokens.rMd),
                borderSide: BorderSide(color: c.brand, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _WordMeter(count: count, min: _minWords, colors: c),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _checkIn,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              icon: const Icon(Icons.login_rounded, size: 16),
              label: const Text('Check in'),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _breakSection(BestieColors c) {
    final entry = (_today?['entry'] as Map?)?.cast<String, dynamic>();
    final onBreak = entry?['onBreak'] == true;
    final checkedIn = entry?['checkInAt'] != null;
    final checkedOut = entry?['checkOutAt'] != null;
    final breakSecs = (entry?['breakSeconds'] as num?)?.toInt() ?? 0;
    final available = checkedIn && !checkedOut;

    String fmtMins(int secs) {
      final m = (secs / 60).round();
      if (m < 60) return '${m}m';
      return '${m ~/ 60}h ${m % 60}m';
    }

    return _SectionCard(
      icon: Icons.coffee_outlined,
      iconColor: c.brand,
      title: 'Break',
      subtitle: onBreak
          ? 'On break since ${_formatTime(entry?['onBreakSince']?.toString())} — supervisor notified'
          : breakSecs > 0
              ? 'Total break today · ${fmtMins(breakSecs)}'
              : 'Step away anytime — your supervisor is told automatically',
      done: false,
      colors: c,
      children: [
        if (available)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _toggleBreak,
              style: FilledButton.styleFrom(
                backgroundColor: onBreak ? c.brandStrong : c.brand,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: Icon(onBreak ? Icons.work_rounded : Icons.coffee_rounded,
                  size: 18),
              label: Text(onBreak ? 'I\'m back' : 'Take a break'),
            ),
          )
        else
          Text('Check in to use breaks.',
              style: TextStyle(color: c.textMuted, fontSize: 13)),
      ],
    );
  }

  Widget _lunchSection(BestieColors c) {
    final entry = (_today?['entry'] as Map?)?.cast<String, dynamic>();
    final state = entry?['lunchState']?.toString(); // null | STARTED | ENDED
    final cfg = _config;
    final startHour = (cfg?['lunchStartHour'] as num?)?.toInt() ?? 13;
    final endHour = (cfg?['lunchEndHour'] as num?)?.toInt() ?? 14;
    final canStart = entry?['checkInAt'] != null &&
        entry?['checkOutAt'] == null &&
        state == null;
    final canEnd = state == 'STARTED';
    final done = state == 'ENDED';

    return _SectionCard(
      icon: Icons.restaurant_rounded,
      iconColor: c.brand,
      title: 'Lunch break',
      subtitle: done
          ? 'Returned at ${_formatTime(entry?['lunchEndedAt']?.toString())}'
          : state == 'STARTED'
              ? 'Started at ${_formatTime(entry?['lunchStartedAt']?.toString())} · resume after ${endHour.toString().padLeft(2, '0')}:00'
              : 'Opens at ${startHour.toString().padLeft(2, '0')}:00',
      done: done,
      colors: c,
      children: [
        if (canStart || canEnd) ...[
          TextField(
            controller: _lunchNote,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: c.textMuted),
            decoration: InputDecoration(
              hintText: canEnd
                  ? 'Lunch wrap-up note (optional)'
                  : 'Anything blocking? (optional)',
              hintStyle: TextStyle(color: c.textFaint),
              filled: true,
              fillColor: c.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BestieTokens.rSm),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BestieTokens.rSm),
                borderSide: BorderSide(color: c.border),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _toggleLunch,
              style: FilledButton.styleFrom(
                backgroundColor: canEnd ? c.brandStrong : c.brand,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: Icon(canEnd ? Icons.work_rounded : Icons.coffee_rounded,
                  size: 18),
              label: Text(canEnd ? 'End lunch' : 'Start lunch'),
            ),
          ),
        ] else if (done && (entry?['lunchNote'] ?? '').toString().isNotEmpty)
          _ReadOnlyEntry(
              label: 'Lunch note',
              text: entry!['lunchNote'].toString(),
              colors: c),
      ],
    );
  }

  Widget _checkOutSection(BestieColors c) {
    final entry = (_today?['entry'] as Map?)?.cast<String, dynamic>();
    final checkedIn = entry?['checkInAt'] != null;
    final checkedOut = entry?['checkOutAt'] != null;
    final cfg = _config;
    final hour = (cfg?['checkOutHour'] as num?)?.toInt() ?? 18;
    final count = _wordCount(_report.text);

    return _SectionCard(
      icon: Icons.logout_rounded,
      iconColor: c.brand,
      title: 'Logout report',
      subtitle: checkedOut
          ? 'Logged out at ${_formatTime(entry?['checkOutAt']?.toString())}'
          : checkedIn
              ? 'Opens at ${hour.toString().padLeft(2, '0')}:00 · ≥ $_minWords words'
              : 'Check in first.',
      done: checkedOut,
      disabled: !checkedIn,
      colors: c,
      children: [
        if (checkedOut &&
            (entry?['checkOutReport'] ?? '').toString().isNotEmpty)
          _ReadOnlyEntry(
              label: 'Today\'s report',
              text: entry!['checkOutReport'].toString(),
              colors: c)
        else if (checkedIn) ...[
          TextField(
            controller: _report,
            minLines: 5,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: c.textMuted, height: 1.45),
            decoration: InputDecoration(
              hintText:
                  'What did you ship today? Mention shipped, blocked, and rolled-over items in ≥ $_minWords words.',
              hintStyle: TextStyle(color: c.textFaint),
              filled: true,
              fillColor: c.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BestieTokens.rMd),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BestieTokens.rMd),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BestieTokens.rMd),
                borderSide: BorderSide(color: c.brand, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _WordMeter(count: count, min: _minWords, colors: c)),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _checkOut,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              icon: const Icon(Icons.logout_rounded, size: 16),
              label: const Text('Check out'),
            ),
          ]),
        ],
      ],
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  final Map<String, dynamic>? today;
  final BestieColors colors;
  const _StatusCard({required this.today, required this.colors});

  @override
  Widget build(BuildContext context) {
    final entry = (today?['entry'] as Map?)?.cast<String, dynamic>();
    final state = entry?['lunchState']?.toString();
    String phase;
    Color phaseColor;
    IconData phaseIcon;
    if (entry?['checkOutAt'] != null) {
      phase = 'Logged out';
      phaseColor = colors.textMuted;
      phaseIcon = Icons.check_circle_outline_rounded;
    } else if (state == 'STARTED') {
      phase = 'On lunch';
      phaseColor = colors.warning;
      phaseIcon = Icons.restaurant_rounded;
    } else if (entry?['checkInAt'] != null) {
      phase = 'Working';
      phaseColor = colors.success;
      phaseIcon = Icons.work_rounded;
    } else {
      phase = 'Not checked in';
      phaseColor = colors.textMuted;
      phaseIcon = Icons.hourglass_empty_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        border: Border.all(color: colors.border),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: phaseColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(BestieTokens.rMd),
          ),
          child: Icon(phaseIcon, color: phaseColor, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TODAY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: BestieTokens.fwBold,
                  letterSpacing: BestieTokens.lsEyebrow,
                  color: colors.textMuted,
                )),
            const SizedBox(height: 2),
            Text(phase,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: BestieTokens.fwBold,
                  color: colors.textMuted,
                  letterSpacing: BestieTokens.lsTight,
                )),
          ]),
        ),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool done;
  final bool disabled;
  final List<Widget> children;
  final BestieColors colors;
  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.colors,
    this.done = false,
    this.disabled = false,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(BestieTokens.rLg),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(BestieTokens.rSm),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            fontWeight: BestieTokens.fwSemibold,
                            fontSize: 15,
                            color: colors.textMuted,
                            letterSpacing: BestieTokens.lsSnug,
                          )),
                      Text(subtitle,
                          style:
                              TextStyle(color: colors.textFaint, fontSize: 12)),
                    ]),
              ),
              if (done)
                Icon(Icons.check_circle_rounded,
                    color: colors.success, size: 22),
            ]),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}

class _WordMeter extends StatelessWidget {
  final int count;
  final int min;
  final BestieColors colors;
  const _WordMeter(
      {required this.count, required this.min, required this.colors});

  @override
  Widget build(BuildContext context) {
    final ratio = (count / min).clamp(0.0, 1.0);
    final ok = count >= min;
    final accent = ok ? colors.success : colors.brand;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: BestieTokens.fwBold,
              color: accent,
            )),
        Text(' / $min words',
            style: TextStyle(color: colors.textMuted, fontSize: 13)),
        const Spacer(),
        if (ok)
          Icon(Icons.check_circle_outline_rounded,
              size: 14, color: colors.success),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(BestieTokens.rPill),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 6,
          backgroundColor: colors.surface2,
          valueColor: AlwaysStoppedAnimation(accent),
        ),
      ),
    ]);
  }
}

class _ReadOnlyEntry extends StatelessWidget {
  final String label;
  final String text;
  final BestieColors colors;
  const _ReadOnlyEntry(
      {required this.label, required this.text, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(BestieTokens.rSm),
        border: Border.all(color: colors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: BestieTokens.fwBold,
              color: colors.textMuted,
              letterSpacing: BestieTokens.lsEyebrow,
            )),
        const SizedBox(height: 6),
        Text(text,
            style: TextStyle(color: colors.textMuted, height: 1.45, fontSize: 13.5)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Workday summary (managers & admins)
// ---------------------------------------------------------------------------

class _WorkdaySummarySection extends ConsumerStatefulWidget {
  final String dateKey;
  const _WorkdaySummarySection({required this.dateKey});

  @override
  ConsumerState<_WorkdaySummarySection> createState() =>
      _WorkdaySummarySectionState();
}

class _WorkdaySummarySectionState extends ConsumerState<_WorkdaySummarySection> {
  String? _selectedUserId;
  String? _selectedUserName;

  void _selectEmployee(String userId, String userName) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      setState(() {
        _selectedUserId = userId;
        _selectedUserName = userName;
      });
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, scrollController) => _WorkdayDetailSheet(
          userId: userId,
          userName: userName,
          dateKey: widget.dateKey,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final role = ref.watch(authStoreProvider).user?.role ?? '';
    final isAdmin = role == 'ADMIN' || role == 'SUPER_ADMIN';
    final summary = ref.watch(workdaySummaryProvider(widget.dateKey));
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.brand.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(BestieTokens.rSm),
                ),
                child: Icon(Icons.groups_rounded, color: colors.brand, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Workday summary',
                      style: TextStyle(
                        fontWeight: BestieTokens.fwSemibold,
                        fontSize: 15,
                        color: colors.textMuted,
                      ),
                    ),
                    Text(
                      widget.dateKey,
                      style: TextStyle(color: colors.textFaint, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (!isAdmin)
                Tooltip(
                  message: 'Manager workdays are visible to admins only',
                  child: Icon(Icons.info_outline_rounded,
                      size: 18, color: colors.textFaint),
                ),
            ],
          ),
          const SizedBox(height: 12),
          summary.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: BestieSpinner()),
            ),
            error: (e, _) => BestieEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load summary',
              description: formatApiError(e),
            ),
            data: (data) {
              final items = (data['items'] as List? ?? const [])
                  .cast<Map<String, dynamic>>();
              if (items.isEmpty) {
                return const BestieEmptyState(
                  icon: Icons.people_outline,
                  title: 'No employees to show',
                  description:
                      'Active team members will appear here once they start their workday.',
                );
              }

              if (wide) {
                return SizedBox(
                  height: 420,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _WorkdaySummaryList(
                          items: items,
                          selectedUserId: _selectedUserId,
                          onSelect: _selectEmployee,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 7,
                        child: _selectedUserId == null
                            ? BestieEmptyState(
                                icon: Icons.touch_app_outlined,
                                title: 'Select an employee',
                                description:
                                    'Tap someone to see their full workday.',
                                iconColor: colors.textFaint,
                              )
                            : _WorkdayDetailBody(
                                userId: _selectedUserId!,
                                userName: _selectedUserName ?? 'Employee',
                                dateKey: widget.dateKey,
                              ),
                      ),
                    ],
                  ),
                );
              }

              return _WorkdaySummaryList(
                items: items,
                selectedUserId: null,
                onSelect: _selectEmployee,
                maxHeight: 360,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WorkdaySummaryList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String? selectedUserId;
  final void Function(String userId, String userName) onSelect;
  final double? maxHeight;

  const _WorkdaySummaryList({
    required this.items,
    required this.selectedUserId,
    required this.onSelect,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      shrinkWrap: maxHeight == null,
      physics: maxHeight == null
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = items[index];
        final user = (row['user'] as Map).cast<String, dynamic>();
        final userId = user['id']?.toString() ?? '';
        final status = row['status']?.toString() ?? 'Not started';
        final selected = userId == selectedUserId;
        return _WorkdaySummaryTile(
          user: user,
          status: status,
          onBreak: row['onBreak'] == true,
          selected: selected,
          onTap: () => onSelect(
            userId,
            user['name']?.toString() ?? 'Employee',
          ),
        );
      },
    );

    if (maxHeight != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight!),
        child: list,
      );
    }
    return list;
  }
}

class _WorkdaySummaryTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final String status;
  final bool onBreak;
  final bool selected;
  final VoidCallback onTap;

  const _WorkdaySummaryTile({
    required this.user,
    required this.status,
    required this.onBreak,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final chip = _workdayStatusStyle(status, onBreak, colors);
    return Material(
      color: selected ? colors.brandSoft : colors.surface2,
      borderRadius: BorderRadius.circular(BestieTokens.rMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestieTokens.rMd),
            border: Border.all(color: selected ? colors.brand : colors.border),
          ),
          child: Row(
            children: [
              BestieAvatar(
                name: user['name']?.toString() ?? 'Employee',
                imageUrl: user['avatarUrl']?.toString(),
                isClient: false,
                size: 40,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BestieUserName(
                      name: user['name']?.toString() ?? 'Employee',
                      isClient: false,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    if ((user['customTitle'] ?? '').toString().isNotEmpty)
                      Text(
                        user['customTitle'].toString(),
                        style: TextStyle(color: colors.textFaint, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: chip.bg,
                  borderRadius: BorderRadius.circular(BestieTokens.rPill),
                  border: Border.all(color: chip.border),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: chip.fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: colors.textFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkdayStatusStyle {
  final Color bg;
  final Color fg;
  final Color border;
  const _WorkdayStatusStyle(this.bg, this.fg, this.border);
}

_WorkdayStatusStyle _workdayStatusStyle(
    String status, bool onBreak, BestieColors colors) {
  if (status == 'Logged out') {
    return _WorkdayStatusStyle(
      colors.textMuted.withOpacity(0.12),
      colors.textMuted,
      colors.border,
    );
  }
  if (status == 'Lunch') {
    return _WorkdayStatusStyle(
      colors.warning.withOpacity(0.14),
      colors.warning,
      colors.warning.withOpacity(0.35),
    );
  }
  if (onBreak || status == 'Break') {
    return _WorkdayStatusStyle(
      colors.info.withOpacity(0.14),
      colors.info,
      colors.info.withOpacity(0.35),
    );
  }
  if (status == 'Checked in') {
    return _WorkdayStatusStyle(
      colors.success.withOpacity(0.14),
      colors.success,
      colors.success.withOpacity(0.35),
    );
  }
  return _WorkdayStatusStyle(
    colors.surface2,
    colors.textMuted,
    colors.border,
  );
}

class _WorkdayDetailSheet extends ConsumerWidget {
  final String userId;
  final String userName;
  final String dateKey;
  final ScrollController scrollController;

  const _WorkdayDetailSheet({
    required this.userId,
    required this.userName,
    required this.dateKey,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BestieColors.of(context);
    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    userName,
                    style: TextStyle(
                      fontWeight: BestieTokens.fwBold,
                      fontSize: 17,
                      color: colors.textMuted,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: _WorkdayDetailBody(
              userId: userId,
              userName: userName,
              dateKey: dateKey,
              scrollController: scrollController,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkdayDetailBody extends ConsumerWidget {
  final String userId;
  final String userName;
  final String dateKey;
  final ScrollController? scrollController;

  const _WorkdayDetailBody({
    required this.userId,
    required this.userName,
    required this.dateKey,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BestieColors.of(context);
    final detail = ref.watch(workdayUserDayProvider(
      (userId: userId, date: dateKey),
    ));

    return detail.when(
      loading: () => const Center(child: BestieSpinner()),
      error: (e, _) => BestieEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Could not load workday',
        description: formatApiError(e),
      ),
      data: (data) {
        final entry = (data['entry'] as Map?)?.cast<String, dynamic>() ?? {};
        final status = data['status']?.toString() ?? 'Not started';
        final chip = _workdayStatusStyle(status, entry['onBreak'] == true, colors);

        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                BestieAvatar(
                  name: userName,
                  imageUrl: (data['user'] as Map?)?['avatarUrl']?.toString(),
                  isClient: false,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dateKey,
                          style: TextStyle(
                            color: colors.textFaint,
                            fontSize: 12,
                          )),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: chip.bg,
                          borderRadius: BorderRadius.circular(BestieTokens.rPill),
                          border: Border.all(color: chip.border),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: chip.fg,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _WorkdayDetailBlock(
              colors: colors,
              title: 'Check-in',
              time: entry['checkInAt']?.toString(),
              body: entry['checkInPlan']?.toString(),
              empty: 'Not checked in yet',
            ),
            const SizedBox(height: 12),
            _WorkdayDetailBlock(
              colors: colors,
              title: 'Break',
              time: entry['onBreak'] == true
                  ? entry['onBreakSince']?.toString()
                  : null,
              body: entry['onBreak'] == true
                  ? 'Currently on break'
                  : _formatBreakTotal(entry['breakSeconds']),
              empty: 'No breaks recorded',
              subtitle: entry['onBreak'] == true ? 'Started' : 'Total today',
            ),
            const SizedBox(height: 12),
            _WorkdayDetailBlock(
              colors: colors,
              title: 'Lunch',
              time: entry['lunchStartedAt']?.toString(),
              body: _lunchDetail(entry),
              empty: 'Lunch not started',
              subtitle: entry['lunchEndedAt'] != null
                  ? 'Ended ${_formatWorkdayTime(entry['lunchEndedAt']?.toString())}'
                  : null,
            ),
            const SizedBox(height: 12),
            _WorkdayDetailBlock(
              colors: colors,
              title: 'Logout',
              time: entry['checkOutAt']?.toString(),
              body: entry['checkOutReport']?.toString(),
              empty: 'Not logged out yet',
            ),
          ],
        );
      },
    );
  }
}

class _WorkdayDetailBlock extends StatelessWidget {
  final BestieColors colors;
  final String title;
  final String? time;
  final String? body;
  final String empty;
  final String? subtitle;

  const _WorkdayDetailBlock({
    required this.colors,
    required this.title,
    this.time,
    this.body,
    required this.empty,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent =
        (time != null && time!.isNotEmpty) || (body != null && body!.trim().isNotEmpty);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: BestieTokens.fwBold,
              color: colors.textMuted,
              letterSpacing: BestieTokens.lsEyebrow,
            ),
          ),
          if (!hasContent) ...[
            const SizedBox(height: 6),
            Text(empty, style: TextStyle(color: colors.textFaint, fontSize: 13)),
          ] else ...[
            if (time != null && time!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _formatWorkdayTime(time),
                style: TextStyle(
                  color: colors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!,
                  style: TextStyle(color: colors.textFaint, fontSize: 11)),
            ],
            if (body != null && body!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(body!,
                  style: TextStyle(
                      color: colors.textMuted, height: 1.45, fontSize: 13.5)),
            ],
          ],
        ],
      ),
    );
  }
}

String _formatWorkdayTime(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso;
  final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final m = dt.minute.toString().padLeft(2, '0');
  final ap = dt.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ap';
}

String _formatBreakTotal(dynamic seconds) {
  final total = (seconds as num?)?.toInt() ?? 0;
  if (total <= 0) return '';
  final mins = total ~/ 60;
  final secs = total % 60;
  if (mins <= 0) return '$secs sec';
  if (secs == 0) return '$mins min';
  return '$mins min $secs sec';
}

String _lunchDetail(Map<String, dynamic> entry) {
  final note = entry['lunchNote']?.toString().trim() ?? '';
  if (note.isNotEmpty) return note;
  if (entry['lunchStartedAt'] != null && entry['lunchEndedAt'] == null) {
    return 'Lunch in progress';
  }
  if (entry['lunchStartedAt'] != null) return 'Lunch completed';
  return '';
}
