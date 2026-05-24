import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Performance leaderboard card. Renders as a self-contained block — drop it
/// on the Dashboard, on Profile, or in a desktop sidebar.
///
/// `topN` controls how many rows to show. The Dashboard typically uses 3,
/// a dedicated leaderboard screen could pass 20.
class LeaderboardCard extends ConsumerStatefulWidget {
  final int topN;
  final int sinceDays;
  const LeaderboardCard({super.key, this.topN = 5, this.sinceDays = 30});

  @override
  ConsumerState<LeaderboardCard> createState() => _LeaderboardCardState();
}

class _LeaderboardCardState extends ConsumerState<LeaderboardCard> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(apiProvider).leaderboard(limit: widget.topN, sinceDays: widget.sinceDays);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BestieTokens.s3),
      decoration: BoxDecoration(
        color: BestieTokens.cSurface,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: BestieTokens.cBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.emoji_events_outlined, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(
              'Top performers · ${widget.sinceDays}d',
              style: const TextStyle(fontWeight: FontWeight.w700),
            )),
            const BestieBadge(tone: BestieTone.success, dot: true, child: Text('Live')),
          ]),
          const SizedBox(height: 8),
          FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: BestieSpinner()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Could not load leaderboard: ${formatApiError(snap.error!)}',
                      style: const TextStyle(color: BestieTokens.cDanger, fontSize: 12)),
                );
              }
              final items = (snap.data?['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No completed tasks in this window yet.',
                      style: TextStyle(color: BestieTokens.cTextMuted)),
                );
              }
              return Column(children: [
                for (var i = 0; i < items.length; i++) _row(i, items[i]),
              ]);
            },
          ),
        ],
      ),
    );
  }

  Widget _row(int index, Map<String, dynamic> row) {
    final user = (row['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    final avg = (row['avgScore'] as num?)?.toInt() ?? 0;
    final completed = (row['completed'] as num?)?.toInt() ?? 0;
    final onTimeRate = (row['onTimeRate'] as num?)?.toInt() ?? 0;
    final streak = (row['streak'] as num?)?.toInt() ?? 0;
    final tone = avg >= 80 ? BestieTokens.cSuccess
              : avg >= 50 ? BestieTokens.cWarning
              : BestieTokens.cDanger;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(width: 28, child: _rankBadge(index + 1)),
        BestieAvatar(
          name: user['name'] ?? '?',
          imageUrl: user['avatarUrl'],
          isClient: user['isClient'] ?? false,
          size: 30,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BestieUserName(
                name: user['name'] ?? '',
                isClient: user['isClient'] ?? false,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              Row(children: [
                Text('$completed tasks · $onTimeRate% on time',
                    style: const TextStyle(color: BestieTokens.cTextMuted, fontSize: 11)),
                if (streak > 0) Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.local_fire_department, size: 11, color: Color(0xFFB45309)),
                    Text(' $streak streak',
                        style: const TextStyle(color: Color(0xFFB45309), fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
            ],
          ),
        ),
        BestieProgressRing(value: avg / 100, size: 36, color: tone, label: Text('$avg',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
      ]),
    );
  }

  Widget _rankBadge(int place) {
    if (place > 3) {
      return Text('#$place',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BestieTokens.cTextMuted));
    }
    final color = const [Color(0xFFFACC15), Color(0xFFCBD5E1), Color(0xFFD97706)][place - 1];
    return Container(
      width: 22, height: 22,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text('$place', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

/// A compact "my score" card — shows on the Profile screen.
class MyScoreCard extends ConsumerStatefulWidget {
  final int sinceDays;
  const MyScoreCard({super.key, this.sinceDays = 30});
  @override
  ConsumerState<MyScoreCard> createState() => _MyScoreCardState();
}

class _MyScoreCardState extends ConsumerState<MyScoreCard> {
  Map<String, dynamic>? _mine;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = ref.read(authStoreProvider).user;
    if (me == null) return;
    try {
      // Pull the leaderboard and find my own row. This is cheap (limit 100)
      // and reuses one endpoint instead of adding a per-user one.
      final r = await ref.read(apiProvider).leaderboard(limit: 100, sinceDays: widget.sinceDays);
      final items = (r['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final me2 = ref.read(authStoreProvider).user;
      final mine = items.firstWhere(
        (row) => (row['user'] as Map?)?['id'] == me2?.id,
        orElse: () => const {},
      );
      if (mounted) setState(() { _mine = mine; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(BestieTokens.s3), child: BestieSpinner());
    }
    if (_mine == null || _mine!.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: BestieTokens.s3, vertical: 6),
        padding: const EdgeInsets.all(BestieTokens.s3),
        decoration: BoxDecoration(
          color: BestieTokens.cSurface,
          border: Border.all(color: BestieTokens.cBorder),
          borderRadius: BorderRadius.circular(BestieTokens.rMd),
        ),
        child: Row(children: const [
          Icon(Icons.bolt_outlined, color: BestieTokens.cBrand),
          SizedBox(width: 10),
          Expanded(child: Text(
            'Complete a task to start earning your score.',
            style: TextStyle(color: BestieTokens.cTextMuted),
          )),
        ]),
      );
    }
    final avg = (_mine!['avgScore'] as num?)?.toInt() ?? 0;
    final completed = (_mine!['completed'] as num?)?.toInt() ?? 0;
    final onTimeRate = (_mine!['onTimeRate'] as num?)?.toInt() ?? 0;
    final streak = (_mine!['streak'] as num?)?.toInt() ?? 0;
    final tone = avg >= 80 ? BestieTokens.cSuccess : avg >= 50 ? BestieTokens.cWarning : BestieTokens.cDanger;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: BestieTokens.s3, vertical: 6),
      padding: const EdgeInsets.all(BestieTokens.s3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tone.withOpacity(0.10), Colors.transparent],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        border: Border.all(color: BestieTokens.cBorder),
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
      ),
      child: Row(children: [
        BestieProgressRing(
          value: avg / 100,
          size: 84,
          color: tone,
          label: Text('$avg', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your performance', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('over the last ${widget.sinceDays} days',
                  style: const TextStyle(color: BestieTokens.cTextMuted, fontSize: 11)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                BestieBadge(child: Text('$completed tasks')),
                BestieBadge(tone: BestieTone.info, child: Text('$onTimeRate% on time')),
                if (streak > 0)
                  BestieBadge(tone: BestieTone.warning, child: Text('🔥 $streak streak')),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}
