import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import 'field_helpers.dart';
import 'field_offline_queue.dart';
import 'field_sync_service.dart';

/// Field HR hub — expenses, leaves, incidents, ratings, routes & daily plans.
class FieldHrScreen extends ConsumerStatefulWidget {
  const FieldHrScreen({super.key});

  @override
  ConsumerState<FieldHrScreen> createState() => _FieldHrScreenState();
}

class _FieldHrScreenState extends ConsumerState<FieldHrScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FieldSyncService.syncAll(ref.read(apiProvider)).catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final isManager = ref.watch(authStoreProvider).user?.isFieldManager ?? false;
    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) fieldGoBack(context);
      },
      child: DefaultTabController(
        length: 6,
        child: Scaffold(
          backgroundColor: c.surface,
          appBar: AppBar(
            leading: BackButton(onPressed: () => fieldGoBack(context)),
            title: const Text('Field HR'),
            backgroundColor: c.surface,
            foregroundColor: c.text,
            bottom: TabBar(
              isScrollable: true,
              labelColor: c.brand,
              tabs: const [
                Tab(text: 'Expenses'),
                Tab(text: 'Leaves'),
                Tab(text: 'Incidents'),
                Tab(text: 'Ratings'),
                Tab(text: 'Routes'),
                Tab(text: 'Holidays'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _ExpensesTab(isManager: isManager),
              _LeavesTab(isManager: isManager),
              _IncidentsTab(isManager: isManager),
              _RatingsTab(),
              _RoutesTab(isManager: isManager),
              _HolidaysTab(isManager: isManager),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpensesTab extends ConsumerStatefulWidget {
  final bool isManager;
  const _ExpensesTab({required this.isManager});

  @override
  ConsumerState<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends ConsumerState<_ExpensesTab> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ref.read(apiProvider).listFieldExpenses();
      setState(() {
        _items = ((resp['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final typeCtrl = TextEditingController(text: 'Travel');
    final amountCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
        text: DateTime.now().toIso8601String().substring(0, 10));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Type')),
            TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: 'Amount'), keyboardType: TextInputType.number),
            TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (ok != true) {
      typeCtrl.dispose();
      amountCtrl.dispose();
      dateCtrl.dispose();
      return;
    }
    try {
      String? receiptUrl;
      final pickReceipt = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Receipt'),
          content: const Text('Attach a receipt photo?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Skip')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Attach')),
          ],
        ),
      );
      if (pickReceipt == true) {
        final file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 75);
        if (file != null) {
          final bytes = await file.readAsBytes();
          final asset = await ref.read(apiProvider).uploadFile(
                bytes: bytes,
                filename: 'expense-${DateTime.now().millisecondsSinceEpoch}.jpg',
                mimeType: 'image/jpeg',
              );
          receiptUrl = asset['url']?.toString();
        }
      }
      await ref.read(apiProvider).createFieldExpense({
        'type': typeCtrl.text.trim(),
        'amount': double.tryParse(amountCtrl.text.trim()) ?? 0,
        'expenseDate': dateCtrl.text.trim(),
        if (receiptUrl != null) 'receiptUrl': receiptUrl,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Failed', body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      typeCtrl.dispose();
      amountCtrl.dispose();
      dateCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    if (_loading) return const Center(child: BestieSpinner());
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items.isEmpty
            ? ListView(children: [Center(child: Text('No expenses', style: TextStyle(color: c.textMuted)))])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final e = _items[i];
                  return ListTile(
                    tileColor: c.surface2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text('${e['type']} — ${e['amount']}'),
                    subtitle: Text('${e['expenseDate']} · ${e['status']}'),
                    trailing: widget.isManager && e['status'] == 'pending'
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Approve',
                                icon: Icon(Icons.check_circle_outline, color: c.success),
                                onPressed: () async {
                                  await ref.read(apiProvider).approveFieldExpense(e['id'].toString());
                                  await _load();
                                },
                              ),
                              IconButton(
                                tooltip: 'Reject',
                                icon: Icon(Icons.cancel_outlined, color: c.danger),
                                onPressed: () async {
                                  await ref.read(apiProvider).rejectFieldExpense(e['id'].toString());
                                  await _load();
                                },
                              ),
                            ],
                          )
                        : null,
                  );
                },
              ),
      ),
    );
  }
}

class _LeavesTab extends ConsumerStatefulWidget {
  final bool isManager;
  const _LeavesTab({required this.isManager});

  @override
  ConsumerState<_LeavesTab> createState() => _LeavesTabState();
}

