import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';
import 'leaderboard_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStoreProvider).user;
    final overview = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: _appBar(context),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(dashboardProvider.future),
        child: overview.when(
          loading: () => const Center(child: BestieSpinner()),
          error: (e, _) => BestieEmptyState(
            icon: Icons.error_outline,
            iconColor: BestieTokens.cDanger,
            title: 'Couldn\'t load',
            description: formatApiError(e),
          ),
          data: (data) {
            final counts = (data['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
            final isAdmin = ['SUPER_ADMIN', 'ADMIN'].contains(user?.role);
            final isClient = user?.isClient ?? false;
            return ListView(
              padding: const EdgeInsets.all(BestieTokens.s4),
              children: [
                _greeting(user),
                const SizedBox(height: BestieTokens.s3),
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: BestieTokens.s2,
                  mainAxisSpacing: BestieTokens.s2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  children: _statsFor(context, counts, isAdmin: isAdmin, isClient: isClient),
                ),
                const SizedBox(height: BestieTokens.s4),
                const SizedBox(height: BestieTokens.s3),
                // Performance leaderboard — visible to everyone; useful for both
                // self-comparison and "who shipped this week".
                const LeaderboardCard(topN: 5),
                if (isAdmin) ...[
                  const SizedBox(height: BestieTokens.s3),
                  _activityCard(context, data['recentActivity'] as List? ?? const []),
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

  Widget _greeting(dynamic user) {
    return Row(children: [
      BestieAvatar(name: user?.name ?? '—', imageUrl: user?.avatarUrl, isClient: user?.isClient ?? false, size: 44),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Good to see you', style: TextStyle(color: BestieTokens.cTextMuted, fontSize: 12)),
            BestieUserName(name: user?.name ?? 'Friend',
                isClient: user?.isClient ?? false,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      const PulseDot(color: BestieTokens.cSuccess),
    ]);
  }

  List<Widget> _statsFor(BuildContext context, Map<String, dynamic> c, {required bool isAdmin, required bool isClient}) {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 18, color: color),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: BestieTokens.cTextMuted, fontSize: 11)),
                if (n != null)
                  AnimatedCounter(value: n, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))
                else
                  Text('${v ?? '—'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      );
    }

    if (isAdmin) {
      return [
        tile(Icons.people_outline,         'Employees',          c['employees'],          BestieTokens.cBrand),
        tile(Icons.manage_accounts_outlined,'Clients',            c['clients'],            BestieTokens.cClient),
        tile(Icons.task_alt_outlined,      'Tasks open',         c['tasksOpen'],          BestieTokens.cWarning),
        tile(Icons.bolt,                   'Done · 7d',          c['tasksDoneThisWeek'],  BestieTokens.cSuccess),
        tile(Icons.call_outlined,          'Calls today',        c['callsToday'],         BestieTokens.cInfo),
        tile(Icons.podcasts,               'Active calls',       c['activeCalls'],        BestieTokens.cAccent),
      ];
    }
    if (isClient) {
      return [
        tile(Icons.chat_bubble_outline,    'Channels',           c['channels'],           BestieTokens.cBrand),
        tile(Icons.notifications_none,     'Unread',             c['unreadNotifs'],       BestieTokens.cWarning),
      ];
    }
    return [
      tile(Icons.task_alt_outlined,        'Open tasks',         c['myOpenTasks'],        BestieTokens.cWarning),
      tile(Icons.check_circle_outline,     'Done · 7d',          c['myDoneThisWeek'],     BestieTokens.cSuccess),
      tile(Icons.chat_bubble_outline,      'Channels',           c['activeChannels'],     BestieTokens.cBrand),
      tile(Icons.notifications_none,       'Unread',             c['unreadNotifs'],       BestieTokens.cInfo),
    ];
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
            const Expanded(child: Text('Recent activity', style: TextStyle(fontWeight: FontWeight.w700))),
            BestieBadge(tone: BestieTone.success, dot: true, child: const Text('Live')),
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
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: BestieTokens.cBrand, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 2, children: [
                      BestieUserName(
                        name: actor?['name'] ?? 'System',
                        isClient: actor?['isClient'] ?? false,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text('${a['kind']}', style: const TextStyle(color: BestieTokens.cTextMuted, fontSize: 12)),
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
