import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

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

    // Pad the list bottom past the shell's floating nav (70 + margin +
    // safe-area) so the checkout section clears it — without an empty
    // bottomNavigationBar SizedBox that rendered as a white strip.
    final bottomPad = 70.0 + 24 + MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
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
        title: const Text('Workday'),
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
                  color: c.text,
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
                Text(text, style: TextStyle(color: c.textSoft, fontSize: 13))),
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
                      color: c.text,
                      fontSize: 16,
                      fontWeight: BestieTokens.fwBold),
                  children: [
                    TextSpan(text: '$_streak '),
                    TextSpan(
                      text: '$label streak',
                      style: TextStyle(
                          color: c.textSoft,
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
            style: TextStyle(color: c.text, height: 1.45),
            decoration: InputDecoration(
              hintText:
                  'Write today\'s plan in ≥ $_minWords words. Mention top priorities, dependencies, and what "done" looks like by end of day.',
              hintStyle: TextStyle(color: c.textMuted),
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
      iconColor: c.info,
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
                backgroundColor: onBreak ? c.success : c.info,
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
      iconColor: c.warning,
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
            style: TextStyle(color: c.text),
            decoration: InputDecoration(
              hintText: canEnd
                  ? 'Lunch wrap-up note (optional)'
                  : 'Anything blocking? (optional)',
              hintStyle: TextStyle(color: c.textMuted),
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
                backgroundColor: canEnd ? c.success : c.warning,
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
      iconColor: c.danger,
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
            style: TextStyle(color: c.text, height: 1.45),
            decoration: InputDecoration(
              hintText:
                  'What did you ship today? Mention shipped, blocked, and rolled-over items in ≥ $_minWords words.',
              hintStyle: TextStyle(color: c.textMuted),
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
                backgroundColor: c.danger,
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
                  color: colors.text,
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
                            color: colors.text,
                            letterSpacing: BestieTokens.lsSnug,
                          )),
                      Text(subtitle,
                          style:
                              TextStyle(color: colors.textMuted, fontSize: 12)),
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
            style: TextStyle(color: colors.text, height: 1.45, fontSize: 13.5)),
      ]),
    );
  }
}
