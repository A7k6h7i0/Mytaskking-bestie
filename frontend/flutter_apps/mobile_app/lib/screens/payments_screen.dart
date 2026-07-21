import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref.read(apiProvider).listAdminBillingPlans();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = formatApiError(e);
        _loading = false;
      });
    }
  }

  Future<void> _showPlanSheet({Map<String, dynamic>? existing}) async {
    final c = BestieColors.of(context);
    final labelCtrl = TextEditingController(text: existing?['label']?.toString() ?? '');
    final monthsCtrl = TextEditingController(
      text: (existing?['planMonths'] ?? existing?['months'] ?? '1').toString(),
    );
    final amountCtrl = TextEditingController(
      text: existing?['amountInr']?.toString() ??
          (((existing?['amountPaise'] as num?) ?? 0) / 100).toStringAsFixed(0),
    );
    final sortCtrl = TextEditingController(
      text: (existing?['sortOrder'] ?? 0).toString(),
    );
    var isActive = existing?['isActive'] != false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New plan' : 'Edit plan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                TextField(
                  controller: monthsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Duration (months)'),
                ),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Price (INR)'),
                ),
                TextField(
                  controller: sortCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sort order'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active in checkout'),
                  value: isActive,
                  onChanged: (v) => setLocal(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: c.brand),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final body = {
      'label': labelCtrl.text.trim(),
      'months': int.tryParse(monthsCtrl.text.trim()) ?? 1,
      'amountPaise': ((double.tryParse(amountCtrl.text.trim()) ?? 0) * 100).round(),
      'sortOrder': int.tryParse(sortCtrl.text.trim()) ?? 0,
      'isActive': isActive,
    };

    try {
      final api = ref.read(apiProvider);
      if (existing == null) {
        await api.createBillingPlan(body);
      } else {
        await api.updateBillingPlan(existing['id'].toString(), body);
      }
      await _load();
      if (!mounted) return;
      bestieToast(context, existing == null ? 'Plan created' : 'Plan updated',
          kind: BestieToastKind.success);
    } catch (e) {
      if (!mounted) return;
      bestieToast(context, 'Could not save plan',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  Future<void> _deletePlan(String id, String label) async {
    final c = BestieColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove plan?'),
        content: Text('Delete or hide "$label" from checkout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: c.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final result = await ref.read(apiProvider).deleteBillingPlan(id);
      await _load();
      if (!mounted) return;
      final deactivated = result['deactivated'] == true;
      bestieToast(context, deactivated ? 'Plan hidden' : 'Plan deleted',
          kind: BestieToastKind.success);
    } catch (e) {
      if (!mounted) return;
      bestieToast(context, 'Could not remove plan',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: const Text('Payments'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showPlanSheet(),
            tooltip: 'Add plan',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(_error!, style: TextStyle(color: c.danger)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  )
                : _items.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Icon(Icons.payments_outlined, size: 48, color: c.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            'No subscription plans',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: c.text,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add plans here — they appear in org registration checkout and payment.mytaskking.com.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.textMuted, height: 1.4),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final plan = _items[i];
                          final active = plan['isActive'] != false;
                          final months = plan['planMonths'] ?? plan['months'];
                          final inr = plan['amountInr'] ??
                              (((plan['amountPaise'] as num?) ?? 0) / 100);
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(BestieTokens.rLg),
                              border: Border.all(color: c.borderSoft),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.payments_rounded, color: c.brand),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        plan['label']?.toString() ?? 'Plan',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: c.text,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$months mo · ₹$inr · order ${plan['sortOrder'] ?? 0}',
                                        style: TextStyle(color: c.textMuted, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: active ? c.successSoft : c.surface2,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    active ? 'Active' : 'Hidden',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: active ? c.success : c.textMuted,
                                    ),
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') {
                                      _showPlanSheet(existing: plan);
                                    } else if (v == 'delete') {
                                      _deletePlan(
                                        plan['id'].toString(),
                                        plan['label']?.toString() ?? 'plan',
                                      );
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                                    PopupMenuItem(value: 'delete', child: Text('Remove')),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