class _LeavesTabState extends ConsumerState<_LeavesTab> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ref.read(apiProvider).listFieldLeaves();
      setState(() {
        _items = ((resp['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final typeCtrl = TextEditingController(text: 'Casual');
    final fromCtrl = TextEditingController();
    final toCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply leave'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Leave type')),
            TextField(controller: fromCtrl, decoration: const InputDecoration(labelText: 'From (YYYY-MM-DD)')),
            TextField(controller: toCtrl, decoration: const InputDecoration(labelText: 'To (YYYY-MM-DD)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).createFieldLeave({
        'leaveType': typeCtrl.text.trim(),
        'fromDate': fromCtrl.text.trim(),
        'toDate': toCtrl.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Failed', body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      typeCtrl.dispose();
      fromCtrl.dispose();
      toCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    if (_loading) return const Center(child: BestieSpinner());
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(onPressed: _apply, child: const Icon(Icons.add)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final l = _items[i];
          return ListTile(
            tileColor: c.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text('${l['leaveType']} · ${l['fromDate']} → ${l['toDate']}'),
            subtitle: Text(l['status']?.toString() ?? ''),
            trailing: widget.isManager && l['status'] == 'pending'
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.check_circle_outline, color: c.success),
                        onPressed: () async {
                          await ref.read(apiProvider).approveFieldLeave(l['id'].toString());
                          await _load();
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.cancel_outlined, color: c.danger),
                        onPressed: () async {
                          await ref.read(apiProvider).rejectFieldLeave(l['id'].toString());
                          await _load();
                        },
                      ),
                    ],
                  )
                : null,
          );
        },
      ),
    );
  }
}

class _IncidentsTab extends ConsumerStatefulWidget {
  final bool isManager;
  const _IncidentsTab({required this.isManager});

  @override
  ConsumerState<_IncidentsTab> createState() => _IncidentsTabState();
}

