import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../active_call_state.dart';
import '../state.dart';

/// Mobile shell with role-aware bottom navigation.
///
/// • EMPLOYEE / MANAGER / ADMIN — Chat · Tasks · Home · Meet · More
/// • TELECALLER — Chat · Leads · Home · Calls · More
/// • CLIENT — Chat · Saved · Home · More (no Tasks, no Meet)
///
/// "More" opens a 4-column grid drawer with every other screen.
class ShellScreen extends ConsumerWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  static const _employeeTabs = [
    _Tab('/chat', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,
        'Chat'),
    _Tab('/tasks', Icons.task_alt_outlined, Icons.task_alt_rounded, 'Tasks'),
    _Tab('/attendance', Icons.access_time_rounded,
        Icons.access_time_filled_rounded, 'Workday'),
    _Tab('/meetings', Icons.videocam_outlined, Icons.videocam_rounded, 'Meet'),
    _Tab('/more', Icons.apps_rounded, Icons.apps_rounded, 'More'),
  ];

  static const _telecallerTabs = [
    _Tab('/chat', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,
        'Chat'),
    _Tab('/telecaller', Icons.headset_mic_outlined, Icons.headset_mic_rounded,
        'Leads'),
    _Tab('/dashboard', Icons.dashboard_outlined, Icons.dashboard_rounded,
        'Home'),
    _Tab('/calls', Icons.call_outlined, Icons.call_rounded, 'Calls'),
    _Tab('/more', Icons.apps_rounded, Icons.apps_rounded, 'More'),
  ];

  static const _clientTabs = [
    _Tab('/chat', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,
        'Chat'),
    _Tab('/saved', Icons.bookmark_outline_rounded, Icons.bookmark_rounded,
        'Saved'),
    _Tab('/dashboard', Icons.dashboard_outlined, Icons.dashboard_rounded,
        'Home'),
    _Tab('/more', Icons.apps_rounded, Icons.apps_rounded, 'More'),
  ];

  List<_Tab> _tabsFor(BestieUser? user) {
    if (user == null) return _employeeTabs;
    if (user.isClient) return _clientTabs;
    if (user.role == 'TELECALLER') return _telecallerTabs;
    return _employeeTabs;
  }

  Future<bool> _handleShellBack(BuildContext context, String location) async {
    final router = GoRouter.of(context);
    if (router.canPop()) return true;
    if (location == '/dashboard') return true;
    context.go('/dashboard');
    return false;
  }

  void _openMoreRoute(BuildContext context, String route) {
    if (route == '/dashboard') {
      context.go(route);
      return;
    }
    context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BestieColors.of(context);
    final user = ref.watch(authStoreProvider).user;
    final tabs = _tabsFor(user);
    final router = GoRouter.of(context);
    final location = GoRouterState.of(context).matchedLocation;
    final canPop = router.canPop() || location == '/dashboard';
    int index = tabs.indexWhere((t) => location.startsWith(t.path));
    if (index < 0) index = 0;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleShellBack(context, location);
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: colors.bg,
        body: Stack(
          children: [
            Positioned.fill(child: child),
            Positioned(
              left: 16,
              right: 16,
              bottom: 98 + MediaQuery.of(context).padding.bottom,
              child: _MiniCallBar(colors: colors),
            ),
          ],
        ),
        bottomNavigationBar: _PremiumBottomNav(
          tabs: tabs,
          currentIndex: index,
          onTap: (i) {
            if (tabs[i].path == '/more') {
              _openMore(context, ref, user);
            } else {
              context.go(tabs[i].path);
            }
          },
        ),
      ),
    );
  }

  void _openMore(BuildContext context, WidgetRef ref, BestieUser? user) {
    final c = BestieColors.of(context);
    final entries = _moreEntries(user, c);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  alignment: Alignment.center,
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.borderStrong,
                      borderRadius: BorderRadius.circular(BestieTokens.rPill),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'More',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: BestieTokens.fwBold,
                      color: c.text,
                      letterSpacing: BestieTokens.lsTight,
                    ),
                  ),
                ),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 4,
                  childAspectRatio: 0.95,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final e in entries)
                      _MoreTile(
                          entry: e,
                          colors: c,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _openMoreRoute(context, e.route);
                          }),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Curated list of every nested screen, filtered by role. Each tile shows
  /// even when the related provider has no data so users can still reach it.
  List<_MoreEntry> _moreEntries(BestieUser? user, BestieColors c) {
    final isClient = user?.isClient ?? false;
    final role = user?.role ?? '';
    final isAdmin = role == 'SUPER_ADMIN' || role == 'ADMIN';
    final isTelecaller = role == 'TELECALLER';

    return [
      // Dashboard moved from bottom nav → More since Workday now lives in
      // the bottom-nav slot.
      _MoreEntry(
          Icons.dashboard_outlined, 'Dashboard', '/dashboard', c.brand, true),
      _MoreEntry(Icons.notifications_outlined, 'Notifications',
          '/notifications', c.warning, true),
      _MoreEntry(
          Icons.event_outlined, 'Calendar', '/calendar', c.info, !isClient),
      _MoreEntry(
          Icons.article_outlined, 'Reports', '/reports', c.success, !isClient),
      _MoreEntry(
          Icons.videocam_outlined, 'Meetings', '/meetings', c.brand, !isClient),
      _MoreEntry(Icons.history_rounded, 'Call history', '/calls', c.success,
          !isClient),
      _MoreEntry(Icons.campaign_outlined, 'Announcements', '/announcements',
          c.accent, true),
      _MoreEntry(
          Icons.bookmark_outline_rounded, 'Saved', '/saved', c.brand, true),
      _MoreEntry(Icons.people_outline_rounded, 'Employees', '/employees',
          c.brand, !isClient),
      _MoreEntry(Icons.business_center_outlined, 'Clients', '/clients',
          c.client, isAdmin || role == 'MANAGER'),
      _MoreEntry(Icons.headset_mic_outlined, 'Telecaller', '/telecaller',
          c.warning, isTelecaller || isAdmin),
      _MoreEntry(
          Icons.devices_outlined, 'Sessions', '/sessions', c.textMuted, true),
      _MoreEntry(Icons.person_outline_rounded, 'Profile', '/profile',
          c.brandStrong, true),
      _MoreEntry(
          Icons.settings_outlined, 'Settings', '/settings', c.textSoft, true),
    ].where((e) => e.visible).toList();
  }
}

