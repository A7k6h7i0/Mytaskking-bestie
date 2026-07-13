import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;
import 'package:mytaskking_design/mytaskking_design.dart';

import 'mobile_local_settings.dart';
import 'mobile_theme_palettes.dart';
import 'state.dart' hide ThemeMode;

class MobileThemesSection extends ConsumerWidget {
  const MobileThemesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    return ValueListenableBuilder<core.ThemeMode>(
      valueListenable: MobileLocalSettings.themeMode,
      builder: (context, mode, _) {
        return ValueListenableBuilder<MobileThemeId>(
          valueListenable: MobileLocalSettings.colorTheme,
          builder: (context, selected, __) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appearance',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<core.ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: core.ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: core.ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: core.ThemeMode.system,
                        label: Text('Auto'),
                        icon: Icon(Icons.brightness_auto_outlined, size: 16),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) async {
                      final next = s.first;
                      await MobileLocalSettings.setThemeMode(next);
                      ref.read(themeModeProvider.notifier).state = next;
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Color themes',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 132,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: MobileThemeId.values.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final themeId = MobileThemeId.values[index];
                        final palette =
                            MobileThemePalettes.paletteFor(themeId);
                        final isSelected = themeId == selected;
                        return GestureDetector(
                          onTap: () async {
                            await MobileLocalSettings.setColorTheme(themeId);
                            ref.invalidate(themeModeProvider);
                          },
                          child: Container(
                            width: 112,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(BestieTokens.rMd),
                              border: Border.all(
                                color: isSelected
                                    ? palette.brand
                                    : c.border,
                                width: isSelected ? 2 : 1,
                              ),
                              gradient: palette.previewGradient,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  themeId.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: palette.text,
                                  ),
                                ),
                                const Spacer(),
                                if (isSelected)
                                  Icon(Icons.check_circle,
                                      size: 16, color: palette.brand),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
