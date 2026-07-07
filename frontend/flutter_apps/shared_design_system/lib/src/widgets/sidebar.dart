import 'package:flutter/material.dart';
import '../colors.dart';
import '../tokens.dart';

class BestieSidebarItem {
  final IconData icon;
  final String label;
  final String route;
  const BestieSidebarItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}

class BestieSidebar extends StatelessWidget {
  final List<BestieSidebarItem> items;
  final String activeRoute;
  final void Function(String route) onSelect;
  final Widget? footer;
  final Widget? header;
  final bool collapsed;

  const BestieSidebar({
    super.key,
    required this.items,
    required this.activeRoute,
    required this.onSelect,
    this.footer,
    this.header,
    this.collapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final width =
        collapsed ? BestieTokens.sidebarWCollapsed : BestieTokens.sidebarW;
    return AnimatedContainer(
      duration: BestieTokens.dur,
      curve: BestieTokens.ease,
      width: width,
      padding: const EdgeInsets.all(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors.isDark
                ? [
                    colors.surface.withOpacity(0.96),
                    colors.surface2.withOpacity(0.98),
                  ]
                : [
                    Colors.white.withOpacity(0.92),
                    const Color(0xFFF6FAFF).withOpacity(0.92),
                  ],
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: colors.border),
          boxShadow: colors.shadowPop,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Column(
            children: [
              header ??
                  Padding(
                    padding: const EdgeInsets.all(BestieTokens.s3),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF08307A),
                                Color(0xFF0C4FBF),
                              ],
                            ),
                          ),
                        ),
                        if (!collapsed) ...[
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'MyTaskKing',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              Divider(height: 1, color: colors.borderSoft),
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  children: items.map((it) {
                    final active = it.route == activeRoute;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: active
                              ? const LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Color(0xFF062E78),
                                    Color(0xFF0A4AA6),
                                  ],
                                )
                              : null,
                          color: active ? null : Colors.transparent,
                          borderRadius: BorderRadius.circular(BestieTokens.rMd),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF062E78)
                                        .withOpacity(0.18),
                                    blurRadius: 18,
                                    offset: const Offset(0, 10),
                                  ),
                                ]
                              : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(BestieTokens.rMd),
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(BestieTokens.rMd),
                            onTap: () => onSelect(it.route),
                            child: SizedBox(
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 13,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    Icon(
                                      it.icon,
                                      size: 18,
                                      color: active
                                          ? Colors.white
                                          : colors.textSoft,
                                    ),
                                    if (!collapsed) ...[
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          it.label,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: active
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            color: active
                                                ? Colors.white
                                                : colors.textSoft,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (footer != null) ...[
                Divider(height: 1, color: colors.borderSoft),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
