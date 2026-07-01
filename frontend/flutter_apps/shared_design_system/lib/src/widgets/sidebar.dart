import 'package:flutter/material.dart';
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
    final width = collapsed
        ? BestieTokens.sidebarWCollapsed
        : BestieTokens.sidebarW;
    return AnimatedContainer(
      duration: BestieTokens.dur,
      curve: BestieTokens.ease,
      width: width,
      decoration: const BoxDecoration(
        color: BestieTokens.cSurface,
        border: Border(right: BorderSide(color: BestieTokens.cBorder)),
      ),
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
                          colors: [BestieTokens.cAccent, BestieTokens.cBrand],
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
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: items.map((it) {
                final active = it.route == activeRoute;
                return Material(
                  color: active ? BestieTokens.cBrandSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(BestieTokens.rSm),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(BestieTokens.rSm),
                    onTap: () => onSelect(it.route),
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Icon(
                              it.icon,
                              size: 18,
                              color: active
                                  ? BestieTokens.cBrandStrong
                                  : BestieTokens.cTextSoft,
                            ),
                            if (!collapsed) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  it.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: active
                                        ? BestieTokens.cBrandStrong
                                        : BestieTokens.cTextSoft,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (footer != null) ...[const Divider(height: 1), footer!],
        ],
      ),
    );
  }
}