class _IncidentsTabState extends ConsumerState<_IncidentsTab> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ref.read(apiProvider).listFieldIncidents();
      setState(() {
        _items = ((resp['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _report() async {
    final typeCtrl = TextEditingController(text: 'Safety');
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report incident'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Type')),
            TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Report')),
        ],
      ),
    );
    if (ok != true) return;
    final offlineId = 'inc-${DateTime.now().millisecondsSinceEpoch}';
    final payload = {
      'type': typeCtrl.text.trim(),
      'description': descCtrl.text.trim(),
      'offlineId': offlineId,
    };
    try {
      await ref.read(apiProvider).createFieldIncident(payload);
      await _load();
    } catch (_) {
      await FieldOfflineQueue.enqueueIncident(payload);
      if (mounted) {
        setState(() {
          _items = [
            {
              ...payload,
              'status': 'queued',
              'id': offlineId,
            },
            ..._items,
          ];
        });
        bestieToast(context, 'Saved offline',
            body: 'Will sync when you are back online.',
            kind: BestieToastKind.info);
      }
    } finally {
      typeCtrl.dispose();
      descCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    if (_loading) return const Center(child: BestieSpinner());
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(onPressed: _report, child: const Icon(Icons.add)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final item = _items[i];
          return ListTile(
            tileColor: c.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(item['type']?.toString() ?? 'Incident'),
            subtitle: Text(item['description']?.toString() ?? ''),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BestieBadge(
                  tone: item['status'] == 'resolved'
                      ? BestieTone.success
                      : BestieTone.warning,
                  child: Text(item['status']?.toString() ?? 'open'),
                ),
                if (widget.isManager && item['status'] == 'open' && item['id'] != null)
                  IconButton(
                    tooltip: 'Resolve',
                    icon: Icon(Icons.done_all, color: c.success),
                    onPressed: () async {
                      await ref.read(apiProvider).resolveFieldIncident(item['id'].toString());
                      await _load();
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RatingsTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RatingsTab> createState() => _RatingsTabState();
}

class _RatingsTabState extends ConsumerState<_RatingsTab> {
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await ref.read(apiProvider).listFieldRatings();
      if (!mounted) return;
      setState(() {
        _items = ((resp['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _rate() async {
    final picked = await pickMarketingOutlet(context, ref, title: 'Rate which outlet?');
    if (picked == null) return;
    final scoreCtrl = TextEditingController(text: '5');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rate ${picked['name']}'),
        content: TextField(
          controller: scoreCtrl,
          decoration: const InputDecoration(labelText: 'Score 1-5'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) {
      scoreCtrl.dispose();
      return;
    }
    try {
      await ref.read(apiProvider).createFieldRating({
        'entityType': 'outlet',
        'entityId': picked['id'].toString(),
        'score': int.tryParse(scoreCtrl.text.trim()) ?? 5,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Failed', body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      scoreCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(onPressed: _rate, child: const Icon(Icons.add)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = _items[i];
          return ListTile(
            tileColor: c.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text('${r['entityType']} · score ${r['score']}'),
            subtitle: Text(r['entityId']?.toString() ?? ''),
          );
        },
      ),
    );
  }
}

class _RoutesTab extends ConsumerStatefulWidget {
  final bool isManager;
  const _RoutesTab({required this.isManager});

  @override
  ConsumerState<_RoutesTab> createState() => _RoutesTabState();
}

class _RoutesTabState extends ConsumerState<_RoutesTab> {
  List<Map<String, dynamic>> _routes = const [];
  List<Map<String, dynamic>> _plans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final routes = await ref.read(apiProvider).listFieldRoutes();
      final plans = await ref.read(apiProvider).listFieldDailyPlans(
            date: DateTime.now().toIso8601String().substring(0, 10),
          );
      if (!mounted) return;
      setState(() {
        _routes = ((routes['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _plans = ((plans['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _addRoute() async {
    if (!widget.isManager) return;
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New route'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Route name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final outlets = await pickMarketingOutletsMulti(context, ref);
      final exec = await pickExecutive(context, ref);
      await ref.read(apiProvider).createFieldRoute({
        'name': nameCtrl.text.trim(),
        'outletIds': outlets.map((o) => o['id']).toList(),
        if (exec != null) 'assignedToId': exec['id'],
      });
      await _load();
    } finally {
      nameCtrl.dispose();
    }
  }

  Future<void> _editRoute(Map<String, dynamic> route) async {
    if (!widget.isManager) return;
    final outlets = await pickMarketingOutletsMulti(
      context,
      ref,
      initialIds: ((route['outletIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
    final exec = await pickExecutive(context, ref);
    await ref.read(apiProvider).updateFieldRoute(route['id'].toString(), {
      'outletIds': outlets.map((o) => o['id']).toList(),
      if (exec != null) 'assignedToId': exec['id'],
    });
    await _load();
  }

  Future<void> _addDailyPlan() async {
    if (!widget.isManager) return;
    final dateCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    String? routeId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Daily plan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateCtrl,
                decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: routeId,
                decoration: const InputDecoration(labelText: 'Route (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('No route')),
                  ..._routes.map(
                    (r) => DropdownMenuItem(
                      value: r['id']?.toString(),
                      child: Text(r['name']?.toString() ?? 'Route'),
                    ),
                  ),
                ],
                onChanged: (v) => setDialogState(() => routeId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) {
      dateCtrl.dispose();
      return;
    }
    try {
      final routeOutlets = routeId == null
          ? <dynamic>[]
          : (_routes.firstWhere(
                (r) => r['id']?.toString() == routeId,
                orElse: () => const {},
              )['outletIds'] as List?) ??
              [];
      await ref.read(apiProvider).createFieldDailyPlan({
        'planDate': dateCtrl.text.trim(),
        if (routeId != null) 'routeId': routeId,
        'outletIds': routeOutlets,
      });
      await _load();
    } finally {
      dateCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.isManager
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'daily-plan',
                  onPressed: _addDailyPlan,
                  child: const Icon(Icons.event_note),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'route',
                  onPressed: _addRoute,
                  child: const Icon(Icons.add_road),
                ),
              ],
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Today\'s plan', style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 8),
            if (_plans.isEmpty)
              Text('No daily plan for today', style: TextStyle(color: c.textMuted))
            else
              for (final p in _plans)
                ListTile(
                  tileColor: c.surface2,
                  title: Text('Plan ${p['planDate']}'),
                  subtitle: Text('${(p['outletIds'] as List?)?.length ?? 0} outlets'),
                ),
            const SizedBox(height: 16),
            Text('Routes', style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 8),
            for (final r in _routes)
              ListTile(
                tileColor: c.surface2,
                title: Text(r['name']?.toString() ?? 'Route'),
                subtitle: Text(
                  '${(r['outletIds'] as List?)?.length ?? 0} outlets · ${(r['assignedTo'] as Map?)?['name'] ?? 'Unassigned'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: widget.isManager ? () => _editRoute(r) : () => context.push('/marketing/outlets'),
              ),
          ],
        ),
      ),
    );
  }
}

class _HolidaysTab extends ConsumerStatefulWidget {
  final bool isManager;
  const _HolidaysTab({required this.isManager});

  @override
  ConsumerState<_HolidaysTab> createState() => _HolidaysTabState();
}

class _HolidaysTabState extends ConsumerState<_HolidaysTab> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await ref.read(apiProvider).listFieldHolidays();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    if (!widget.isManager) return;
    final nameCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add holiday'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).createFieldHoliday({
        'name': nameCtrl.text.trim(),
        'date': dateCtrl.text.trim(),
      });
      await _load();
    } finally {
      nameCtrl.dispose();
      dateCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    if (_loading) return const Center(child: BestieSpinner());
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.isManager
          ? FloatingActionButton(onPressed: _add, child: const Icon(Icons.add))
          : null,
      body: _items.isEmpty
          ? Center(child: Text('No holidays', style: TextStyle(color: c.textMuted)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final h = _items[i];
                return ListTile(
                  tileColor: c.surface2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text(h['name']?.toString() ?? 'Holiday'),
                  subtitle: Text(h['date']?.toString() ?? ''),
                );
              },
            ),
    );
  }
}
