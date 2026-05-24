import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

/// Mobile shell with a premium bottom navigation. Chat is the primary
/// destination, followed by Tasks; deep-links (`/chat/abc`) still land in the
/// right place inside the shell.
class ShellScreen extends ConsumerWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  static const _tabs = [
    _Tab('/chat',      Icons.chat_bubble_outline_rounded,  Icons.chat_bubble_rounded,    'Chat'),
    _Tab('/tasks',     Icons.task_alt_outlined,            Icons.task_alt_rounded,       'Tasks'),
    _Tab('/dashboard', Icons.dashboard_outlined,           Icons.dashboard_rounded,      'Home'),
    _Tab('/meetings',  Icons.videocam_outlined,            Icons.videocam_rounded,       'Meet'),
    _Tab('/more',      Icons.apps_rounded,                 Icons.apps_rounded,           'More'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BestieColors.of(context);
    final location = GoRouterState.of(context).matchedLocation;
    int index = _tabs.indexWhere((t) => location.startsWith(t.path));
    if (index < 0) index = 0;

    return Scaffold(
      extendBody: true,
      backgroundColor: colors.bg,
      body: child,
      bottomNavigationBar: _PremiumBottomNav(
        tabs: _tabs,
        currentIndex: index,
        onTap: (i) {
          if (_tabs[i].path == '/more') {
            _openMore(context);
          } else {
            context.go(_tabs[i].path);
          }
        },
      ),
    );
  }

  void _openMore(BuildContext context) {
    final c = BestieColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) {
        final entries = <_MoreEntry>[
          _MoreEntry(Icons.dashboard_outlined,         'Dashboard',     '/dashboard',     c.brand),
          _MoreEntry(Icons.notifications_outlined,     'Notifications', '/notifications', c.warning),
          _MoreEntry(Icons.event_outlined,             'Calendar',      '/calendar',      c.info),
          _MoreEntry(Icons.history_rounded,            'Call history',  '/calls',         c.success),
          _MoreEntry(Icons.campaign_outlined,          'Announcements', '/announcements', c.accent),
          _MoreEntry(Icons.bookmark_outline_rounded,   'Saved',         '/saved',         c.brand),
          _MoreEntry(Icons.people_outline_rounded,     'Employees',     '/employees',     c.brand),
          _MoreEntry(Icons.business_center_outlined,   'Clients',       '/clients',       c.client),
          _MoreEntry(Icons.headset_mic_outlined,       'Telecaller',    '/telecaller',    c.warning),
          _MoreEntry(Icons.devices_outlined,           'Sessions',      '/sessions',      c.textMuted),
          _MoreEntry(Icons.person_outline_rounded,     'Profile',       '/profile',       c.brandStrong),
          _MoreEntry(Icons.settings_outlined,          'Settings',      '/settings',      c.textSoft),
        ];
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
                    width: 40, height: 4,
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
                    for (final e in entries) _MoreTile(entry: e, colors: c, onTap: () {
                      Navigator.of(ctx).pop();
                      context.go(e.route);
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
}

class _MoreEntry {
  final IconData icon;
  final String label;
  final String route;
  final Color accent;
  const _MoreEntry(this.icon, this.label, this.route, this.accent);
}

class _MoreTile extends StatelessWidget {
  final _MoreEntry entry;
  final BestieColors colors;
  final VoidCallback onTap;
  const _MoreTile({required this.entry, required this.colors, required this.onTap});

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
              width: 46, height: 46,
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

class _Tab {
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _Tab(this.path, this.icon, this.activeIcon, this.label);
}

class _PremiumBottomNav extends StatelessWidget {
  final List<_Tab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _PremiumBottomNav({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          height: 66,
          decoration: BoxDecoration(
            color: isDark
                ? BestieTokens.cSurface.withOpacity(0.78)
                : BestieTokens.cSurface.withOpacity(0.82),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: BestieTokens.cBorder.withOpacity(isDark ? 0.6 : 0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.35 : 0.10),
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
                return Expanded(
                  child: _NavItem(
                    icon: tab.icon,
                    activeIcon: tab.activeIcon,
                    label: tab.label,
                    selected: selected,
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
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> with SingleTickerProviderStateMixin {
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
            BestieTokens.cBrandSoft.withOpacity(0.0),
            BestieTokens.cBrandSoft,
            t,
          )!;
          final iconColor = Color.lerp(
            BestieTokens.cTextMuted,
            BestieTokens.cBrandStrong,
            t,
          )!;
          final labelColor = Color.lerp(
            BestieTokens.cTextMuted,
            BestieTokens.cBrandStrong,
            t,
          )!;

          return Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              padding: EdgeInsets.symmetric(
                horizontal: 10 + 6 * t,
                vertical: 6,
              ),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 1.0 + 0.06 * t,
                    child: Icon(
                      widget.selected ? widget.activeIcon : widget.icon,
                      size: 22,
                      color: iconColor,
                    ),
                  ),
                  ClipRect(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: SizedBox(
                        width: t > 0.05 ? null : 0,
                        child: Padding(
                          padding: EdgeInsets.only(left: 6 * t),
                          child: Opacity(
                            opacity: t,
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                                color: labelColor,
                              ),
                            ),
                          ),
                        ),
                      ),
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
