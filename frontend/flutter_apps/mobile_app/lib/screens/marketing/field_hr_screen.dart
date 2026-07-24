import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import 'field_form_dialogs.dart';
import 'field_helpers.dart';
import 'field_offline_queue.dart';
import 'field_sync_service.dart';

/// Field HR hub — expenses, leaves, incidents, ratings, routes & daily plans.
class FieldHrScreen extends ConsumerStatefulWidget {
  const FieldHrScreen({super.key});

  @override
  ConsumerState<FieldHrScreen> createState() => _FieldHrScreenState();
}

class _FieldHrScreenState extends ConsumerState<FieldHrScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _expensesKey = GlobalKey<_ExpensesTabState>();
  final _leavesKey = GlobalKey<_LeavesTabState>();
  final _incidentsKey = GlobalKey<_IncidentsTabState>();
  final _ratingsKey = GlobalKey<_RatingsTabState>();
  final _routesKey = GlobalKey<_RoutesTabState>();
  final _holidaysKey = GlobalKey<_HolidaysTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) setState(() {});
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FieldSyncService.syncAll(ref.read(apiProvider)).catchError((_) {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget? _floatingActionButton(BestieColors c, bool isManager) {
    switch (_tabController.index) {
      case 0:
        return FloatingActionButton.extended(
          heroTag: 'hr-expenses',
          backgroundColor: c.brand,
          foregroundColor: Colors.white,
          onPressed: () => _expensesKey.currentState?.add(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add expense'),
        );
      case 1:
        return FloatingActionButton.extended(
          heroTag: 'hr-leaves',
          backgroundColor: c.brand,
          foregroundColor: Colors.white,
          onPressed: () => _leavesKey.currentState?.apply(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Apply leave'),
        );
      case 2:
        return FloatingActionButton.extended(
          heroTag: 'hr-incidents',
          backgroundColor: c.brand,
          foregroundColor: Colors.white,
          onPressed: () => _incidentsKey.currentState?.report(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Report'),
        );
      case 3:
        return FloatingActionButton.extended(
          heroTag: 'hr-ratings',
          backgroundColor: c.brand,
          foregroundColor: Colors.white,
          onPressed: () => _ratingsKey.currentState?.rate(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Rate outlet'),
        );
      case 4:
        if (!isManager) return null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'hr-daily-plan',
              backgroundColor: c.surface,
              foregroundColor: c.brand,
              elevation: 1,
              onPressed: () => _routesKey.currentState?.addDailyPlan(),
              icon: const Icon(Icons.event_note_outlined),
              label: const Text('Daily plan'),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.extended(
              heroTag: 'hr-route',
              backgroundColor: c.brand,
              foregroundColor: Colors.white,
              onPressed: () => _routesKey.currentState?.addRoute(),
              icon: const Icon(Icons.add_road_rounded),
              label: const Text('New route'),
            ),
          ],
        );
      case 5:
        if (!isManager) return null;
        return FloatingActionButton.extended(
          heroTag: 'hr-holidays',
          backgroundColor: c.brand,
          foregroundColor: Colors.white,
          onPressed: () => _holidaysKey.currentState?.add(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add holiday'),
        );
      default:
        return null;
    }
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
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          leading: BackButton(onPressed: () => fieldGoBack(context)),
          title: const Text('Field HR'),
          backgroundColor: c.surface,
          foregroundColor: c.text,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: c.brand,
            unselectedLabelColor: c.textMuted,
            indicatorColor: c.brand,
            indicatorWeight: 2.5,
            dividerColor: c.borderSoft,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
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
        floatingActionButton: _floatingActionButton(c, isManager),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        body: TabBarView(
          controller: _tabController,
          children: [
            _ExpensesTab(key: _expensesKey, isManager: isManager),
            _LeavesTab(key: _leavesKey, isManager: isManager),
            _IncidentsTab(key: _incidentsKey, isManager: isManager),
            _RatingsTab(key: _ratingsKey),
            _RoutesTab(key: _routesKey, isManager: isManager),
            _HolidaysTab(key: _holidaysKey, isManager: isManager),
          ],
        ),
      ),
    );
  }
}

class _ExpensesTab extends ConsumerStatefulWidget {
  final bool isManager;
  const _ExpensesTab({super.key, required this.isManager});

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

  Future<void> add() async {
    final c = BestieColors.of(context);
    final typeCtrl = TextEditingController(text: 'Travel');
    final amountCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: formatFieldDate(DateTime.now()));
    final ok = await showFieldFormDialog(
      context: context,
      title: 'New expense',
      subtitle: 'Submit a travel or field expense for approval.',
      confirmLabel: 'Submit',
      fields: [
        fieldFormTextField(c, controller: typeCtrl, label: 'Type'),
        fieldFormTextField(
          c,
          controller: amountCtrl,
          label: 'Amount',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        fieldFormDateField(context, c, controller: dateCtrl, label: 'Date'),
      ],
    );
    if (ok != true) {
      typeCtrl.dispose();
      amountCtrl.dispose();
      dateCtrl.dispose();
      return;
    }
    try {
      String? receiptUrl;
      final pickReceipt = await showFieldConfirmDialog(
        context: context,
        title: 'Receipt',
        message: 'Attach a receipt photo?',
        confirmLabel: 'Attach',
        cancelLabel: 'Skip',
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
    final me = ref.watch(authStoreProvider).user;
    if (_loading) return const Center(child: BestieSpinner());
    return RefreshIndicator(
      onRefresh: _load,
      color: c.brand,
      child: _items.isEmpty
          ? ListView(
              padding: _hrListPadding(context),
              children: [
                _HrEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No expenses yet',
                  subtitle: 'Tap Add expense to submit your first claim.',
                  color: c,
                ),
              ],
            )
          : ListView.separated(
              padding: _hrListPadding(context),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final e = _items[i];
                final canReview = widget.isManager &&
                    e['status'] == 'pending' &&
                    canApproveFieldSubmission(me, e);
                return _HrRecordCard(
                  c: c,
                  icon: Icons.payments_outlined,
                  title: '${e['type']} — ${e['amount']}',
                  subtitle: e['expenseDate']?.toString() ?? '',
                  badge: _HrStatusBadge(status: e['status']?.toString()),
                  trailing: canReview
                      ? _HrReviewActions(
                          c: c,
                          onApprove: () async {
                            await ref.read(apiProvider).approveFieldExpense(e['id'].toString());
                            await _load();
                          },
                          onReject: () async {
                            await ref.read(apiProvider).rejectFieldExpense(e['id'].toString());
                            await _load();
                          },
                        )
                      : null,
                );
              },
            ),
    );
  }
}

class _LeavesTab extends ConsumerStatefulWidget {
  final bool isManager;
  const _LeavesTab({super.key, required this.isManager});

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

  Future<void> apply() async {
    final c = BestieColors.of(context);
    final typeCtrl = TextEditingController(text: 'Casual');
    final fromCtrl = TextEditingController(text: formatFieldDate(DateTime.now()));
    final toCtrl = TextEditingController(text: formatFieldDate(DateTime.now()));
    final ok = await showFieldFormDialog(
      context: context,
      title: 'Apply leave',
      subtitle: 'Choose leave type and date range.',
      confirmLabel: 'Apply',
      fields: [
        fieldFormTextField(c, controller: typeCtrl, label: 'Leave type'),
        fieldFormDateField(context, c, controller: fromCtrl, label: 'From date'),
        fieldFormDateField(context, c, controller: toCtrl, label: 'To date'),
      ],
    );
    if (ok != true) {
      typeCtrl.dispose();
      fromCtrl.dispose();
      toCtrl.dispose();
      return;
    }
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
    final me = ref.watch(authStoreProvider).user;
    if (_loading) return const Center(child: BestieSpinner());
    if (_items.isEmpty) {
      return ListView(
        padding: _hrListPadding(context),
        children: [
          _HrEmptyState(
            icon: Icons.beach_access_outlined,
            title: 'No leave requests',
            subtitle: 'Tap Apply leave to request time off.',
            color: c,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: _hrListPadding(context),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final l = _items[i];
        final canReview = widget.isManager &&
            l['status'] == 'pending' &&
            canApproveFieldSubmission(me, l);
        return _HrRecordCard(
          c: c,
          icon: Icons.event_busy_outlined,
          title: l['leaveType']?.toString() ?? 'Leave',
          subtitle: '${l['fromDate']} → ${l['toDate']}',
          badge: _HrStatusBadge(status: l['status']?.toString()),
          trailing: canReview
              ? _HrReviewActions(
                  c: c,
                  onApprove: () async {
                    await ref.read(apiProvider).approveFieldLeave(l['id'].toString());
                    await _load();
                  },
                  onReject: () async {
                    await ref.read(apiProvider).rejectFieldLeave(l['id'].toString());
                    await _load();
                  },
                )
              : null,
        );
      },
    );
  }
}

class _IncidentsTab extends ConsumerStatefulWidget {
  final bool isManager;
  const _IncidentsTab({super.key, required this.isManager});

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

  Future<void> report() async {
    final c = BestieColors.of(context);
    final typeCtrl = TextEditingController(text: 'Safety');
    final descCtrl = TextEditingController();
    final ok = await showFieldFormDialog(
      context: context,
      title: 'Report incident',
      subtitle: 'Describe what happened in the field.',
      confirmLabel: 'Report',
      fields: [
        fieldFormTextField(c, controller: typeCtrl, label: 'Type'),
        fieldFormTextField(c, controller: descCtrl, label: 'Description', maxLines: 3),
      ],
    );
    if (ok != true) {
      typeCtrl.dispose();
      descCtrl.dispose();
      return;
    }
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
    final me = ref.watch(authStoreProvider).user;
    if (_loading) return const Center(child: BestieSpinner());
    if (_items.isEmpty) {
      return ListView(
        padding: _hrListPadding(context),
        children: [
          _HrEmptyState(
            icon: Icons.report_problem_outlined,
            title: 'No incidents reported',
            subtitle: 'Tap Report to log a safety or field issue.',
            color: c,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: _hrListPadding(context),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final item = _items[i];
        final canResolve = widget.isManager &&
            item['status'] == 'open' &&
            item['id'] != null &&
            canApproveFieldSubmission(me, item);
        return _HrRecordCard(
          c: c,
          icon: Icons.warning_amber_rounded,
          title: item['type']?.toString() ?? 'Incident',
          subtitle: item['description']?.toString() ?? '',
          badge: _HrStatusBadge(status: item['status']?.toString()),
          trailing: canResolve
              ? IconButton(
                  tooltip: 'Resolve',
                  icon: Icon(Icons.done_all_rounded, color: c.success),
                  onPressed: () async {
                    await ref.read(apiProvider).resolveFieldIncident(item['id'].toString());
                    await _load();
                  },
                )
              : null,
        );
      },
    );
  }
}

class _RatingsTab extends ConsumerStatefulWidget {
  const _RatingsTab({super.key});
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

  Future<void> rate() async {
    final picked = await pickMarketingOutlet(context, ref, title: 'Rate which outlet?');
    if (picked == null) return;
    final c = BestieColors.of(context);
    final scoreCtrl = TextEditingController(text: '5');
    final ok = await showFieldFormDialog(
      context: context,
      title: 'Rate ${picked['name']}',
      subtitle: 'Score this outlet from 1 to 5.',
      fields: [
        fieldFormTextField(
          c,
          controller: scoreCtrl,
          label: 'Score (1–5)',
          keyboardType: TextInputType.number,
        ),
      ],
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
    if (_items.isEmpty) {
      return ListView(
        padding: _hrListPadding(context),
        children: [
          _HrEmptyState(
            icon: Icons.star_outline_rounded,
            title: 'No outlet ratings',
            subtitle: 'Tap Rate outlet to score an outlet visit.',
            color: c,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: _hrListPadding(context),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = _items[i];
        return _HrRecordCard(
          c: c,
          icon: Icons.star_rounded,
          iconColor: const Color(0xFFFBBC04),
          title: 'Score ${r['score']}',
          subtitle: '${r['entityType']} · ${r['entityId']}',
        );
      },
    );
  }
}

class _RoutesTab extends ConsumerStatefulWidget {
  final bool isManager;
  const _RoutesTab({super.key, required this.isManager});

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

  Future<void> addRoute() async {
    if (!widget.isManager) return;
    final c = BestieColors.of(context);
    final nameCtrl = TextEditingController();
    final ok = await showFieldFormDialog(
      context: context,
      title: 'New route',
      subtitle: 'Name the route, then pick outlets and an executive.',
      confirmLabel: 'Create',
      fields: [
        fieldFormTextField(c, controller: nameCtrl, label: 'Route name'),
      ],
    );
    if (ok != true) {
      nameCtrl.dispose();
      return;
    }
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

  Future<void> addDailyPlan() async {
    if (!widget.isManager) return;
    final c = BestieColors.of(context);
    final dateCtrl = TextEditingController(text: formatFieldDate(DateTime.now()));
    String? routeId;
    final ok = await showFieldFormDialogBuilder(
      context: context,
      title: 'Daily plan',
      subtitle: 'Schedule outlets for a specific day.',
      confirmLabel: 'Create',
      buildFields: (ctx, setDialogState) => [
        fieldFormDateField(ctx, c, controller: dateCtrl, label: 'Date'),
        fieldFormDropdown<String?>(
          c,
          value: routeId,
          label: 'Route (optional)',
          items: [
            DropdownMenuItem(value: null, child: Text('No route', style: TextStyle(color: c.text))),
            ..._routes.map(
              (r) => DropdownMenuItem(
                value: r['id']?.toString(),
                child: Text(r['name']?.toString() ?? 'Route', style: TextStyle(color: c.text)),
              ),
            ),
          ],
          onChanged: (v) => setDialogState(() => routeId = v),
        ),
      ],
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
    return RefreshIndicator(
      onRefresh: _load,
      color: c.brand,
      child: ListView(
        padding: _hrListPadding(context),
        children: [
          _HrSectionHeader(c: c, title: 'Today\'s plan', icon: Icons.today_outlined),
          const SizedBox(height: 10),
          if (_plans.isEmpty)
            _HrInlineEmpty(c: c, message: 'No daily plan scheduled for today.')
          else
            for (final p in _plans)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _HrRecordCard(
                  c: c,
                  icon: Icons.event_note_outlined,
                  title: 'Plan ${p['planDate']}',
                  subtitle: '${(p['outletIds'] as List?)?.length ?? 0} outlets',
                ),
              ),
          const SizedBox(height: 20),
          _HrSectionHeader(c: c, title: 'Routes', icon: Icons.route_outlined),
          const SizedBox(height: 10),
          if (_routes.isEmpty)
            _HrInlineEmpty(c: c, message: 'No routes created yet.')
          else
            for (final r in _routes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _HrRecordCard(
                  c: c,
                  icon: Icons.add_road_rounded,
                  title: r['name']?.toString() ?? 'Route',
                  subtitle:
                      '${(r['outletIds'] as List?)?.length ?? 0} outlets · ${(r['assignedTo'] as Map?)?['name'] ?? 'Unassigned'}',
                  onTap: widget.isManager
                      ? () => _editRoute(r)
                      : () => context.push('/marketing/outlets'),
                ),
              ),
        ],
      ),
    );
  }
}

class _HolidaysTab extends ConsumerStatefulWidget {
  final bool isManager;
  const _HolidaysTab({super.key, required this.isManager});

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

  Future<void> add() async {
    if (!widget.isManager) return;
    final c = BestieColors.of(context);
    final nameCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: formatFieldDate(DateTime.now()));
    final ok = await showFieldFormDialog(
      context: context,
      title: 'Add holiday',
      subtitle: 'Mark a company holiday on the calendar.',
      fields: [
        fieldFormTextField(c, controller: nameCtrl, label: 'Name'),
        fieldFormDateField(context, c, controller: dateCtrl, label: 'Date'),
      ],
    );
    if (ok != true) {
      nameCtrl.dispose();
      dateCtrl.dispose();
      return;
    }
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
    if (_items.isEmpty) {
      return ListView(
        padding: _hrListPadding(context),
        children: [
          _HrEmptyState(
            icon: Icons.celebration_outlined,
            title: 'No holidays added',
            subtitle: widget.isManager
                ? 'Tap Add holiday to mark a company holiday.'
                : 'Your manager will add company holidays here.',
            color: c,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: _hrListPadding(context),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final h = _items[i];
        return _HrRecordCard(
          c: c,
          icon: Icons.celebration_outlined,
          title: h['name']?.toString() ?? 'Holiday',
          subtitle: h['date']?.toString() ?? '',
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared Field HR layout helpers
// ---------------------------------------------------------------------------

const _kHrFabClearance = 92.0;

EdgeInsets _hrListPadding(BuildContext context) => EdgeInsets.fromLTRB(
      16,
      12,
      16,
      _kHrFabClearance + MediaQuery.paddingOf(context).bottom,
    );

class _HrEmptyState extends StatelessWidget {
  const _HrEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final BestieColors color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: color.brand),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: color.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: color.textMuted, fontSize: 14, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _HrInlineEmpty extends StatelessWidget {
  const _HrInlineEmpty({required this.c, required this.message});

  final BestieColors c;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        border: Border.all(color: c.borderSoft),
      ),
      child: Text(message, style: TextStyle(color: c.textMuted, fontSize: 13)),
    );
  }
}

class _HrSectionHeader extends StatelessWidget {
  const _HrSectionHeader({required this.c, required this.title, required this.icon});

  final BestieColors c;
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: c.brand),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: c.text),
        ),
      ],
    );
  }
}

class _HrRecordCard extends StatelessWidget {
  const _HrRecordCard({
    required this.c,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.badge,
    this.trailing,
    this.onTap,
  });

  final BestieColors c;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final Widget? badge;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        side: BorderSide(color: c.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.brandSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: iconColor ?? c.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: c.text,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.35),
                    ),
                    if (badge != null) ...[
                      const SizedBox(height: 8),
                      badge!,
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _HrStatusBadge extends StatelessWidget {
  const _HrStatusBadge({this.status});

  final String? status;

  BestieTone get _tone {
    switch (status?.toLowerCase()) {
      case 'approved':
      case 'resolved':
        return BestieTone.success;
      case 'rejected':
        return BestieTone.danger;
      case 'pending':
      case 'open':
      case 'queued':
        return BestieTone.warning;
      default:
        return BestieTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BestieBadge(
      tone: _tone,
      child: Text(status ?? 'unknown'),
    );
  }
}

class _HrReviewActions extends StatelessWidget {
  const _HrReviewActions({
    required this.c,
    required this.onApprove,
    required this.onReject,
  });

  final BestieColors c;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Approve',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.check_circle_outline, color: c.success),
          onPressed: onApprove,
        ),
        IconButton(
          tooltip: 'Reject',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.cancel_outlined, color: c.danger),
          onPressed: onReject,
        ),
      ],
    );
  }
}