class _MiniCallBar extends StatefulWidget {
  final BestieColors colors;
  const _MiniCallBar({required this.colors});

  @override
  State<_MiniCallBar> createState() => _MiniCallBarState();
}

class _MiniCallBarState extends State<_MiniCallBar> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _elapsed(DateTime startedAt) {
    final d = DateTime.now().difference(startedAt);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ActiveCallInfo?>(
      valueListenable: ActiveCallState.current,
      builder: (context, call, _) {
        if (call == null) return const SizedBox.shrink();
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.go(call.route),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: widget.colors.surface.withOpacity(0.96),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: widget.colors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: BestieTokens.cSuccess.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    call.mode == 'voice'
                        ? Icons.call_rounded
                        : Icons.videocam_rounded,
                    color: BestieTokens.cSuccess,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        call.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.colors.text,
                          fontWeight: BestieTokens.fwBold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'In call · ${_elapsed(call.startedAt)}',
                        style: TextStyle(
                          color: widget.colors.textMuted,
                          fontSize: 11,
                          fontWeight: BestieTokens.fwSemibold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.open_in_full_rounded, size: 18),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Tab {
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _Tab(this.path, this.icon, this.activeIcon, this.label);
}

class _MoreEntry {
  final IconData icon;
  final String label;
  final String route;
  final Color accent;
  final bool visible;
  const _MoreEntry(
      this.icon, this.label, this.route, this.accent, this.visible);
}

class _MoreTile extends StatelessWidget {
  final _MoreEntry entry;
  final BestieColors colors;
  final VoidCallback onTap;
  const _MoreTile(
      {required this.entry, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: entry.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(BestieTokens.rMd),
              ),
              child: Icon(entry.icon, color: entry.accent, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: colors.text,
                fontWeight: BestieTokens.fwSemibold,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PremiumBottomNav extends ConsumerWidget {
  final List<_Tab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _PremiumBottomNav({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
  });

  /// Total unread channels — DMs + groups that haven't been read by the
  /// current user. Drives the red dot on the Chat tab. Cheap: derived
  /// from the existing channelsProvider so no extra API call.
  int _unreadCount(WidgetRef ref) {
    final me = ref.read(authStoreProvider).user;
    final channels = ref.watch(channelsProvider).asData?.value ?? const [];
    if (me == null) return 0;
    int n = 0;
    for (final c in channels) {
      final members =
          (c['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final mine = members.firstWhere(
        (m) => m['userId'] == me.id,
        orElse: () => const {},
      );
      if (mine.isEmpty) continue;
      if (mine['lastReadAt'] == null) n++;
    }
    return n;
  }

  /// Tasks awaiting my response — assignments in PENDING state. Surfaces
  /// the count as a warning-colored chip on the Tasks tab so users know
  /// they have unaccepted work.
  int _pendingTasks(WidgetRef ref) {
    final me = ref.read(authStoreProvider).user;
    final kanban = ref.watch(tasksKanbanProvider).asData?.value;
    if (me == null || kanban == null) return 0;
    final cols =
        (kanban['columns'] as Map?)?.cast<String, dynamic>() ?? const {};
    int n = 0;
    for (final v in cols.values) {
      for (final t in (v as List).cast<Map<String, dynamic>>()) {
        final assignees =
            (t['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final mine = assignees.firstWhere(
          (a) => (a['user'] as Map?)?['id'] == me.id,
          orElse: () => const {},
        );
        if (mine['state'] == 'PENDING') n++;
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BestieColors.of(context);
    final media = MediaQuery.of(context);
    final isDark = colors.isDark;
    final unread = _unreadCount(ref);
    final pendingTasks = _pendingTasks(ref);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          12 + (media.padding.bottom > 0 ? 0 : 4),
        ),
        child: Container(
          // Vertical icon + label layout needs a touch more breathing room
          // than the prior icon-only design.
          height: 70,
          decoration: BoxDecoration(
            color: colors.surface.withOpacity(isDark ? 0.92 : 0.96),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.border.withOpacity(0.7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.45 : 0.10),
                blurRadius: 24,
                offset: const Offset(0, 12),
                spreadRadius: -4,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Row(
              children: List.generate(tabs.length, (i) {
                final tab = tabs[i];
                final selected = i == currentIndex;
                // Per-tab badges:
                //   Chat   → unread channels (red)
                //   Tasks  → tasks awaiting my accept (warning-colored, see _NavItem)
                int? badge;
                if (tab.path == '/chat' && unread > 0) badge = unread;
                if (tab.path == '/tasks' && pendingTasks > 0)
                  badge = pendingTasks;
                return Expanded(
                  child: _NavItem(
                    icon: tab.icon,
                    activeIcon: tab.activeIcon,
                    label: tab.label,
                    selected: selected,
                    colors: colors,
                    badge: badge,
                    onTap: () => onTap(i),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final BestieColors colors;
  final int? badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
    this.badge,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: widget.selected ? 1.0 : 0.0,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeIn,
  );

  @override
  void didUpdateWidget(covariant _NavItem old) {
    super.didUpdateWidget(old);
    if (widget.selected != old.selected) {
      widget.selected ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(18),
      splashColor: BestieTokens.cBrand.withOpacity(0.10),
      highlightColor: BestieTokens.cBrand.withOpacity(0.04),
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final t = _t.value;
          final pill = Color.lerp(
            widget.colors.brandSoft.withOpacity(0.0),
            widget.colors.brandSoft,
            t,
          )!;
          final iconColor = Color.lerp(
              widget.colors.textMuted, widget.colors.brandStrong, t)!;
          final labelColor = Color.lerp(
              widget.colors.textMuted, widget.colors.brandStrong, t)!;

          return Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: pill,
                borderRadius: BorderRadius.circular(14),
                boxShadow: t > 0.5
                    ? [
                        BoxShadow(
                          color: BestieTokens.cBrand.withOpacity(0.18 * t),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                          spreadRadius: -2,
                        ),
                      ]
                    : const [],
              ),
              // Vertical layout — icon on top, label below — so labels are
              // always visible (typical mobile bottom-nav). Active state
              // adds the brand-soft pill background + filled icon variant.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Transform.scale(
                        scale: 1.0 + 0.06 * t,
                        child: Icon(
                          widget.selected ? widget.activeIcon : widget.icon,
                          size: 22,
                          color: iconColor,
                        ),
                      ),
                      // Unread badge — capped at 99+. Pinned with negative
                      // offsets so it overlaps the icon corner crisply.
                      if (widget.badge != null && widget.badge! > 0)
                        Positioned(
                          top: -4,
                          right: -8,
                          child: Container(
                            constraints: const BoxConstraints(
                                minWidth: 16, minHeight: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: BestieTokens.cDanger,
                              borderRadius:
                                  BorderRadius.circular(BestieTokens.rPill),
                              border: Border.all(
                                  color: widget.colors.surface, width: 2),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              widget.badge! > 99 ? '99+' : '${widget.badge}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: -0.1,
                      color: labelColor,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
