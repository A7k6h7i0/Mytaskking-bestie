import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import 'mobile_local_settings.dart';
import 'mobile_theme_palettes.dart';

Future<void> showMobileThemeColorEditor(
  BuildContext context, {
  required MobileThemeId themeId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: BestieColors.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.92,
      child: _MobileThemeColorEditorSheet(themeId: themeId),
    ),
  );
}

class _MobileThemeColorEditorSheet extends StatefulWidget {
  const _MobileThemeColorEditorSheet({required this.themeId});

  final MobileThemeId themeId;

  @override
  State<_MobileThemeColorEditorSheet> createState() =>
      _MobileThemeColorEditorSheetState();
}

class _MobileThemeColorEditorSheetState
    extends State<_MobileThemeColorEditorSheet> {
  late Map<String, int> _draft;
  String? _selectedKey;

  @override
  void initState() {
    super.initState();
    final base = MobileThemePalettes.basePaletteFor(widget.themeId);
    final saved = MobileLocalSettings.overridesFor(widget.themeId);
    _draft = saved.isEmpty
        ? base.toColorValueMap()
        : {...base.toColorValueMap(), ...saved};
    _selectedKey = BestiePaletteEditing.editableFields.first.key;
  }

  BestiePaletteExtension get _previewPalette {
    final base = MobileThemePalettes.basePaletteFor(widget.themeId);
    return base.withColorValues(_draft);
  }

  Color get _selectedColor {
    final key = _selectedKey ?? BestiePaletteEditing.editableFields.first.key;
    return Color(_draft[key] ?? _previewPalette.colorForKey(key).toARGB32());
  }

  void _setColor(String key, Color color) {
    setState(() {
      _draft[key] = color.toARGB32();
      _selectedKey = key;
    });
  }

  Future<void> _save() async {
    final base = MobileThemePalettes.basePaletteFor(widget.themeId);
    final baseMap = base.toColorValueMap();
    final overrides = <String, int>{};
    _draft.forEach((key, value) {
      if (baseMap[key] != value) overrides[key] = value;
    });
    await MobileLocalSettings.setThemeColorOverrides(widget.themeId, overrides);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    final base = MobileThemePalettes.basePaletteFor(widget.themeId);
    setState(() {
      _draft = base.toColorValueMap();
      _selectedKey = BestiePaletteEditing.editableFields.first.key;
    });
    await MobileLocalSettings.resetThemeColorOverrides(widget.themeId);
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final palette = _previewPalette;
    final selectedKey =
        _selectedKey ?? BestiePaletteEditing.editableFields.first.key;
    final selectedColor = _selectedColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Edit ${widget.themeId.title}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap a swatch, then fine-tune with sliders or hex.',
                      style: TextStyle(fontSize: 13, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: palette.previewGradient,
              border: Border.all(color: c.border),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              for (final field in BestiePaletteEditing.editableFields)
                Builder(builder: (context) {
                  final color = Color(
                    _draft[field.key] ??
                        palette.colorForKey(field.key).toARGB32(),
                  );
                  final selected = field.key == selectedKey;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    selectedTileColor: c.brandSoft.withValues(alpha: 0.45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    leading: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.borderStrong),
                      ),
                    ),
                    title: Text(
                      field.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: c.text,
                      ),
                    ),
                    subtitle: Text(
                      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                    onTap: () => setState(() => _selectedKey = field.key),
                  );
                }),
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _ColorMakerPanel(
                  color: selectedColor,
                  onChanged: (color) => _setColor(selectedKey, color),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save colors'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorMakerPanel extends StatefulWidget {
  const _ColorMakerPanel({
    required this.color,
    required this.onChanged,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorMakerPanel> createState() => _ColorMakerPanelState();
}

class _ColorMakerPanelState extends State<_ColorMakerPanel> {
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(text: _hexLabel(widget.color));
  }

  @override
  void didUpdateWidget(covariant _ColorMakerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _hexController.text = _hexLabel(widget.color);
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _hexLabel(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  void _applyHex(String raw) {
    var text = raw.trim();
    if (text.startsWith('#')) text = text.substring(1);
    if (text.length == 6) text = 'FF$text';
    final value = int.tryParse(text, radix: 16);
    if (value == null) return;
    widget.onChanged(Color(value));
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final color = widget.color;
    final hsv = HSVColor.fromColor(color);

    return Card(
      elevation: 0,
      color: c.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Custom color',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.borderStrong),
              ),
            ),
            const SizedBox(height: 10),
            _slider(
              label: 'Hue',
              value: hsv.hue,
              max: 360,
              activeColor: color,
              onChanged: (v) => widget.onChanged(hsv.withHue(v).toColor()),
            ),
            _slider(
              label: 'Saturation',
              value: hsv.saturation,
              max: 1,
              activeColor: color,
              onChanged: (v) =>
                  widget.onChanged(hsv.withSaturation(v).toColor()),
            ),
            _slider(
              label: 'Brightness',
              value: hsv.value,
              max: 1,
              activeColor: color,
              onChanged: (v) => widget.onChanged(hsv.withValue(v).toColor()),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _hexController,
              decoration: InputDecoration(
                labelText: 'Hex',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[#0-9A-Fa-f]')),
              ],
              onSubmitted: _applyHex,
              onChanged: (value) {
                if (value.length == 7 || value.length == 9) _applyHex(value);
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Presets',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in _presetColors)
                  InkWell(
                    onTap: () => widget.onChanged(preset),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: preset,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.borderStrong),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double max,
    required Color activeColor,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        Slider(
          value: value.clamp(0, max),
          min: 0,
          max: max,
          activeColor: activeColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

const _presetColors = <Color>[
  Color(0xFF0C4FBF),
  Color(0xFF09A7FF),
  Color(0xFFEA580C),
  Color(0xFF166534),
  Color(0xFF1E3A5F),
  Color(0xFF0B0E13),
  Color(0xFFFFFFFF),
  Color(0xFFEEF4FF),
  Color(0xFFFFFBF7),
  Color(0xFFF8FAF9),
  Color(0xFFD6336C),
  Color(0xFF64748B),
];
