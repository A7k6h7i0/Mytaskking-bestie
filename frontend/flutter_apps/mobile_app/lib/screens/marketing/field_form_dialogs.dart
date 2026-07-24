import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../widgets/bestie_picker_theme.dart';

String formatFieldDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

InputDecoration fieldFormDecoration(
  BestieColors c,
  String label, {
  String? hint,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    floatingLabelBehavior: FloatingLabelBehavior.auto,
    labelStyle: TextStyle(color: c.textMuted, fontSize: 14),
    hintStyle: TextStyle(color: c.textFaint, fontSize: 15),
    filled: true,
    fillColor: c.surface2,
    suffixIcon: suffixIcon,
    isDense: false,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(BestieTokens.rMd),
      borderSide: BorderSide(color: c.borderSoft),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(BestieTokens.rMd),
      borderSide: BorderSide(color: c.borderSoft),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(BestieTokens.rMd),
      borderSide: BorderSide(color: c.brand, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
  );
}

/// Keeps form rows from collapsing in tight dialog layouts.
Widget fieldFormFieldShell({required Widget child}) {
  return SizedBox(width: double.infinity, child: child);
}

Widget fieldFormTextField(
  BestieColors c, {
  required TextEditingController controller,
  required String label,
  TextInputType? keyboardType,
  int maxLines = 1,
  String? hint,
}) {
  return fieldFormFieldShell(
    child: TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      minLines: maxLines > 1 ? maxLines : 1,
      style: TextStyle(color: c.text, fontSize: 15, height: 1.35),
      decoration: fieldFormDecoration(c, label, hint: hint),
    ),
  );
}

Widget fieldFormDateField(
  BuildContext context,
  BestieColors c, {
  required TextEditingController controller,
  required String label,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  Future<void> pick() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final initial = DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
    final picked = await bestiePickDate(
      context,
      initial: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null) {
      controller.text = formatFieldDate(picked);
    }
  }

  return fieldFormFieldShell(
    child: TextField(
      controller: controller,
      readOnly: true,
      enableInteractiveSelection: false,
      showCursor: false,
      style: TextStyle(color: c.text, fontSize: 15),
      decoration: fieldFormDecoration(
        c,
        label,
        hint: 'Tap to pick a date',
        suffixIcon: IconButton(
          tooltip: 'Pick date',
          onPressed: pick,
          icon: Icon(Icons.calendar_today_outlined, color: c.brand, size: 20),
        ),
      ),
      onTap: pick,
    ),
  );
}

/// Themed form dialog with scrollable spaced fields (light/dark aware).
Future<bool?> showFieldFormDialog({
  required BuildContext context,
  required String title,
  required List<Widget> fields,
  String? subtitle,
  String confirmLabel = 'Save',
  String cancelLabel = 'Cancel',
}) {
  return showFieldFormDialogBuilder(
    context: context,
    title: title,
    subtitle: subtitle,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    buildFields: (_, __) => fields,
  );
}

/// Same as [showFieldFormDialog] but fields can depend on [StateSetter] (e.g. dropdowns).
Future<bool?> showFieldFormDialogBuilder({
  required BuildContext context,
  required String title,
  required List<Widget> Function(BuildContext ctx, StateSetter setState) buildFields,
  String? subtitle,
  String confirmLabel = 'Save',
  String cancelLabel = 'Cancel',
}) {
  final c = BestieColors.of(context);
  final screenW = MediaQuery.sizeOf(context).width;
  final dialogW = screenW > 560 ? 440.0 : screenW - 32;

  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final fields = buildFields(ctx, setDialogState);
        return Dialog(
          backgroundColor: c.surface,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BestieTokens.rLg),
            side: BorderSide(color: c.borderSoft),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dialogW,
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          height: 1.25,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < fields.length; i++) ...[
                          if (i > 0) const SizedBox(height: 18),
                          fields[i],
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          foregroundColor: c.textMuted,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        child: Text(cancelLabel),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: c.brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(BestieTokens.rMd),
                          ),
                        ),
                        child: Text(confirmLabel),
                      ),
                    ],
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

Future<bool?> showFieldConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
}) {
  final c = BestieColors.of(context);
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        side: BorderSide(color: c.borderSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(color: c.text, fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(message, style: TextStyle(color: c.textMuted, height: 1.45, fontSize: 14)),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(cancelLabel, style: TextStyle(color: c.textMuted)),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(backgroundColor: c.brand),
                  child: Text(confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget fieldFormDropdown<T>(
  BestieColors c, {
  required T? value,
  required String label,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
}) {
  return fieldFormFieldShell(
    child: DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: fieldFormDecoration(c, label),
      dropdownColor: c.surface,
      borderRadius: BorderRadius.circular(BestieTokens.rMd),
      style: TextStyle(color: c.text, fontSize: 15),
      items: items,
      onChanged: onChanged,
    ),
  );
}
