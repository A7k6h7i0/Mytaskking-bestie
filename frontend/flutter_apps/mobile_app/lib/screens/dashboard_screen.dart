import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';
import 'leaderboard_card.dart';

/// Today's `/attendance/today` snapshot — used to power the dashboard
/// check-in banner and the working-hours pill. Cheap, autoDispose so it
/// re-fetches each time the dashboard mounts.
final _dashboardAttendanceProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(apiProvider).attendanceToday();
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStoreProvider).user;
    final overview = ref.watch(dashboardProvider);
    final attendance = ref.watch(_dashboardAttendanceProvider);
    final tasks = ref.watch(tasksKanbanProvider);
    final meetings = ref.watch(meetingsProvider);

    return Scaffold(
      appBar: _appBar(context),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_dashboardAttendanceProvider);
          ref.invalidate(tasksKanbanProvider);
          ref.invalidate(dashboardProvider);
          await ref.read(dashboardProvider.future);
        },
        child: overview.when(
          loading: () => const Center(child: BestieSpinner()),
          error: (e, _) => BestieEmptyState(
            icon: Icons.error_outline,
            iconColor: BestieTokens.cDanger,
            title: 'Couldn\'t load',
            description: formatApiError(e),
          ),
          data: (data) {
            final counts =
                (data['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
            final isAdmin = ['SUPER_ADMIN', 'ADMIN'].contains(user?.role);
            final isClient = user?.isClient ?? false;
            final attendanceData = attendance.asData?.value;
            final tasksData = tasks.asData?.value;
            final todayTasks = _todayTasksFor(tasksData, user?.id);
            // Pre-compute which optional cards actually have content. We
            // intersperse a fixed-height spacer between *visible* sections
            // instead of pairing every card with its own SizedBox — that
            // way an empty meetings/today-tasks card doesn't leave a ghost
            // gap behind in the layout.
            final liveMeetings =
                (meetings.asData?.value ?? const <Map<String, dynamic>>[])
                    .where((m) => m['endedAt'] == null)
                    .toList();
            final sections = <Widget>[
              if (!isClient && _shouldShowCheckInBanner(attendanceData))
                _checkInBanner(context, attendanceData),
              _statsGrid(
                context,
                _statsFor(context, counts,
                    isAdmin: isAdmin, isClient: isClient),
              ),
              if (!isClient && todayTasks.isNotEmpty)
                _todayTasksCard(context, todayTasks),
              if (!isClient && liveMeetings.isNotEmpty)
                _liveMeetingsCard(context, liveMeetings),
              if (!isClient)
                _weeklyStatsCard(context, counts, isAdmin: isAdmin),
              const LeaderboardCard(topN: 5),
              if (isAdmin)
                _activityCard(
                    context, data['recentActivity'] as List? ?? const []),
            ];
            return ListView(
              padding: EdgeInsets.fromLTRB(
                BestieTokens.s4,
                BestieTokens.s4,
                BestieTokens.s4,
                112 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                _greeting(user, attendanceData),
                for (final s in sections) ...[
                  const SizedBox(height: BestieTokens.s3),
                  s,
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    return AppBar(
      elevation: 0,
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const BestieLogo(size: 28, withWordmark: true),
      titleSpacing: 16,
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Search people, messages, files',
          onPressed: () => context.go('/search'),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _greeting(dynamic user, Map<String, dynamic>? attendance) {
    return Row(children: [
      BestieAvatar(
          name: user?.name ?? '—',
          imageUrl: user?.avatarUrl,
          isClient: user?.isClient ?? false,
          size: 44),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(_greetingPrefix(),
                  style: const TextStyle(
                      color: BestieTokens.cTextMuted, fontSize: 12)),
              const SizedBox(width: 6),
              _workingHoursPill(attendance),
            ]),
            BestieUserName(
                name: user?.name ?? 'Friend',
                isClient: user?.isClient ?? false,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      const PulseDot(color: BestieTokens.cSuccess),
    ]);
  }

  /// Time-of-day-aware salutation. Tiny touch, but it makes the dashboard
  /// feel attentive to context instead of static "Good to see you" copy.
  String _greetingPrefix() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Burning the midnight oil';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 21) return 'Good evening';
    return 'Working late';
  }

  /// Compact pill that surfaces how long the user has been clocked in today
  /// (e.g. "On the clock · 3h 12m") so the workday rhythm is always visible
  /// at a glance. Renders nothing when the user hasn't checked in yet or has
  /// already clocked out for the day.
  Widget _workingHoursPill(Map<String, dynamic>? attendance) {
    if (attendance == null) return const SizedBox.shrink();
    final entry = (attendance['entry'] as Map?)?.cast<String, dynamic>();
    final checkInIso = entry?['checkInAt']?.toString();
    final checkOutIso = entry?['checkOutAt']?.toString();
    if (checkInIso == null) return const SizedBox.shrink();
    final checkIn = DateTime.tryParse(checkInIso)?.toLocal();
    if (checkIn == null) return const SizedBox.shrink();
    final end = checkOutIso != null
        ? (DateTime.tryParse(checkOutIso)?.toLocal() ?? DateTime.now())
        : DateTime.now();
    final lunchState = entry?['lunchState']?.toString();
    final live = checkOutIso == null && lunchState != 'STARTED';
    final dur = end.difference(checkIn);
    final h = dur.inHours;
    final m = dur.inMinutes.remainder(60);
    final label = '${h}h ${m}m';
    final color = live ? BestieTokens.cSuccess : BestieTokens.cTextMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(BestieTokens.rPill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  bool _shouldShowCheckInBanner(Map<String, dynamic>? attendance) {
    if (attendance == null) return false;
    final entry = (attendance['entry'] as Map?)?.cast<String, dynamic>();
    final checkedIn = entry?['checkInAt'] != null;
    if (checkedIn) return false;
    // The banner only nags between the configured open hour and noon —
    // before that the screen isn't open yet, after noon the day is
    // arguably gone and the reminder becomes noise.
    final opensHour = (attendance['opensAt'] as Map?)?['hour'] as num?;
    final now = DateTime.now();
    if (opensHour != null && now.hour < opensHour.toInt()) return false;
    if (now.hour >= 18) return false;
    return true;
  }

  Widget _checkInBanner(
      BuildContext context, Map<String, dynamic>? attendance) {
    final minWords = (attendance?['minRequiredWords'] as num?)?.toInt() ?? 10;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        onTap: () => context.go('/attendance'),
        child: Container(
          padding: const EdgeInsets.all(BestieTokens.s3),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [BestieTokens.cBrand, BestieTokens.cAccent],
            ),
            borderRadius: BorderRadius.circular(BestieTokens.rMd),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(BestieTokens.rMd),
              ),
              child:
                  const Icon(Icons.flag_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Plan your day',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Write ≥ $minWords words to check in.',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.85), fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white, size: 14),
          ]),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _todayTasksFor(
      Map<String, dynamic>? data, String? meId) {
    if (data == null || meId == null) return const [];
    final cols = (data['columns'] as Map?)?.cast<String, dynamic>() ?? const {};
    final all = cols.values
        .expand((v) => (v as List).cast<Map<String, dynamic>>())
        .toList();
    final now = DateTime.now();
    bool isTodayOrOverdue(DateTime d) {
      final today = DateTime(now.year, now.month, now.day);
      final dDay = DateTime(d.year, d.month, d.day);
      return !dDay.isAfter(today);
    }

    final mine = all.where((t) {
      final assignees =
          (t['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (!assignees.any((a) => (a['user'] as Map?)?['id'] == meId))
        return false;
      final status = (t['status'] ?? 'TODO').toString();
      if (status == 'DONE' || status == 'CANCELLED') return false;
      final due = DateTime.tryParse('${t['dueAt']}')?.toLocal();
      if (due == null) return false;
      return isTodayOrOverdue(due);
    }).toList();
    mine.sort((a, b) => '${a['dueAt']}'.compareTo('${b['dueAt']}'));
    return mine;
  }

  Widget _todayTasksCard(
      BuildContext context, List<Map<String, dynamic>> tasks) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(BestieTokens.s3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: BestieTokens.cBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.today_rounded,
                size: 18, color: BestieTokens.cWarning),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Due today & overdue',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => context.go('/tasks'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 28),
              ),
              child: const Text('See all'),
            ),
          ]),
          const SizedBox(height: 4),
          for (final t in tasks.take(3))
            Builder(builder: (_) {
              final due = DateTime.tryParse('${t['dueAt']}')?.toLocal();
              final overdue = due != null && due.isBefore(now);
              final hm = due == null
                  ? ''
                  : '${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.push('/tasks/${t['id']}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: overdue
                            ? BestieTokens.cDanger
                            : BestieTokens.cWarning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${t['title'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      overdue ? 'Overdue · $hm' : hm,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: overdue
                            ? BestieTokens.cDanger
                            : BestieTokens.cTextMuted,
                      ),
                    ),
                  ]),
                ),
              );
            }),
          if (tasks.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('+${tasks.length - 3} more',
                  style: const TextStyle(
                      fontSize: 11,
                      color: BestieTokens.cTextMuted,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  List<Widget> _statsFor(BuildContext context, Map<String, dynamic> c,
      {required bool isAdmin, required bool isClient}) {
    Widget tile(IconData icon, String label, dynamic v, Color color) {
      final n = v is num ? v : num.tryParse('$v');
      return Container(
        padding: const EdgeInsets.all(BestieTokens.s3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(BestieTokens.rMd),
          border: Border.all(color: BestieTokens.cBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: BestieTokens.s3),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: BestieTokens.cTextMuted, fontSize: 11)),
                if (n != null)
                  AnimatedCounter(
                      value: n,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700))
                else
                  Text('${v ?? '—'}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      );
    }

    if (isAdmin) {
      return [
        tile(Icons.people_outline, 'Employees', c['employees'],
            BestieTokens.cBrand),
        tile(Icons.manage_accounts_outlined, 'Clients', c['clients'],
            BestieTokens.cClient),
        tile(Icons.task_alt_outlined, 'Tasks open', c['tasksOpen'],
            BestieTokens.cWarning),
        tile(Icons.bolt, 'Done · 7d', c['tasksDoneThisWeek'],
            BestieTokens.cSuccess),
        tile(Icons.call_outlined, 'Calls today', c['callsToday'],
            BestieTokens.cInfo),
        tile(Icons.podcasts, 'Active calls', c['activeCalls'],
            BestieTokens.cAccent),
      ];
    }
    if (isClient) {
      return [
        tile(Icons.chat_bubble_outline, 'Channels', c['channels'],
            BestieTokens.cBrand),
        tile(Icons.notifications_none, 'Unread', c['unreadNotifs'],
            BestieTokens.cWarning),
      ];
    }
    return [
      tile(Icons.task_alt_outlined, 'Open tasks', c['myOpenTasks'],
          BestieTokens.cWarning),
      tile(Icons.check_circle_outline, 'Done · 7d', c['myDoneThisWeek'],
          BestieTokens.cSuccess),
      tile(Icons.chat_bubble_outline, 'Channels', c['activeChannels'],
          BestieTokens.cBrand),
      tile(Icons.notifications_none, 'Unread', c['unreadNotifs'],
          BestieTokens.cInfo),
    ];
  }

  Widget _statsGrid(BuildContext context, List<Widget> children) {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = BestieTokens.s2;
      final tileWidth = (constraints.maxWidth - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children)
            SizedBox(
              width: tileWidth,
              child: child,
            ),
        ],
      );
    });
  }

  /// Compact "Your week in numbers" card — tasks shipped, still open, and a
  /// completion bar. Reuses the counts the dashboard endpoint already
  /// returns so it costs us no extra round trip.
  Widget _weeklyStatsCard(BuildContext context, Map<String, dynamic> counts,
      {required bool isAdmin}) {
    final done = ((isAdmin
                ? counts['tasksDoneThisWeek']
                : counts['myDoneThisWeek']) as num?)
            ?.toInt() ??
        0;
    final open =
        ((isAdmin ? counts['tasksOpen'] : counts['myOpenTasks']) as num?)
                ?.toInt() ??
            0;
    final total = done + open;
    final pct = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(BestieTokens.s3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: BestieTokens.cBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.show_chart_rounded,
                size: 18, color: BestieTokens.cBrand),
            const SizedBox(width: 6),
            const Text('Your week',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${(pct * 100).round()}%',
                style: const TextStyle(
                    color: BestieTokens.cBrand,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _statSpark('Shipped', '$done', BestieTokens.cSuccess),
            const SizedBox(width: 24),
            _statSpark('Open', '$open', BestieTokens.cWarning),
            const SizedBox(width: 24),
            _statSpark('Total', '$total', BestieTokens.cBrand),
          ]),
          const SizedBox(height: 12),
          // Brand-tinted progress bar showing this-week completion ratio.
          ClipRRect(
            borderRadius: BorderRadius.circular(BestieTokens.rPill),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: BestieTokens.cBorder,
              valueColor: const AlwaysStoppedAnimation(BestieTokens.cBrand),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statSpark(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: BestieTokens.cTextMuted,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  /// Lists rooms that are currently live in the workspace, with a one-tap
  /// join button. Hidden entirely when nothing's active so the dashboard
  /// stays calm during quiet hours. Rendered above the daily quote so
  /// "your team is meeting right now" is the most visible affordance.
  Widget _liveMeetingsCard(
      BuildContext context, List<Map<String, dynamic>> all) {
    if (all.isEmpty) return const SizedBox.shrink();
    final live = all.where((m) => m['endedAt'] == null).toList();
    if (live.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(BestieTokens.s3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: BestieTokens.cBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.videocam_rounded,
                size: 18, color: BestieTokens.cSuccess),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Live meetings',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const PulseDot(color: BestieTokens.cSuccess, size: 8),
            const SizedBox(width: 6),
            Text('${live.length}',
                style: const TextStyle(
                    color: BestieTokens.cTextMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          for (final m in live.take(3))
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => context.go('/meetings'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: BestieTokens.cSuccess.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(BestieTokens.rMd),
                    ),
                    child: Icon(
                      (m['mode'] ?? 'VIDEO').toString().toUpperCase() == 'VOICE'
                          ? Icons.call_rounded
                          : Icons.videocam_rounded,
                      size: 18,
                      color: BestieTokens.cSuccess,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m['name'] ?? 'Untitled meeting'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Text(
                          '${(m['_count']?['participants'] ?? 0)} participants',
                          style: const TextStyle(
                              color: BestieTokens.cTextMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => context.go('/meetings'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 0),
                      minimumSize: const Size(0, 30),
                      backgroundColor: BestieTokens.cBrand,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Join',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ]),
              ),
            ),
          if (live.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('+${live.length - 3} more',
                  style: const TextStyle(
                      fontSize: 11,
                      color: BestieTokens.cTextMuted,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _activityCard(BuildContext context, List items) {
    return Container(
      padding: const EdgeInsets.all(BestieTokens.s3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: BestieTokens.cBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(
                child: Text('Recent activity',
                    style: TextStyle(fontWeight: FontWeight.w700))),
            BestieBadge(
                tone: BestieTone.success, dot: true, child: const Text('Live')),
          ]),
          const Divider(),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Quiet so far — activity will land here in realtime.',
                  style: TextStyle(color: BestieTokens.cTextMuted)),
            )
          else
            ...items.take(6).map((a) {
              final actor = (a['actor'] as Map?)?.cast<String, dynamic>();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: BestieTokens.cBrand, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 2, children: [
                      BestieUserName(
                        name: actor?['name'] ?? 'System',
                        isClient: actor?['isClient'] ?? false,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text('${a['kind']}',
                          style: const TextStyle(
                              color: BestieTokens.cTextMuted, fontSize: 12)),
                    ]),
                  ),
                ]),
              );
            }),
        ],
      ),
    );
  }
}
