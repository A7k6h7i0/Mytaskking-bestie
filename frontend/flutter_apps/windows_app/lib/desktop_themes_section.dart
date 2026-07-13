import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import 'desktop_local_settings.dart';
import 'desktop_theme_color_editor.dart';
import 'desktop_theme_palettes.dart';

class DesktopThemesSection extends ConsumerWidget {
  const DesktopThemesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final selected = DesktopLocalSettings.colorTheme.value;

    return ValueListenableBuilder<Map<DesktopThemeId, Map<String, int>>>(
      valueListenable: DesktopLocalSettings.themeColorOverrides,
      builder: (context, _, __) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      'Themes',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'TOP PICKS',
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textMuted,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 268,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: DesktopThemeId.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final themeId = DesktopThemeId.values[index];
                    final palette = DesktopThemePalettes.paletteFor(
                      themeId,
                      overrides: DesktopLocalSettings.overridesFor(themeId),
                    );
                    final isSelected = themeId == selected;
                    return _ThemeCard(
                      title: themeId.title,
                      subtitle: themeId.subtitle,
                      palette: palette,
                      selected: isSelected,
                      onTap: () => DesktopLocalSettings.setColorTheme(themeId),
                      onEdit: () => showDesktopThemeColorEditor(
                        context,
                        themeId: themeId,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.selected,
    required this.onTap,
    required this.onEdit,
  });

  final String title;
  final String subtitle;
  final BestiePaletteExtension palette;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return SizedBox(
      width: 130,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 210,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: palette.previewGradient,
                  border: Border.all(
                    color: selected ? c.brand : Colors.black.withValues(alpha: 0.05),
                    width: selected ? 2.2 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: c.brand.withValues(alpha: 0.22),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 22,
                      left: 0,
                      right: 0,
                      child: Text(
                        '12:30',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.id == 'orange_milk'
                              ? const Color(0xFFD6336C)
                              : Colors.white,
                          fontSize: 24,
                          fontWeight: palette.id == 'orange_milk'
                              ? FontWeight.w600
                              : FontWeight.w300,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 30,
                          minHeight: 30,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.28),
                          foregroundColor: Colors.white,
                        ),
                        tooltip: 'Edit colors',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_rounded, size: 16),
                      ),
                    ),
                    if (selected)
                      const Positioned(
                        top: 10,
                        right: 10,
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
