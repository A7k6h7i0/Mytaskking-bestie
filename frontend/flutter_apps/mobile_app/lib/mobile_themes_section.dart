import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;
import 'package:mytaskking_design/mytaskking_design.dart';

import 'branding.dart';
import 'mobile_local_settings.dart';
import 'mobile_appearance_providers.dart';
import 'mobile_theme_color_editor.dart';
import 'mobile_theme_palettes.dart';
import 'state.dart' hide ThemeMode;

class MobileThemesSection extends ConsumerWidget {
  const MobileThemesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final me = ref.watch(authStoreProvider).user;
    final isAdmin =
        me?.role == 'ADMIN' || me?.role == 'SUPER_ADMIN';

    return ValueListenableBuilder<core.ThemeMode>(
      valueListenable: MobileLocalSettings.themeMode,
      builder: (context, mode, _) {
        return ValueListenableBuilder<MobileThemeId>(
          valueListenable: MobileLocalSettings.colorTheme,
          builder: (context, selected, __) {
            return ValueListenableBuilder<
                Map<MobileThemeId, Map<String, int>>>(
              valueListenable: MobileLocalSettings.themeColorOverrides,
              builder: (context, overridesMap, ___) {
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
                            icon:
                                Icon(Icons.brightness_auto_outlined, size: 16),
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
                      const SizedBox(height: 4),
                      Text(
                        'Tap to apply. Use Edit to change each color.',
                        style: TextStyle(fontSize: 12, color: c.textFaint),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 148,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: MobileThemeId.values.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final themeId = MobileThemeId.values[index];
                            final palette = MobileThemePalettes.paletteFor(
                              themeId,
                              overrides: overridesMap[themeId],
                            );
                            final isSelected = themeId == selected;
                            return Container(
                              width: 128,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(BestieTokens.rMd),
                                border: Border.all(
                                  color: isSelected ? palette.brand : c.border,
                                  width: isSelected ? 2 : 1,
                                ),
                                gradient: palette.previewGradient,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () async {
                                            await MobileLocalSettings
                                                .setColorTheme(themeId);
                                            ref
                                                .read(mobileColorThemeProvider
                                                    .notifier)
                                                .state = themeId;
                                          },
                                          child: Text(
                                            themeId.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: palette.text,
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Edit colors',
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        icon: Icon(
                                          Icons.edit_rounded,
                                          size: 16,
                                          color: palette.text,
                                        ),
                                        onPressed: () =>
                                            showMobileThemeColorEditor(
                                          context,
                                          themeId: themeId,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () async {
                                      await MobileLocalSettings
                                          .setColorTheme(themeId);
                                      ref
                                          .read(mobileColorThemeProvider.notifier)
                                          .state = themeId;
                                    },
                                    child: Row(
                                      children: [
                                        if (isSelected)
                                          Icon(Icons.check_circle,
                                              size: 16, color: palette.brand),
                                        if (isSelected)
                                          const SizedBox(width: 4),
                                        Text(
                                          isSelected ? 'Active' : 'Apply',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: palette.text,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(height: 16),
                        _AdminPrimaryColorTile(colors: c),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AdminPrimaryColorTile extends ConsumerStatefulWidget {
  const _AdminPrimaryColorTile({required this.colors});
  final BestieColors colors;

  @override
  ConsumerState<_AdminPrimaryColorTile> createState() =>
      _AdminPrimaryColorTileState();
}

class _AdminPrimaryColorTileState
    extends ConsumerState<_AdminPrimaryColorTile> {
  bool _saving = false;

  Future<void> _pickAndSave() async {
    final c = widget.colors;
    final current = MobileLocalSettings.adminPrimaryColor.value != null
        ? Color(MobileLocalSettings.adminPrimaryColor.value!)
        : c.brand;
    final hexCtrl = TextEditingController(
      text:
          '#${current.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
    );
    Color draft = current;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Org brand color'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Sets the workspace primary color for all devices (branding.primaryColor).',
                    style: TextStyle(fontSize: 13, color: c.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: draft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.border),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: hexCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Hex (#RRGGBB)',
                      isDense: true,
                    ),
                    onChanged: (raw) {
                      var text = raw.trim();
                      if (text.startsWith('#')) text = text.substring(1);
                      if (text.length == 6) {
                        final v = int.tryParse('FF$text', radix: 16);
                        if (v != null) setLocal(() => draft = Color(v));
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    await MobileLocalSettings.setAdminPrimaryColor(null);
                    try {
                      await ref.read(apiProvider).setSetting(
                            scope: 'branding',
                            key: 'primaryColor',
                            value: '',
                          );
                    } catch (_) {}
                    ref.invalidate(orgBrandingProvider);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  child: const Text('Clear'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final hex =
          '#${draft.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
      await ref.read(apiProvider).setSetting(
            scope: 'branding',
            key: 'primaryColor',
            value: hex,
          );
      await MobileLocalSettings.setAdminPrimaryColor(draft.toARGB32());
      ref.invalidate(orgBrandingProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Org brand color saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return ValueListenableBuilder<int?>(
      valueListenable: MobileLocalSettings.adminPrimaryColor,
      builder: (context, argb, _) {
        final color = argb != null ? Color(argb) : c.brand;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
          ),
          title: Text(
            'Org brand color (admin)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
          subtitle: Text(
            'Applies brand tint across the app for everyone',
            style: TextStyle(fontSize: 12, color: c.textMuted),
          ),
          trailing: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.palette_outlined, color: c.brand),
          onTap: _saving ? null : _pickAndSave,
        );
      },
    );
  }
}
