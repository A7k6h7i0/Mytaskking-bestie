import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_mobile/state.dart';

class DesktopCalendarScreen extends ConsumerStatefulWidget {
  const DesktopCalendarScreen({super.key});

  @override
  ConsumerState<DesktopCalendarScreen> createState() =>
      _DesktopCalendarScreenState();
}

class _DesktopCalendarScreenState extends ConsumerState<DesktopCalendarScreen> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
  }

  void _moveWeek(int delta) =>
      setState(() => _weekStart = _weekStart.add(Duration(days: delta * 7)));

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final weekEnd = _weekStart.add(const Duration(days: 7));
    final eventsAsync =
        ref.watch(calendarRangeProvider((from: _weekStart, to: weekEnd)));
    final tasksAsync = ref.watch(tasksKanbanProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: eventsAsync.when(
            loading: () => const Center(child: BestieSpinner()),
            error: (e, _) => BestieEmptyState(
              icon: Icons.error_outline_rounded,
              iconColor: c.danger,
              title: 'Could not load calendar',
              description: formatApiError(e),
            ),
            data: (events) {
              final tasks = tasksAsync.maybeWhen(
                data: flattenTasksResponse,
                orElse: () => const <Map<String, dynamic>>[],
              );
              final calendarItems = _mergeTaskDeadlines(
                events,
                tasks,
                _weekStart,
                weekEnd,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    weekStart: _weekStart,
                    onPrev: () => _moveWeek(-1),
                    onNext: () => _moveWeek(1),
                    onToday: () {
                      final now = DateTime.now();
                      setState(() => _weekStart = DateTime(
                            now.year,
                            now.month,
                            now.day,
                          ).subtract(Duration(days: now.weekday - 1)));
                    },
                  ),
                  const SizedBox(height: 22),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _WeekGrid(
                            weekStart: _weekStart,
                            events: calendarItems,
                          ),
                        ),
                        const SizedBox(width: 22),
                        SizedBox(
                          width: 270,
                          child: _MonthPanel(
                            weekStart: _weekStart,
                            events: calendarItems,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.weekStart,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime weekStart;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final end = weekStart.add(const Duration(days: 6));
    return Row(
      children: [
        const Text(
          'Calendar',
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const Spacer(),
        _SoftButton(label: 'Today', onTap: onToday),
        const SizedBox(width: 12),
        _RoundIcon(icon: Icons.chevron_left_rounded, onTap: onPrev),
        _RoundIcon(icon: Icons.chevron_right_rounded, onTap: onNext),
        const SizedBox(width: 22),
        Text(
          '${_month(weekStart.month)} ${weekStart.day}-${end.day}, ${weekStart.year}',
          style: const TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF6B7280)),
        const Spacer(),
        const _ModePill(),
      ],
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({required this.weekStart, required this.events});

  final DateTime weekStart;
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    final byDay = <int, List<Map<String, dynamic>>>{};
    for (final event in events) {
      final startsAt = DateTime.tryParse(event['startsAt']?.toString() ?? '');
      if (startsAt == null) continue;
      final index = startsAt.difference(weekStart).inDays;
      if (index < 0 || index > 6) continue;
      byDay.putIfAbsent(index, () => []).add(event);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7ECF7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x110F172A),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 70, child: _TimeColumn()),
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _DayColumn(
                day: weekStart.add(Duration(days: i)),
                events: byDay[i] ?? const [],
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 70),
        for (final hour in const [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18])
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                hour <= 12
                    ? '$hour ${hour == 12 ? 'PM' : 'AM'}'
                    : '${hour - 12} PM',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({required this.day, required this.events});

  final DateTime day;
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    final isToday = _sameDay(day, DateTime.now());
    final sorted = [...events]..sort((a, b) => (a['startsAt'] ?? '')
        .toString()
        .compareTo((b['startsAt'] ?? '').toString()));
    return Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFFEAEFF8))),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 70,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _weekday(day.weekday),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        isToday ? const Color(0xFF4F6BFF) : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: isToday ? Colors.white : const Color(0xFF1F2937),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: List.generate(
                    11,
                    (_) => const Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0xFFEFF3FA)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        for (var i = 0; i < 11; i++)
                          Expanded(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: _eventForHour(sorted, 8 + i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventForHour(List<Map<String, dynamic>> events, int hour) {
    final event = events.cast<Map<String, dynamic>?>().firstWhere(
      (e) {
        final startsAt = DateTime.tryParse(e?['startsAt']?.toString() ?? '');
        return startsAt?.hour == hour;
      },
      orElse: () => null,
    );
    if (event == null) return const SizedBox.shrink();
    final startsAt = DateTime.tryParse(event['startsAt']?.toString() ?? '');
    final kind = (event['kind'] ?? '').toString().toLowerCase();
    final deadlineToday = event['deadlineToday'] == true;
    final color = switch (kind) {
      'call' => const Color(0xFFFFEDF2),
      'meeting' => const Color(0xFFEFF5FF),
      'task_deadline' =>
        deadlineToday ? const Color(0xFFFFE7E7) : const Color(0xFFFFF3D7),
      'reminder' => const Color(0xFFE6FAF2),
      _ => const Color(0xFFF0ECFF),
    };
    final accent = switch (kind) {
      'call' => const Color(0xFFFF5074),
      'meeting' => const Color(0xFF3B82F6),
      'task_deadline' =>
        deadlineToday ? const Color(0xFFE11D48) : const Color(0xFFF59E0B),
      'reminder' => const Color(0xFF10B981),
      _ => const Color(0xFF8B5CF6),
    };
    if (kind == 'task_deadline' && deadlineToday) {
      return _DeadlineCard(event: event, startsAt: startsAt, accent: accent);
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (startsAt != null)
            Text(
              _time(startsAt),
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          Text(
            (event['title'] ?? 'Event').toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF24324B),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeadlineCard extends StatefulWidget {
  const _DeadlineCard({
    required this.event,
    required this.startsAt,
    required this.accent,
  });

  final Map<String, dynamic> event;
  final DateTime? startsAt;
  final Color accent;

  @override
  State<_DeadlineCard> createState() => _DeadlineCardState();
}

class _DeadlineCardState extends State<_DeadlineCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.25, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, _) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE7E7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: widget.accent.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: widget.accent.withValues(alpha: _glow.value * 0.32),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.priority_high_rounded,
                    color: widget.accent, size: 14),
                const SizedBox(width: 4),
                Text(
                  widget.startsAt == null
                      ? 'Deadline today'
                      : _time(widget.startsAt!),
                  style: TextStyle(
                    color: widget.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            Text(
              (widget.event['title'] ?? 'Task deadline').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF7F1D1D),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthPanel extends StatelessWidget {
  const _MonthPanel({required this.weekStart, required this.events});

  final DateTime weekStart;
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    final upcoming = events.take(4).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7ECF7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${_month(weekStart.month)} ${weekStart.year}',
                style: const TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              const Icon(Icons.chevron_left_rounded, color: Color(0xFF94A3B8)),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
          const SizedBox(height: 18),
          _MiniMonth(month: DateTime(weekStart.year, weekStart.month, 1)),
          const SizedBox(height: 28),
          const Text(
            'Upcoming events',
            style: TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 14),
          if (upcoming.isEmpty)
            const Text(
              'No upcoming events this week.',
              style: TextStyle(color: Color(0xFF94A3B8)),
            )
          else
            for (final event in upcoming) _UpcomingEvent(event: event),
          const Spacer(),
          TextButton(
            onPressed: () {},
            child: const Row(
              children: [
                Text('View full calendar'),
                Spacer(),
                Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingEvent extends StatelessWidget {
  const _UpcomingEvent({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final startsAt = DateTime.tryParse(event['startsAt']?.toString() ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const CircleAvatar(radius: 4, backgroundColor: Color(0xFF3D63F4)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (event['title'] ?? 'Event').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (startsAt != null)
                  Text(
                    _time(startsAt),
                    style:
                        const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
              ],
            ),
          ),
          TextButton(onPressed: () {}, child: const Text('Join')),
        ],
      ),
    );
  }
}

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
              .map(
                (d) => Text(
                  d,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List.generate(cellCount, (index) {
            final day = index - leading + 1;
            final inMonth = day >= 1 && day <= daysInMonth;
            final active = inMonth &&
                now.year == month.year &&
                now.month == month.month &&
                day == now.day;
            return Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? const Color(0xFF4F6BFF) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                inMonth ? '$day' : '',
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF475569),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SoftButton extends StatelessWidget {
  const _SoftButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE7ECF7)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      color: const Color(0xFF64748B),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7ECF7)),
      ),
      child: Row(
        children: [
          _mode('Week', true, Icons.view_week_outlined),
          _mode('Month', false, Icons.calendar_month_outlined),
        ],
      ),
    );
  }

  Widget _mode(String label, bool active, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFF1F5FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color:
                  active ? const Color(0xFF3D63F4) : const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFF3D63F4) : const Color(0xFF64748B),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _weekday(int weekday) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

String _month(int month) => const [
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
    ][month - 1];

String _time(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

List<Map<String, dynamic>> _mergeTaskDeadlines(
  List<Map<String, dynamic>> events,
  List<Map<String, dynamic>> tasks,
  DateTime from,
  DateTime to,
) {
  final merged =
      events.map((event) => Map<String, dynamic>.from(event)).toList();
  final now = DateTime.now();
  for (final task in tasks) {
    final due = DateTime.tryParse('${task['dueAt'] ?? ''}')?.toLocal();
    if (due == null || due.isBefore(from) || !due.isBefore(to)) continue;
    final status = '${task['status'] ?? ''}'.toUpperCase();
    if (status.contains('DONE') ||
        status.contains('COMPLETE') ||
        status.contains('CANCEL')) {
      continue;
    }
    merged.add({
      'id': 'task-${task['id'] ?? task['title']}',
      'title': 'Deadline: ${task['title'] ?? 'Task'}',
      'kind': 'task_deadline',
      'startsAt': due.toIso8601String(),
      'deadlineToday': _sameDay(due, now),
    });
  }
  merged.sort((a, b) => '${a['startsAt']}'.compareTo('${b['startsAt']}'));
  return merged;
}
