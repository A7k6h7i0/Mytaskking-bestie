import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';

class MarketingOutletsScreen extends ConsumerStatefulWidget {
  const MarketingOutletsScreen({super.key});

  @override
  ConsumerState<MarketingOutletsScreen> createState() =>
      _MarketingOutletsScreenState();
}

class _MarketingOutletsScreenState extends ConsumerState<MarketingOutletsScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;
  String? _approvalFilter;

  bool get _isManager {
    final role = ref.read(authStoreProvider).user?.role ?? '';
    return role == 'ADMIN' ||
        role == 'SUPER_ADMIN' ||
        role == 'MANAGER' ||
        role == 'PROJECT_COORDINATOR_MANAGER';
  }

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await ref.read(apiProvider).listMarketingOutlets(
            search: _search.text.trim(),
            approvalStatus: _approvalFilter,
          );
      final items = (resp['items'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _items = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  Future<void> _addOutlet() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final c = BestieColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add outlet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Shop name')),
            TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone')),
          ],
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
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    try {
      await ref.read(apiProvider).createMarketingOutlet({
        'name': nameCtrl.text.trim(),
        if (phoneCtrl.text.trim().isNotEmpty) 'phone': phoneCtrl.text.trim(),
      });
      await _load();
      if (mounted) {
        bestieToast(context, 'Outlet added', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not add outlet',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
    }
  }

  Future<void> _approveOutlet(String id) async {
    try {
      await ref.read(apiProvider).approveMarketingOutlet(id);
      await _load();
      if (mounted) {
        bestieToast(context, 'Outlet approved', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Approve failed',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: const Text('Outlets'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addOutlet,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Add outlet'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                if (_isManager)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('All'),
                          selected: _approvalFilter == null,
                          onSelected: (_) {
                            setState(() => _approvalFilter = null);
                            _load();
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Pending approval'),
                          selected: _approvalFilter == 'pending',
                          onSelected: (_) {
                            setState(() => _approvalFilter = 'pending');
                            _load();
                          },
                        ),
                      ],
                    ),
                  ),
                if (_isManager) const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, color: c.textMuted),
                    hintText: 'Search outlets',
                    filled: true,
                    fillColor: c.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BestieTokens.rPill),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: BestieSpinner())
                  : _error != null
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(_error!, style: TextStyle(color: c.danger)),
                            ),
                          ],
                        )
                      : _items.isEmpty
                          ? ListView(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    children: [
                                      Icon(Icons.storefront_outlined,
                                          size: 56, color: c.textMuted),
                                      const SizedBox(height: 12),
                                      Text('No outlets yet',
                                          style: TextStyle(
                                              color: c.text,
                                              fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final o = _items[i];
                                final assignee =
                                    (o['assignedTo'] as Map?)?.cast<String, dynamic>();
                                return Material(
                                  color: c.surface2,
                                  borderRadius:
                                      BorderRadius.circular(BestieTokens.rLg),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: c.brandSoft,
                                      child: Icon(Icons.store, color: c.brand, size: 20),
                                    ),
                                    title: Text(o['name']?.toString() ?? 'Outlet',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: c.text)),
                                    subtitle: Text(
                                      [
                                        if (o['city'] != null) o['city'].toString(),
                                        if (o['phone'] != null) o['phone'].toString(),
                                        if (assignee?['name'] != null)
                                          'Assigned: ${assignee!['name']}',
                                      ].join(' · '),
                                      style: TextStyle(color: c.textMuted, fontSize: 12),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_isManager &&
                                            o['approvalStatus'] == 'pending')
                                          IconButton(
                                            tooltip: 'Approve',
                                            icon: Icon(Icons.check_circle_outline,
                                                color: c.success),
                                            onPressed: () =>
                                                _approveOutlet(o['id'].toString()),
                                          ),
                                        Icon(Icons.chevron_right_rounded,
                                            color: c.textMuted),
                                      ],
                                    ),
                                    onTap: () {
                                      final id = o['id']?.toString();
                                      if (id != null) {
                                        context.push('/marketing/outlets/$id');
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}
