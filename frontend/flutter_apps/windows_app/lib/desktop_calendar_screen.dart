import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_mobile/state.dart';

/// Windows calendar — week time-grid + sidebar, matching the Calendar UI HTML.
/// Events: `GET /calendar?from=&to=`. Task deadlines: assigned tasks with
/// `dueAt` not already linked via `event.taskId`.
class DesktopCalendarScreen extends ConsumerStatefulWidget {
  const DesktopCalendarScreen({super.key});

  @override
  ConsumerState<DesktopCalendarScreen> createState() =>
      _DesktopCalendarScreenState();
}

enum _CalendarView { week, month }

class _CalendarEntry {
  const _CalendarEntry({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    required this.kind,
    this.taskId,
    this.callId,
    this.source = 'calendar',
  });

  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final String kind;
  final String? taskId;
  final String? callId;
  final String source;
}

class _DesktopCalendarScreenState
    extends ConsumerState<DesktopCalendarScreen> {
  static const _hourHeight = 80.0;
  static const _startHour = 8;
  static const _endHour = 20;

  late DateTime _weekStart;
  DateTime _sidebarMonth = DateTime.now();
  _CalendarView _view = _CalendarView.week;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    _sidebarMonth = DateTime(now.year, now.month, 1);
  }

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 7));

  DateTime get _rangeFrom => _view == _CalendarView.month
      ? DateTime(_sidebarMonth.year, _sidebarMonth.month, 1)
      : _weekStart;

  DateTime get _rangeTo => _view == _CalendarView.month
      ? DateTime(_sidebarMonth.year, _sidebarMonth.month + 1, 1)
      : _weekEnd;

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _weekStart = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      _sidebarMonth = DateTime(now.year, now.month, 1);
    });
  }

  void _shiftWeek(int delta) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: delta * 7));
      _sidebarMonth = DateTime(_weekStart.year, _weekStart.month, 1);
    });
  }

  List<_CalendarEntry> _mergeEntries(
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> tasks,
    String? meId,
    DateTime rangeFrom,
    DateTime rangeTo,
  ) {
    final linkedTaskIds = events
        .map((e) => e['taskId']?.toString())
        .whereType<String>()
        .toSet();
    final out = <_CalendarEntry>[];

    for (final e in events) {
      final start = DateTime.tryParse('${e['startsAt']}')?.toLocal();
      if (start == null) continue;
      final end = DateTime.tryParse('${e['endsAt']}')?.toLocal() ??
          start.add(const Duration(hours: 1));
      out.add(_CalendarEntry(
        id: e['id']?.toString() ?? start.toIso8601String(),
        title: '${e['title'] ?? 'Event'}',
        startsAt: start,
        endsAt: end.isAfter(start) ? end : start.add(const Duration(hours: 1)),
        allDay: e['allDay'] == true,
        kind: (e['kind'] ?? 'GENERAL').toString(),
        taskId: e['taskId']?.toString(),
        callId: e['callId']?.toString(),
      ));
    }

    if (meId != null) {
      for (final task in tasks) {
        final taskId = task['id']?.toString();
        if (taskId == null || linkedTaskIds.contains(taskId)) continue;
        if (!_isAssignedToMe(task, meId)) continue;
        final due = DateTime.tryParse('${task['dueAt']}')?.toLocal();
        if (due == null) continue;
        if (due.isBefore(rangeFrom) || !due.isBefore(rangeTo)) continue;
        final allDay = due.hour == 0 && due.minute == 0;
        out.add(_CalendarEntry(
          id: 'task:$taskId',
          title: '${task['title'] ?? 'Task'}',
          startsAt: due,
          endsAt: allDay ? due : due.add(const Duration(hours: 1)),
          allDay: allDay,
          kind: 'TASK_DEADLINE',
          taskId: taskId,
          source: 'task',
        ));
      }
    }

    out.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return out;
  }

  Future<void> _createEvent() async {
    final created = await showDialog<_NewEventResult>(
      context: context,
      builder: (_) => _NewEventDialog(initialDay: DateTime.now()),
    );
    if (created == null) return;
    try {
      await ref.read(apiProvider).post('/calendar', body: {
        'title': created.title,
        if (created.description != null) 'description': created.description,
        'startsAt': created.startsAt.toUtc().toIso8601String(),
        if (created.endsAt != null)
          'endsAt': created.endsAt!.toUtc().toIso8601String(),
        'kind': created.kind,
        'allDay': created.allDay,
      });
      ref.invalidate(calendarRangeProvider);
      if (mounted) {
        bestieToast(context, 'Event created', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(
          context,
          'Could not create event',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meId = ref.watch(authStoreProvider).user?.id;
    final eventsAsync =
        ref.watch(calendarRangeProvider((from: _rangeFrom, to: _rangeTo)));
    final tasksAsync = ref.watch(tasksKanbanProvider);

    return ColoredBox(
      color: _CalUi.bgBody,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              weekStart: _weekStart,
              view: _view,
              onToday: _goToday,
              onPrev: () => _shiftWeek(-1),
              onNext: () => _shiftWeek(1),
              onView: (v) => setState(() => _view = v),
              onNewEvent: _createEvent,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: eventsAsync.when(
                loading: () => const Center(child: BestieSpinner()),
                error: (e, _) => BestieEmptyState(
                  icon: Icons.error_outline_rounded,
                  iconColor: _CalUi.statusRed,
                  title: 'Could not load calendar',
                  description: formatApiError(e),
                ),
                data: (events) {
                  final tasks = tasksAsync.asData?.value != null
                      ? flattenTasksResponse(tasksAsync.asData!.value)
                      : const <Map<String, dynamic>>[];
                  final entries = _mergeEntries(
                    events,
                    tasks,
                    meId,
                    _rangeFrom,
                    _rangeTo,
                  );

                  if (_view == _CalendarView.month) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _MonthGridView(
                            month: _sidebarMonth,
                            entries: entries,
                            onPrev: () => setState(() {
                              _sidebarMonth = DateTime(
                                _sidebarMonth.year,
                                _sidebarMonth.month - 1,
                                1,
                              );
                            }),
                            onNext: () => setState(() {
                              _sidebarMonth = DateTime(
                                _sidebarMonth.year,
                                _sidebarMonth.month + 1,
                                1,
                              );
                            }),
                          ),
                        ),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: 300,
                          child: _Sidebar(
                            sidebarMonth: _sidebarMonth,
                            weekStart: _weekStart,
                            entries: entries,
                            onMonthPrev: () => setState(() {
                              _sidebarMonth = DateTime(
                                _sidebarMonth.year,
                                _sidebarMonth.month - 1,
                                1,
                              );
                            }),
                            onMonthNext: () => setState(() {
                              _sidebarMonth = DateTime(
                                _sidebarMonth.year,
                                _sidebarMonth.month + 1,
                                1,
                              );
                            }),
                            onNewEvent: _createEvent,
                            onViewFullSchedule: () =>
                                setState(() => _view = _CalendarView.week),
                            onSelectWeek: (day) {
                              setState(() {
                                _weekStart = DateTime(day.year, day.month, day.day)
                                    .subtract(Duration(days: day.weekday - 1));
                                _view = _CalendarView.week;
                              });
                            },
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _WeekTimeGrid(
                          weekStart: _weekStart,
                          entries: entries,
                          startHour: _startHour,
                          endHour: _endHour,
                          hourHeight: _hourHeight,
                        ),
                      ),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 300,
                        child: _Sidebar(
                          sidebarMonth: _sidebarMonth,
                          weekStart: _weekStart,
                          entries: entries,
                          onMonthPrev: () => setState(() {
                            _sidebarMonth = DateTime(
                              _sidebarMonth.year,
                              _sidebarMonth.month - 1,
                              1,
                            );
                          }),
                          onMonthNext: () => setState(() {
                            _sidebarMonth = DateTime(
                              _sidebarMonth.year,
                              _sidebarMonth.month + 1,
                              1,
                            );
                          }),
                          onNewEvent: _createEvent,
                          onViewFullSchedule: () =>
                              setState(() => _view = _CalendarView.week),
                          onSelectWeek: (day) {
                            setState(() {
                              _weekStart = DateTime(day.year, day.month, day.day)
                                  .subtract(Duration(days: day.weekday - 1));
                            });
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalUi {
  static const bgBody = Color(0xFFF8F9FA);
  static const bgSurface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const textTertiary = Color(0xFF9CA3AF);
  static const borderColor = Color(0xFFF3F4F6);
  static const borderDarker = Color(0xFFE5E7EB);
  static const primaryBlue = Color(0xFF3B82F6);
  static const blueLight = Color(0xFFEFF6FF);
  static const statusRed = Color(0xFFEF4444);
}

class _Header extends StatelessWidget {
  const _Header({
    required this.weekStart,
    required this.view,
    required this.onToday,
    required this.onPrev,
    required this.onNext,
    required this.onView,
    required this.onNewEvent,
  });

  final DateTime weekStart;
  final _CalendarView view;
  final VoidCallback onToday;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<_CalendarView> onView;
  final VoidCallback onNewEvent;

  @override
  Widget build(BuildContext context) {
    final end = weekStart.add(const Duration(days: 6));
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final range = weekStart.month == end.month
        ? '${months[weekStart.month - 1]} ${weekStart.day}–${end.day}, ${weekStart.year}'
        : '${months[weekStart.month - 1]} ${weekStart.day} – ${months[end.month - 1]} ${end.day}, ${weekStart.year}';

    return Row(
      children: [
        const Text(
          'Calendar',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: _CalUi.textPrimary,
          ),
        ),
        const SizedBox(width: 24),
        OutlinedButton(
          onPressed: onToday,
          style: OutlinedButton.styleFrom(
            foregroundColor: _CalUi.textPrimary,
            side: const BorderSide(color: _CalUi.borderDarker),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Today', style: TextStyle(fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 16),
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left_rounded, color: _CalUi.textSecondary),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded, color: _CalUi.textSecondary),
        ),
        const SizedBox(width: 8),
        Row(
          children: [
            Text(
              range,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _CalUi.textPrimary,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: _CalUi.textSecondary, size: 18),
          ],
        ),
        const Spacer(),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: _CalUi.borderDarker),
            borderRadius: BorderRadius.circular(8),
            color: _CalUi.bgSurface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ViewToggleBtn(
                label: 'Week',
                icon: Icons.calendar_view_week_outlined,
                active: view == _CalendarView.week,
                onTap: () => onView(_CalendarView.week),
                showDivider: true,
              ),
              _ViewToggleBtn(
                label: 'Month',
                icon: Icons.calendar_month_outlined,
                active: view == _CalendarView.month,
                onTap: () => onView(_CalendarView.month),
                showDivider: false,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: onNewEvent,
          style: FilledButton.styleFrom(
            backgroundColor: _CalUi.primaryBlue,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New event', style: TextStyle(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

class _ViewToggleBtn extends StatelessWidget {
  const _ViewToggleBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.showDivider,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? _CalUi.blueLight : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: showDivider
                ? const Border(right: BorderSide(color: _CalUi.borderDarker))
                : null,
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: active ? _CalUi.primaryBlue : _CalUi.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: active ? _CalUi.primaryBlue : _CalUi.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekTimeGrid extends StatelessWidget {
  const _WeekTimeGrid({
    required this.weekStart,
    required this.entries,
    required this.startHour,
    required this.endHour,
    required this.hourHeight,
  });

  final DateTime weekStart;
  final List<_CalendarEntry> entries;
  final int startHour;
  final int endHour;
  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final totalHours = endHour - startHour;
    final gridHeight = totalHours * hourHeight;
    final tz = _timezoneLabel();

    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final todayCol = days.indexWhere((d) => _sameDay(d, now));
    final allDay = entries.where((e) => e.allDay).toList();
    final timed = entries.where((e) => !e.allDay).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _CalUi.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _CalUi.borderDarker),
        boxShadow: const [
          BoxShadow(color: Color(0x05000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 70,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tz,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _CalUi.textTertiary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    for (final day in days)
                      Expanded(
                        child: _DayHeaderCell(day: day, now: now),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 1, color: _CalUi.borderDarker),
          _AllDayRow(weekStart: weekStart, entries: allDay),
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                height: gridHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 70,
                      child: Column(
                        children: [
                          for (int h = startHour; h < endHour; h++)
                            SizedBox(
                              height: hourHeight,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 0, right: 8),
                                  child: Text(
                                    _formatHourLabel(h),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: _CalUi.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final colWidth = constraints.maxWidth / 7;
                          return Stack(
                            children: [
                              Row(
                                children: [
                                  for (int col = 0; col < 7; col++)
                                    SizedBox(
                                      width: colWidth,
                                      child: Column(
                                        children: List.generate(
                                          totalHours,
                                          (_) => Container(
                                            height: hourHeight,
                                            decoration: const BoxDecoration(
                                              border: Border(
                                                right: BorderSide(
                                                  color: _CalUi.borderDarker,
                                                ),
                                                bottom: BorderSide(
                                                  color: _CalUi.borderColor,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              for (int col = 0; col < 7; col++)
                                ..._eventsForColumn(
                                  col,
                                  timed,
                                  colWidth,
                                  startHour,
                                  hourHeight,
                                ).map(
                                  (layout) => Positioned(
                                    left: layout.left,
                                    width: layout.width,
                                    top: layout.top,
                                    height: layout.height,
                                    child: _TimedEventBlock(entry: layout.entry),
                                  ),
                                ),
                              if (todayCol >= 0)
                                Positioned(
                                  left: todayCol * colWidth,
                                  width: colWidth,
                                  top: _timeToOffset(now, startHour, hourHeight),
                                  child: _CurrentTimeLine(
                                    label: _formatClock(now),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_EventLayout> _eventsForColumn(
    int col,
    List<_CalendarEntry> timed,
    double colWidth,
    int startHour,
    double hourHeight,
  ) {
    final day = weekStart.add(Duration(days: col));
    final dayEvents = timed.where((e) => _sameDay(e.startsAt, day)).toList();
    final count = dayEvents.length;
    return [
      for (int i = 0; i < dayEvents.length; i++)
        _layoutEvent(
          dayEvents[i],
          col,
          i,
          count,
          colWidth,
          startHour,
          hourHeight,
        ),
    ];
  }

  _EventLayout _layoutEvent(
    _CalendarEntry e,
    int col,
    int index,
    int count,
    double colWidth,
    int startHour,
    double hourHeight,
  ) {
    const inset = 4.0;
    final width = count <= 1
        ? colWidth - inset * 2
        : (colWidth - inset * 2) / count;
    final left = col * colWidth + inset + index * width;
    final top = _timeToOffset(e.startsAt, startHour, hourHeight);
    final bottom = _timeToOffset(e.endsAt, startHour, hourHeight);
    return _EventLayout(
      entry: e,
      left: left,
      width: width - 2,
      top: top.clamp(0, double.infinity),
      height: (bottom - top).clamp(40, double.infinity),
    );
  }
}

class _EventLayout {
  const _EventLayout({
    required this.entry,
    required this.left,
    required this.width,
    required this.top,
    required this.height,
  });
  final _CalendarEntry entry;
  final double left;
  final double width;
  final double top;
  final double height;
}

class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({required this.day, required this.now});

  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final isToday = _sameDay(day, now);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: _CalUi.borderDarker)),
      ),
      child: Column(
        children: [
          Text(
            names[day.weekday - 1],
            style: TextStyle(
              fontSize: 13,
              fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
              color: isToday ? _CalUi.primaryBlue : _CalUi.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isToday ? _CalUi.primaryBlue : Colors.transparent,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isToday ? Colors.white : _CalUi.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllDayRow extends StatelessWidget {
  const _AllDayRow({required this.weekStart, required this.entries});

  final DateTime weekStart;
  final List<_CalendarEntry> entries;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            width: 70,
            child: Padding(
              padding: EdgeInsets.only(top: 16, right: 8),
              child: Text(
                'all-day',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: _CalUi.textSecondary),
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (int i = 0; i < 7; i++)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: i == 6
                                ? Colors.transparent
                                : _CalUi.borderDarker,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final e in entries.where((x) =>
                              _sameDay(
                                  x.startsAt, weekStart.add(Duration(days: i)))))
                            _AllDayChip(entry: e),
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
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.entry});

  final _CalendarEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteForKind(entry.kind);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: palette.fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: palette.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimedEventBlock extends StatelessWidget {
  const _TimedEventBlock({required this.entry});

  final _CalendarEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteForKind(entry.kind);
    return Material(
      color: palette.bg,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => _openEntry(context, entry),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatClock(entry.startsAt),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: palette.fg.withValues(alpha: 0.85),
                    ),
                  ),
                  Icon(_iconForKind(entry.kind), size: 12, color: palette.fg),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: palette.fg,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentTimeLine extends StatelessWidget {
  const _CurrentTimeLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -60,
            top: -10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: _CalUi.statusRed,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            left: -4,
            top: -3,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: _CalUi.statusRed,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned.fill(
            child: Container(color: _CalUi.statusRed),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.sidebarMonth,
    required this.weekStart,
    required this.entries,
    required this.onMonthPrev,
    required this.onMonthNext,
    required this.onNewEvent,
    required this.onViewFullSchedule,
    required this.onSelectWeek,
  });

  final DateTime sidebarMonth;
  final DateTime weekStart;
  final List<_CalendarEntry> entries;
  final VoidCallback onMonthPrev;
  final VoidCallback onMonthNext;
  final VoidCallback onNewEvent;
  final VoidCallback onViewFullSchedule;
  final ValueChanged<DateTime> onSelectWeek;

  @override
  Widget build(BuildContext context) {
    final upcoming = entries
        .where((e) => e.startsAt.isAfter(DateTime.now().subtract(const Duration(hours: 1))))
        .take(8)
        .toList();

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _CalUi.bgSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _CalUi.borderDarker),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MiniCalendar(
                        month: sidebarMonth,
                        weekStart: weekStart,
                        entries: entries,
                        onPrev: onMonthPrev,
                        onNext: onMonthNext,
                        onSelectDay: onSelectWeek,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Upcoming',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _CalUi.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: upcoming.isEmpty
                            ? const Text(
                                'No upcoming events this week.',
                                style: TextStyle(
                                  color: _CalUi.textSecondary,
                                  fontSize: 13,
                                ),
                              )
                            : ListView.separated(
                                itemCount: upcoming.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 16),
                                itemBuilder: (_, i) =>
                                    _UpcomingRow(entry: upcoming[i]),
                              ),
                      ),
                      Material(
                        color: _CalUi.bgBody,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: onViewFullSchedule,
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'View full schedule',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _CalUi.primaryBlue,
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded,
                                    color: _CalUi.primaryBlue, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Material(
            color: _CalUi.primaryBlue,
            borderRadius: BorderRadius.circular(12),
            elevation: 4,
            shadowColor: _CalUi.primaryBlue.withValues(alpha: 0.3),
            child: InkWell(
              onTap: onNewEvent,
              borderRadius: BorderRadius.circular(12),
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.add, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniCalendar extends StatelessWidget {
  const _MiniCalendar({
    required this.month,
    required this.weekStart,
    required this.entries,
    required this.onPrev,
    required this.onNext,
    required this.onSelectDay,
  });

  final DateTime month;
  final DateTime weekStart;
  final List<_CalendarEntry> entries;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    final cells = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final weekEnd = weekStart.add(const Duration(days: 6));

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${months[month.month - 1]} ${month.year}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: onPrev,
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('M', style: TextStyle(fontSize: 10, color: _CalUi.textSecondary)),
            Text('T', style: TextStyle(fontSize: 10, color: _CalUi.textSecondary)),
            Text('W', style: TextStyle(fontSize: 10, color: _CalUi.textSecondary)),
            Text('T', style: TextStyle(fontSize: 10, color: _CalUi.textSecondary)),
            Text('F', style: TextStyle(fontSize: 10, color: _CalUi.textSecondary)),
            Text('S', style: TextStyle(fontSize: 10, color: _CalUi.textSecondary)),
            Text('S', style: TextStyle(fontSize: 10, color: _CalUi.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 8,
          ),
          itemCount: cells,
          itemBuilder: (_, index) {
            final dayNumber = index - leading + 1;
            final inMonth = dayNumber >= 1 && dayNumber <= daysInMonth;
            if (!inMonth) return const SizedBox.shrink();
            final date = DateTime(month.year, month.month, dayNumber);
            final inWeek = !date.isBefore(weekStart) && !date.isAfter(weekEnd);
            final isToday = _sameDay(date, DateTime.now());
            final hasEvents =
                entries.any((e) => _sameDay(e.startsAt, date));
            return GestureDetector(
              onTap: () => onSelectDay(date),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (inWeek)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _CalUi.blueLight,
                          borderRadius: BorderRadius.horizontal(
                            left: date.weekday == 1
                                ? const Radius.circular(14)
                                : Radius.zero,
                            right: date.weekday == 7
                                ? const Radius.circular(14)
                                : Radius.zero,
                          ),
                        ),
                      ),
                    ),
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isToday ? _CalUi.primaryBlue : Colors.transparent,
                    ),
                    child: Text(
                      '$dayNumber',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isToday
                            ? Colors.white
                            : inMonth
                                ? _CalUi.textPrimary
                                : _CalUi.borderDarker,
                      ),
                    ),
                  ),
                  if (hasEvents && !isToday)
                    Positioned(
                      bottom: 0,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: _CalUi.primaryBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.entry});

  final _CalendarEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteForKind(entry.kind);
    return Row(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(color: palette.fg, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _CalUi.textPrimary,
                      ),
                    ),
                    Text(
                      '${_formatUpcomingWhen(entry.startsAt)} · ${_formatClock(entry.startsAt)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: _CalUi.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_canJoin(entry))
          TextButton(
            onPressed: () => _openEntry(context, entry),
            style: TextButton.styleFrom(
              backgroundColor: _CalUi.blueLight,
              foregroundColor: _CalUi.primaryBlue,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              'Join',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}

class _MonthGridView extends StatelessWidget {
  const _MonthGridView({
    required this.month,
    required this.entries,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final List<_CalendarEntry> entries;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _CalUi.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _CalUi.borderDarker),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${month.year}-${month.month.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
                    IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
                  ],
                ),
              ],
            ),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.1,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: daysInMonth,
                itemBuilder: (_, i) {
                  final day = i + 1;
                  final date = DateTime(month.year, month.month, day);
                  final dayEvents =
                      entries.where((e) => _sameDay(e.startsAt, date)).toList();
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: _CalUi.borderDarker),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$day', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Expanded(
                          child: ListView(
                            children: dayEvents
                                .take(3)
                                .map((e) => Text(
                                      e.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: _paletteForKind(e.kind).fg,
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewEventResult {
  const _NewEventResult({
    required this.title,
    this.description,
    required this.startsAt,
    this.endsAt,
    required this.kind,
    this.allDay = false,
  });
  final String title;
  final String? description;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String kind;
  final bool allDay;
}

class _NewEventDialog extends StatefulWidget {
  const _NewEventDialog({required this.initialDay});

  final DateTime initialDay;

  @override
  State<_NewEventDialog> createState() => _NewEventDialogState();
}

class _NewEventDialogState extends State<_NewEventDialog> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  late DateTime _start;
  DateTime? _end;
  String _kind = 'MEETING';
  bool _allDay = false;

  @override
  void initState() {
    super.initState();
    _start = DateTime(
      widget.initialDay.year,
      widget.initialDay.month,
      widget.initialDay.day,
      10,
      0,
    );
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    if (_allDay) {
      setState(() => _start = DateTime(date.year, date.month, date.day));
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _start.hour, minute: _start.minute),
    );
    if (time == null) return;
    setState(() => _start = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New event'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _kind,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'MEETING', child: Text('Meeting')),
                DropdownMenuItem(value: 'CALL', child: Text('Call')),
                DropdownMenuItem(value: 'REMINDER', child: Text('Reminder')),
                DropdownMenuItem(value: 'GENERAL', child: Text('General')),
              ],
              onChanged: (v) => setState(() => _kind = v ?? 'MEETING'),
            ),
            SwitchListTile(
              title: const Text('All day'),
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
            ),
            ListTile(
              title: const Text('Starts'),
              subtitle: Text(_start.toLocal().toString().split('.').first),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickStart,
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
          onPressed: _title.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _NewEventResult(
                      title: _title.text.trim(),
                      description:
                          _desc.text.trim().isEmpty ? null : _desc.text.trim(),
                      startsAt: _start,
                      endsAt: _end,
                      kind: _kind,
                      allDay: _allDay,
                    ),
                  ),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _EventPalette {
  const _EventPalette(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

_EventPalette _paletteForKind(String kind) {
  switch (kind.toUpperCase()) {
    case 'MEETING':
      return const _EventPalette(Color(0xFFF3E8FF), Color(0xFF7E22CE));
    case 'CALL':
      return const _EventPalette(Color(0xFFFCE7F3), Color(0xFFDB2777));
    case 'TASK_DEADLINE':
      return const _EventPalette(Color(0xFFFEF9C3), Color(0xFFCA8A04));
    case 'REMINDER':
      return const _EventPalette(Color(0xFFDCFCE7), Color(0xFF16A34A));
    case 'GENERAL':
      return const _EventPalette(Color(0xFFE0F2FE), Color(0xFF0284C7));
    default:
      return const _EventPalette(Color(0xFFFFEDD5), Color(0xFFEA580C));
  }
}

IconData _iconForKind(String kind) {
  switch (kind.toUpperCase()) {
    case 'MEETING':
      return Icons.videocam_outlined;
    case 'CALL':
      return Icons.call_outlined;
    case 'TASK_DEADLINE':
      return Icons.assignment_outlined;
    case 'REMINDER':
      return Icons.notifications_outlined;
    default:
      return Icons.event_outlined;
  }
}

bool _canJoin(_CalendarEntry entry) {
  return entry.callId != null ||
      entry.kind.toUpperCase() == 'CALL' ||
      entry.kind.toUpperCase() == 'MEETING';
}

void _openEntry(BuildContext context, _CalendarEntry entry) {
  if (entry.taskId != null) {
    context.push('/tasks/${entry.taskId}');
    return;
  }
  if (entry.callId != null) {
    context.go('/call/${entry.callId}?mode=video');
  }
}

bool _isAssignedToMe(Map<String, dynamic> task, String meId) {
  final assignees =
      (task['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  return assignees.any((a) {
    final uid = (a['user'] as Map?)?['id']?.toString() ?? a['userId']?.toString();
    return uid == meId;
  });
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

double _timeToOffset(DateTime time, int startHour, double hourHeight) {
  final minutes = (time.hour - startHour) * 60 + time.minute;
  return (minutes / 60) * hourHeight;
}

String _formatHourLabel(int hour) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  final suffix = hour >= 12 ? 'PM' : 'AM';
  return '$h $suffix';
}

String _formatClock(DateTime dt) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  final suffix = dt.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $suffix';
}

String _formatUpcomingWhen(DateTime dt) {
  final now = DateTime.now();
  if (_sameDay(dt, now)) return 'Today';
  if (_sameDay(dt, now.add(const Duration(days: 1)))) return 'Tomorrow';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}';
}

String _timezoneLabel() {
  final offset = DateTime.now().timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hours = offset.inHours.abs();
  final minutes = (offset.inMinutes.abs() % 60);
  return 'GMT$sign$hours:${minutes.toString().padLeft(2, '0')}';
}
