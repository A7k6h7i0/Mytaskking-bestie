import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Week-view calendar — shows all events (meetings, calls, task deadlines,
/// reminders) for the current 7-day window pulled from `/calendar`.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
  }

  void _shift(int days) => setState(() => _weekStart = _weekStart.add(Duration(days: days)));

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final weekEnd = _weekStart.add(const Duration(days: 7));
    final eventsAsync = ref.watch(calendarRangeProvider((from: _weekStart, to: weekEnd)));

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Calendar'),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _shift(-7)),
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'This week',
            onPressed: () {
              final now = DateTime.now();
              setState(() => _weekStart = DateTime(now.year, now.month, now.day)
                  .subtract(Duration(days: now.weekday - 1)));
            },
          ),
          IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _shift(7)),
        ],
      ),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: c.surface,
          child: Row(children: [
            Text(
              _formatWeek(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: BestieTokens.fwSemibold,
                color: c.text,
                letterSpacing: BestieTokens.lsSnug,
              ),
            ),
          ]),
        ),
        Divider(height: 1, color: c.border),
        Expanded(
          child: eventsAsync.when(
            loading: () => const Center(child: BestieSpinner()),
            error: (e, _) => BestieEmptyState(
              icon: Icons.error_outline_rounded, iconColor: c.danger,
              title: 'Could not load events', description: formatApiError(e),
            ),
            data: (events) {
              if (events.isEmpty) {
                return const BestieEmptyState(
                  icon: Icons.event_outlined,
                  title: 'Nothing scheduled',
                  description: 'No meetings, calls, or deadlines this week.',
                );
              }
              // Group by day-of-week.
              final byDay = <int, List<Map<String, dynamic>>>{};
              for (final e in events) {
                final s = DateTime.tryParse(e['startsAt']?.toString() ?? '');
                if (s == null) continue;
                final dayIdx = s.difference(_weekStart).inDays;
                if (dayIdx < 0 || dayIdx > 6) continue;
                byDay.putIfAbsent(dayIdx, () => []).add(e);
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: 7,
                itemBuilder: (ctx, i) {
                  final day = _weekStart.add(Duration(days: i));
                  final dayEvents = byDay[i] ?? const [];
                  return _DaySection(day: day, events: dayEvents, colors: c);
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  String _formatWeek() {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final end = _weekStart.add(const Duration(days: 6));
    if (_weekStart.month == end.month) {
      return '${months[_weekStart.month - 1]} ${_weekStart.day}–${end.day}, ${_weekStart.year}';
    }
    return '${months[_weekStart.month - 1]} ${_weekStart.day} – ${months[end.month - 1]} ${end.day}';
  }
}

class _DaySection extends StatelessWidget {
  final DateTime day;
  final List<Map<String, dynamic>> events;
  final BestieColors colors;
  const _DaySection({required this.day, required this.events, required this.colors});

  @override
  Widget build(BuildContext context) {
    const wdayName = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final isToday = _sameDay(day, DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(BestieTokens.rMd),
          border: Border.all(color: colors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isToday ? colors.brand : colors.surface2,
                  borderRadius: BorderRadius.circular(BestieTokens.rPill),
                ),
                child: Text(
                  '${wdayName[day.weekday - 1]} ${day.day}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: BestieTokens.fwBold,
                    color: isToday ? Colors.white : colors.textSoft,
                    letterSpacing: BestieTokens.lsWide,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                events.isEmpty ? 'No events' : '${events.length} event${events.length == 1 ? '' : 's'}',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ]),
          ),
          if (events.isNotEmpty)
            for (final e in events) _EventTile(event: e, colors: colors),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _EventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  final BestieColors colors;
  const _EventTile({required this.event, required this.colors});

  @override
  Widget build(BuildContext context) {
    final kind = (event['kind'] ?? 'event').toString().toLowerCase();
    final accent = switch (kind) {
      'meeting'        => colors.brand,
      'call'           => colors.danger,
      'task_deadline'  => colors.warning,
      'reminder'       => colors.success,
      _                 => colors.info,
    };
    final icon = switch (kind) {
      'meeting'        => Icons.videocam_outlined,
      'call'           => Icons.call_outlined,
      'task_deadline'  => Icons.event_busy_outlined,
      'reminder'       => Icons.notifications_active_outlined,
      _                 => Icons.event_outlined,
    };
    final start = DateTime.tryParse(event['startsAt']?.toString() ?? '');
    final timeStr = start == null
        ? ''
        : '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(BestieTokens.rSm),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              (event['title'] ?? '—').toString(),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.text,
                fontWeight: BestieTokens.fwSemibold,
                fontSize: 13.5,
              ),
            ),
            if ((event['subtitle'] ?? '').toString().isNotEmpty)
              Text(event['subtitle'].toString(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textMuted, fontSize: 11)),
          ]),
        ),
        if (timeStr.isNotEmpty)
          Text(timeStr, style: TextStyle(color: colors.textMuted, fontSize: 12)),
      ]),
    );
  }
}
