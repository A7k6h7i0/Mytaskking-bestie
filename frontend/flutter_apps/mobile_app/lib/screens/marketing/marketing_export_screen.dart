import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../chat_media_saver.dart';
import '../../state.dart';
import 'field_form_dialogs.dart';
import 'field_sub_scaffold.dart';

/// Manager / admin — download full marketing field data as Excel.
class MarketingExportScreen extends ConsumerStatefulWidget {
  const MarketingExportScreen({super.key});

  @override
  ConsumerState<MarketingExportScreen> createState() =>
      _MarketingExportScreenState();
}

class _MarketingExportScreenState extends ConsumerState<MarketingExportScreen> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  bool _downloading = false;

  static const _sheets = [
    ('Outlets', Icons.storefront_outlined),
    ('Visits', Icons.place_outlined),
    ('Orders', Icons.receipt_long_outlined),
    ('Order Items', Icons.list_alt_outlined),
    ('GPS Logs', Icons.my_location_outlined),
    ('Expenses', Icons.payments_outlined),
    ('Leaves', Icons.beach_access_outlined),
    ('Incidents', Icons.report_problem_outlined),
    ('Ratings', Icons.star_outline_rounded),
    ('Routes', Icons.route_outlined),
    ('Daily Plans', Icons.event_note_outlined),
    ('Products', Icons.inventory_2_outlined),
    ('Categories', Icons.category_outlined),
    ('Brands', Icons.label_outline),
    ('Holidays', Icons.celebration_outlined),
    ('Executives', Icons.groups_outlined),
  ];

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final report = await ref.read(apiProvider).downloadMarketingExport(
            from: _fromCtrl.text.trim().isEmpty ? null : _fromCtrl.text.trim(),
            to: _toCtrl.text.trim().isEmpty ? null : _toCtrl.text.trim(),
          );
      if (!mounted) return;
      final path = await ChatMediaSaver.saveBytesWithSaveDialog(
        report.bytes,
        suggestedName: report.filename,
        dialogTitle: 'Save marketing Excel report',
      );
      if (!mounted || path == null) return;
      bestieToast(
        context,
        'Report saved',
        body: report.rowCount > 0
            ? '${report.executiveCount} executives · ${report.rowCount} rows · $path'
            : path,
        kind: BestieToastKind.success,
      );
    } catch (e) {
      if (mounted) {
        bestieToast(
          context,
          'Export failed',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final isManager = ref.watch(authStoreProvider).user?.isFieldManager ?? false;

    if (!isManager) {
      return FieldSubScaffold(
        title: 'Export Excel',
        body: Center(
          child: Text('Managers and admins only', style: TextStyle(color: c.textMuted)),
        ),
      );
    }

    return FieldSubScaffold(
      title: 'Export Excel',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: BorderRadius.circular(BestieTokens.rLg),
              border: Border.all(color: c.brand.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.download_for_offline_rounded, color: c.brand, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Marketing field report',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Download all executive outlets, visits, orders, GPS, HR records, routes, and product catalog in one Excel workbook.',
                        style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Optional date filter',
            style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
          ),
          const SizedBox(height: 4),
          Text(
            'Limits visits, orders, and GPS logs. Leave blank for all time.',
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          fieldFormDateField(context, c, controller: _fromCtrl, label: 'From date'),
          const SizedBox(height: 12),
          fieldFormDateField(context, c, controller: _toCtrl, label: 'To date'),
          const SizedBox(height: 24),
          Text(
            'Included sheets (${_sheets.length})',
            style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
          ),
          const SizedBox(height: 10),
          ..._sheets.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: c.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BestieTokens.rMd),
                  side: BorderSide(color: c.borderSoft),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(s.$2, color: c.brand, size: 20),
                  title: Text(s.$1, style: TextStyle(color: c.text, fontSize: 14)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _downloading ? null : _download,
            style: FilledButton.styleFrom(
              backgroundColor: c.brand,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: _downloading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.surface),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(_downloading ? 'Preparing workbook…' : 'Download Excel report'),
          ),
        ],
      ),
    );
  }
}
