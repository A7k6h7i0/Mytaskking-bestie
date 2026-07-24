import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import '../shell_screen.dart';
import 'add_outlet_screen.dart';
import 'field_helpers.dart';
import 'field_route_helpers.dart';

class MarketingOutletsScreen extends ConsumerStatefulWidget {
  const MarketingOutletsScreen({super.key});

  @override
  ConsumerState<MarketingOutletsScreen> createState() =>
      _MarketingOutletsScreenState();
}

class _MarketingOutletsScreenState extends ConsumerState<MarketingOutletsScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  LatLng? _position;
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
      final position = await FieldRouteHelpers.resolveCurrentPosition();
      final resp = await ref.read(apiProvider).listMarketingOutlets(
            search: _search.text.trim(),
            approvalStatus: _approvalFilter,
            pageSize: 100,
          );
      final items = (resp['items'] as List?) ?? const [];
      var mapped = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (position != null) {
        mapped = FieldRouteHelpers.withDistancesFrom(position, mapped);
      }
      if (!mounted) return;
      setState(() {
        _position = position;
        _items = mapped;
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
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddOutletScreen()),
    );
    if (saved == true) await _load();
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

  Widget _outletTrailing(
    BestieColors c,
    Map<String, dynamic> o,
  ) {
    final me = ref.read(authStoreProvider).user;
    final pt = FieldRouteHelpers.outletLatLng(o);
    final canApprove = canApproveMarketingOutlet(me, o);
    if (pt == null && !canApprove) {
      return Icon(Icons.chevron_right_rounded, color: c.textMuted);
    }
    if (pt != null && !canApprove) {
      return IconButton(
        tooltip: 'Navigate',
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.navigation_outlined, color: c.brand, size: 20),
        onPressed: () => _openOutletNavigation(o, pt),
      );
    }
    if (pt == null && canApprove) {
      return IconButton(
        tooltip: 'Approve',
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.check_circle_outline, color: c.success),
        onPressed: () => _approveOutlet(o['id'].toString()),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: Icon(Icons.more_vert_rounded, color: c.textMuted, size: 20),
      onSelected: (action) {
        if (action == 'nav' && pt != null) {
          _openOutletNavigation(o, pt);
        } else if (action == 'approve') {
          _approveOutlet(o['id'].toString());
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'nav',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.navigation_outlined, color: c.brand),
            title: const Text('Navigate'),
          ),
        ),
        PopupMenuItem(
          value: 'approve',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle_outline, color: c.success),
            title: const Text('Approve'),
          ),
        ),
      ],
    );
  }

  Future<void> _openOutletNavigation(Map<String, dynamic> o, LatLng pt) async {
    if (_position != null) {
      await FieldRouteHelpers.openMapsDirections(_position!, pt);
    } else {
      await FieldRouteHelpers.openMapsNavigation(
        pt,
        label: o['name']?.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final bottomClearance = shellNavClearance(context);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: const Text('Outlets'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: bottomClearance - 24),
        child: FloatingActionButton.extended(
          onPressed: _addOutlet,
          icon: const Icon(Icons.add_business_rounded),
          label: const Text('Add outlet'),
        ),
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
                              padding: EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                bottomClearance + 72,
                              ),
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
                                        if (o['_distKm'] != null)
                                          FieldRouteHelpers.formatKm(
                                              (o['_distKm'] as num).toDouble()),
                                        if (o['city'] != null) o['city'].toString(),
                                        if (o['phone'] != null) o['phone'].toString(),
                                        if (assignee?['name'] != null)
                                          'Assigned: ${assignee!['name']}',
                                      ].join(' · '),
                                      style: TextStyle(color: c.textMuted, fontSize: 12),
                                    ),
                                    trailing: _outletTrailing(c, o),
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
