import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

String _colorToHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

Color? _parseHexColor(String raw) {
  var text = raw.trim().toUpperCase();
  if (text.startsWith('#')) text = text.substring(1);
  if (text.length == 6) {
    final v = int.tryParse('FF$text', radix: 16);
    if (v != null) return Color(v);
  }
  if (text.length == 8) {
    final v = int.tryParse(text, radix: 16);
    if (v != null) return Color(v);
  }
  return null;
}

const _orgBrandPresets = <Color>[
  Color(0xFF5B8CFF),
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFF059669),
  Color(0xFFDC2626),
  Color(0xFFEA580C),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
  Color(0xFF111827),
  Color(0xFF64748B),
];

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
    final hexCtrl = TextEditingController(text: _colorToHex(current));
    Color draft = current;

    void syncHex(Color next, void Function(void Function()) setLocal) {
      setLocal(() => draft = next);
      hexCtrl.text = _colorToHex(next);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final hsv = HSVColor.fromColor(draft);
            return AlertDialog(
              title: const Text('Org brand color'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Pick a custom color for all devices (branding.primaryColor).',
                      style: TextStyle(fontSize: 13, color: c.textMuted),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: draft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _colorToHex(draft),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: draft.computeLuminance() > 0.55
                              ? Colors.black87
                              : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hexCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Hex color (#RRGGBB)',
                        hintText: '#5B8CFF',
                        isDense: true,
                        prefixIcon: Icon(Icons.tag_rounded, size: 18),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[#0-9A-Fa-f]'),
                        ),
                      ],
                      onChanged: (raw) {
                        final parsed = _parseHexColor(raw);
                        if (parsed != null) setLocal(() => draft = parsed);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Quick picks',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in _orgBrandPresets)
                          InkWell(
                            onTap: () => syncHex(preset, setLocal),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: preset,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: draft.toARGB32() == preset.toARGB32()
                                      ? c.text
                                      : c.border,
                                  width: draft.toARGB32() == preset.toARGB32()
                                      ? 2
                                      : 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Custom',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textMuted,
                      ),
                    ),
                    Slider(
                      value: hsv.hue,
                      min: 0,
                      max: 360,
                      activeColor: draft,
                      onChanged: (v) => syncHex(
                        hsv.withHue(v).withSaturation(
                              hsv.saturation.clamp(0.35, 1.0),
                            ).toColor(),
                        setLocal,
                      ),
                    ),
                    Slider(
                      value: hsv.saturation,
                      min: 0,
                      max: 1,
                      activeColor: draft,
                      onChanged: (v) =>
                          syncHex(hsv.withSaturation(v).toColor(), setLocal),
                    ),
                    Slider(
                      value: hsv.value,
                      min: 0.15,
                      max: 1,
                      activeColor: draft,
                      onChanged: (v) =>
                          syncHex(hsv.withValue(v).toColor(), setLocal),
                    ),
                  ],
                ),
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

    hexCtrl.dispose();

    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final hex = _colorToHex(draft);
      await ref.read(apiProvider).setSetting(
            scope: 'branding',
            key: 'primaryColor',
            value: hex,
          );
      await MobileLocalSettings.setAdminPrimaryColor(draft.toARGB32());
      ref.invalidate(orgBrandingProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Org brand color saved ($hex)')),
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
        final hex = _colorToHex(color);
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
            '$hex · Applies brand tint for everyone',
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
