import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';

/// Field order — pick products and place order at an outlet.
class MarketingOrdersScreen extends ConsumerStatefulWidget {
  final String? outletId;
  const MarketingOrdersScreen({super.key, this.outletId});

  @override
  ConsumerState<MarketingOrdersScreen> createState() =>
      _MarketingOrdersScreenState();
}

class _MarketingOrdersScreenState extends ConsumerState<MarketingOrdersScreen> {
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _orders = const [];
  final _cart = <String, int>{};
  String? _outletId;
  String? _outletName;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _outletId = widget.outletId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final productsResp = await api.listMarketingProducts();
      final ordersResp = await api.listFieldOrders();
      if (_outletId != null) {
        final outlet = await api.getMarketingOutlet(_outletId!);
        _outletName = outlet['name']?.toString();
      }
      if (!mounted) return;
      setState(() {
        _products = ((productsResp['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _orders = ((ordersResp['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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

  Future<void> _pickOutlet() async {
    final resp = await ref.read(apiProvider).listMarketingOutlets(pageSize: 50);
    final items = ((resp['items'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (!mounted || items.isEmpty) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('Select outlet')),
            for (final o in items)
              ListTile(
                title: Text(o['name']?.toString() ?? 'Outlet'),
                onTap: () => Navigator.pop(ctx, o),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _outletId = picked['id']?.toString();
        _outletName = picked['name']?.toString();
      });
    }
  }

  Future<void> _submit() async {
    if (_outletId == null) {
      bestieToast(context, 'Select an outlet first', kind: BestieToastKind.warning);
      return;
    }
    final lines = _cart.entries
        .where((e) => e.value > 0)
        .map((e) {
          final p = _products.firstWhere((x) => x['id'] == e.key);
          return {
            'productId': e.key,
            'quantity': e.value,
            'ptr': p['ptr'] ?? p['mrp'] ?? 0,
            'mrp': p['mrp'],
          };
        })
        .toList();
    if (lines.isEmpty) {
      bestieToast(context, 'Add at least one product', kind: BestieToastKind.warning);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(apiProvider).createFieldOrder({
        'outletId': _outletId,
        'items': lines,
        'status': 'submitted',
      });
      if (!mounted) return;
      setState(() => _cart.clear());
      bestieToast(context, 'Order placed', kind: BestieToastKind.success);
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Order failed',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: const Text('Field orders'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
      ),
      floatingActionButton: _cart.values.any((q) => q > 0)
          ? FloatingActionButton.extended(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: const Text('Place order'),
            )
          : null,
      body: _loading
          ? const Center(child: BestieSpinner())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: c.danger)))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: OutlinedButton.icon(
                        onPressed: _pickOutlet,
                        icon: const Icon(Icons.storefront_outlined),
                        label: Text(_outletName ?? 'Select outlet'),
                      ),
                    ),
                    Expanded(
                      child: DefaultTabController(
                        length: 2,
                        child: Column(
                          children: [
                            TabBar(
                              labelColor: c.brand,
                              tabs: const [
                                Tab(text: 'Products'),
                                Tab(text: 'My orders'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _products.isEmpty
                                      ? Center(
                                          child: Text('No products yet',
                                              style: TextStyle(color: c.textMuted)))
                                      : ListView.separated(
                                          padding: const EdgeInsets.all(16),
                                          itemCount: _products.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 8),
                                          itemBuilder: (_, i) {
                                            final p = _products[i];
                                            final id = p['id'].toString();
                                            final qty = _cart[id] ?? 0;
                                            return Material(
                                              color: c.surface2,
                                              borderRadius: BorderRadius.circular(
                                                  BestieTokens.rLg),
                                              child: ListTile(
                                                title: Text(
                                                    p['name']?.toString() ?? 'Product',
                                                    style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        color: c.text)),
                                                subtitle: Text(
                                                  'PTR ${p['ptr'] ?? p['mrp'] ?? '—'}',
                                                  style: TextStyle(
                                                      color: c.textMuted,
                                                      fontSize: 12),
                                                ),
                                                trailing: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.remove_circle_outline),
                                                      onPressed: qty > 0
                                                          ? () => setState(
                                                              () => _cart[id] = qty - 1)
                                                          : null,
                                                    ),
                                                    Text('$qty'),
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.add_circle_outline),
                                                      onPressed: () => setState(
                                                          () => _cart[id] = qty + 1),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                  _orders.isEmpty
                                      ? Center(
                                          child: Text('No orders yet',
                                              style: TextStyle(color: c.textMuted)))
                                      : ListView.separated(
                                          padding: const EdgeInsets.all(16),
                                          itemCount: _orders.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 8),
                                          itemBuilder: (_, i) {
                                            final o = _orders[i];
                                            final outlet =
                                                (o['outlet'] as Map?)?.cast<String, dynamic>();
                                            return Material(
                                              color: c.surface2,
                                              borderRadius: BorderRadius.circular(
                                                  BestieTokens.rLg),
                                              child: ListTile(
                                                title: Text(
                                                    outlet?['name']?.toString() ??
                                                        'Order',
                                                    style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        color: c.text)),
                                                subtitle: Text(
                                                  'Total ${o['total'] ?? o['subtotal'] ?? '—'} · ${o['status'] ?? ''}',
                                                  style: TextStyle(
                                                      color: c.textMuted,
                                                      fontSize: 12),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
