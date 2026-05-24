import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bestie_design/bestie_design.dart';

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
    _Tab('/profile',   Icons.person_outline_rounded,       Icons.person_rounded,         'Me'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    int index = _tabs.indexWhere((t) => location.startsWith(t.path));
    if (index < 0) index = 0;

    return Scaffold(
      extendBody: true,
      backgroundColor: BestieTokens.cBg,
      body: child,
      bottomNavigationBar: _PremiumBottomNav(
        tabs: _tabs,
        currentIndex: index,
        onTap: (i) => context.go(_tabs[i].path),
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
