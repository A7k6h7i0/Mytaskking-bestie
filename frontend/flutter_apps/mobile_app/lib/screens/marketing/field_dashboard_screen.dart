import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import 'field_gps_tracker.dart';
import 'field_sync_service.dart';

/// Field executive / manager home — visits, outlets, orders at a glance.
class FieldDashboardScreen extends ConsumerStatefulWidget {
  const FieldDashboardScreen({super.key});

  @override
  ConsumerState<FieldDashboardScreen> createState() =>
      _FieldDashboardScreenState();
}

class _FieldDashboardScreenState extends ConsumerState<FieldDashboardScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _activeVisit;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FieldSyncService.syncAll(ref.read(apiProvider)).catchError((_) {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FieldSyncService.syncAll(ref.read(apiProvider)).catchError((_) {});
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final results = await Future.wait([
        api.marketingDashboard(),
        api.getActiveFieldVisit(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _activeVisit = results[1];
        _loading = false;
      });
      if (_activeVisit != null) {
        final settings = await ref.read(apiProvider).marketingFieldSettings();
        final interval =
            (settings['gpsIntervalMovingSeconds'] as num?)?.toInt() ?? 120;
        FieldGpsTracker.instance
            .start(ref.read(apiProvider), intervalSeconds: interval);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = formatApiError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final user = ref.watch(authStoreProvider).user;
    final isManager = user?.isFieldManager ?? false;

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: Text(isManager ? 'Field team' : 'Field dashboard'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: BestieSpinner())
            : _error != null
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(_error!, style: TextStyle(color: c.danger)),
                            const SizedBox(height: 12),
                            FilledButton(onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      Text(
                        'Hello, ${user?.name ?? 'there'}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isManager
                            ? 'Monitor outlets, visits, and orders for your team.'
                            : 'Your daily field activity overview.',
                        style: TextStyle(color: c.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      if (_activeVisit != null) ...[
                        _activeVisitCard(c),
                        const SizedBox(height: 16),
                      ],
                      _statsGrid(c),
                      const SizedBox(height: 20),
                      Text('Quick actions',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: c.text)),
                      const SizedBox(height: 10),
                      _actionTile(
                        c,
                        icon: Icons.storefront_outlined,
                        label: 'Outlets',
                        onTap: () => context.go('/marketing/outlets'),
                      ),
                      _actionTile(
                        c,
                        icon: Icons.search_rounded,
                        label: 'Shop search',
                        subtitle: 'Find businesses via directory',
                        onTap: () => context.go('/marketing/shops'),
                      ),
                      if (isManager)
                        _actionTile(
                          c,
                          icon: Icons.groups_outlined,
                          label: 'Team visits',
                          onTap: () => context.go('/field/manager'),
                        ),
                      _actionTile(
                        c,
                        icon: Icons.work_outline_rounded,
                        label: 'Field HR',
                        subtitle: 'Expenses, leaves, routes',
                        onTap: () => context.go('/field/hr'),
                      ),
                      _actionTile(
                        c,
                        icon: Icons.receipt_long_outlined,
                        label: 'Orders',
                        onTap: () => context.go('/marketing/orders'),
                      ),
                      _actionTile(
                        c,
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Team chat',
                        onTap: () => context.go('/chat'),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _activeVisitCard(BestieColors c) {
    final outlet = (_activeVisit!['outlet'] as Map?)?.cast<String, dynamic>();
    final outletId = _activeVisit!['outletId']?.toString() ??
        outlet?['id']?.toString();
    final name = outlet?['name']?.toString() ?? 'Outlet';
    return Material(
      color: c.successSoft,
      borderRadius: BorderRadius.circular(BestieTokens.rLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        onTap: outletId == null ? null : () => context.push('/marketing/outlets/$outletId'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.place_rounded, color: c.success),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Visit in progress',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: c.text)),
                    Text(name,
                        style: TextStyle(color: c.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Text('Tap to complete',
                  style: TextStyle(
                      color: c.brand, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsGrid(BestieColors c) {
    final s = _stats ?? const {};
    final cards = [
      ('Outlets', s['outlets']?.toString() ?? '0', Icons.store_mall_directory_outlined),
      ('Visits today', s['visitsToday']?.toString() ?? '0', Icons.place_outlined),
      ('Open visits', s['openVisits']?.toString() ?? '0', Icons.timelapse_rounded),
      ('Orders today', s['ordersToday']?.toString() ?? '0', Icons.receipt_long_outlined),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: [
        for (final card in cards)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(BestieTokens.rLg),
              border: Border.all(color: c.borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(card.$3, color: c.brand),
                const Spacer(),
                Text(card.$2,
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: c.text)),
                Text(card.$1,
                    style: TextStyle(color: c.textMuted, fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _actionTile(
    BestieColors c, {
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.surface2,
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        child: ListTile(
          leading: Icon(icon, color: c.brand),
          title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
          subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: c.textMuted, fontSize: 12)) : null,
          trailing: Icon(Icons.chevron_right_rounded, color: c.textMuted),
          onTap: onTap,
        ),
      ),
    );
  }
}
