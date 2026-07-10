import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Mobile shell with role-aware bottom navigation (Stitch-styled).
///
/// • EMPLOYEE / MANAGER / ADMIN — Chat · Tasks · Workday · Meet · More
/// • TELECALLER — Chat · Leads · Home · Calls · More
/// • CLIENT — Chat · Saved · Home · More
///
/// "More" opens a grid drawer (Profile, Settings, Employees, etc.).
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

  bool _isRootShellTab(String location) {
    return location == '/chat' ||
        location == '/tasks' ||
        location == '/attendance' ||
        location == '/meetings' ||
        location == '/dashboard' ||
        location == '/telecaller' ||
        location == '/calls' ||
        location == '/saved';
  }

  Future<void> _handleShellBack(BuildContext context, String location) async {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    if (_isRootShellTab(location)) {
      await SystemNavigator.pop();
      return;
    }
    router.go('/chat');
  }

  void _openMoreRoute(BuildContext context, String route) {
    if (route == '/dashboard' ||
        route == '/telecaller' ||
        route == '/calls') {
      context.go(route);
      return;
    }
    context.push(route);
  }

  void _openMore(BuildContext context, WidgetRef ref, BestieUser? user) {
    final c = BestieColors.of(context);
    final entries = _moreEntries(user, c);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.82;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
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
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    mainAxisExtent: 96,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final e in entries)
                        _MoreTile(
                          entry: e,
                          colors: c,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!context.mounted) return;
                              _openMoreRoute(context, e.route);
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<_MoreEntry> _moreEntries(BestieUser? user, BestieColors c) {
    final isClient = user?.isClient ?? false;
    final role = user?.role ?? '';
    final isAdmin = role == 'SUPER_ADMIN' || role == 'ADMIN';
    final isTelecaller = role == 'TELECALLER';

    return [
      _MoreEntry(
          Icons.dashboard_outlined, 'Dashboard', '/dashboard', c.brand, true),
      _MoreEntry(Icons.notifications_outlined, 'Notifications',
          '/notifications', c.warning, true),
      _MoreEntry(
          Icons.event_outlined, 'Calendar', '/calendar', c.info, !isClient),
      _MoreEntry(
          Icons.article_outlined, 'Reports', '/reports', c.success, !isClient),
      _MoreEntry(Icons.history_rounded, 'Call history', '/calls', c.success,
          !isClient),
      _MoreEntry(Icons.download_for_offline_outlined, 'Recordings',
          '/recordings', c.accent, isAdmin),
      _MoreEntry(Icons.login_rounded, 'Login activity', '/login-activity',
          c.info, isAdmin),
      _MoreEntry(Icons.monitor_heart_outlined, 'Work activity',
          '/work-activity', c.brand, isAdmin),
      _MoreEntry(Icons.psychology_outlined, 'AI Review', '/ai-review',
          c.brandStrong, isAdmin),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BestieColors.of(context);
    final user = ref.watch(authStoreProvider).user;
    final tabs = _tabsFor(user);
    final location = GoRouterState.of(context).matchedLocation;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleShellBack(context, location);
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: colors.surface,
        body: child,
        bottomNavigationBar: _StitchBottomNav(
          tabs: tabs,
          currentIndex: tabs.indexWhere((t) => location.startsWith(t.path)),
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

class _StitchBottomNav extends ConsumerWidget {
  final List<_Tab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _StitchBottomNav({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
  });

  int _unreadCount(WidgetRef ref) {
    final channels = ref.watch(channelsProvider).asData?.value ?? const [];
    var n = 0;
    for (final c in channels) {
      n += (c['unreadCount'] as num?)?.toInt() ?? 0;
    }
    return n;
  }

  int _pendingTasks(WidgetRef ref) {
    final me = ref.read(authStoreProvider).user;
    final kanban = ref.watch(tasksKanbanProvider).asData?.value;
    if (me == null || kanban == null) return 0;
    final cols =
        (kanban['columns'] as Map?)?.cast<String, dynamic>() ?? const {};
    var n = 0;
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
    final unread = _unreadCount(ref);
    final pendingTasks = _pendingTasks(ref);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderSoft)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final tab = tabs[i];
              final selected = currentIndex >= 0 && i == currentIndex;
              int? badge;
              if (tab.path == '/chat' && unread > 0) badge = unread;
              if (tab.path == '/tasks' && pendingTasks > 0) {
                badge = pendingTasks;
              }
              return Expanded(
                child: _StitchNavItem(
                  icon: tab.icon,
                  activeIcon: tab.activeIcon,
                  label: tab.label,
                  selected: selected,
                  colors: colors,
                  badge: badge,
                  warningBadge: tab.path == '/tasks' && pendingTasks > 0,
                  onTap: () => onTap(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _StitchNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final BestieColors colors;
  final int? badge;
  final bool warningBadge;
  final VoidCallback onTap;

  const _StitchNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
    this.badge,
    this.warningBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = colors.brand;
    final inactiveColor = colors.textMuted;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                selected ? activeIcon : icon,
                size: 24,
                color: selected ? activeColor : inactiveColor,
              ),
              if (badge != null && badge! > 0)
                Positioned(
                  top: -4,
                  right: -10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: BoxDecoration(
                      color: warningBadge ? colors.warning : colors.brand,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge! > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? activeColor : inactiveColor,
            ),
          ),
        ],
      ),
    );
  }
}
