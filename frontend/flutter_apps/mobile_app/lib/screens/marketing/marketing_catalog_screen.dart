import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import 'field_sub_scaffold.dart';

/// Manager catalog — products, brands, categories.
class MarketingCatalogScreen extends ConsumerStatefulWidget {
  const MarketingCatalogScreen({super.key});

  @override
  ConsumerState<MarketingCatalogScreen> createState() =>
      _MarketingCatalogScreenState();
}

class _MarketingCatalogScreenState extends ConsumerState<MarketingCatalogScreen> {
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _brands = const [];
  List<Map<String, dynamic>> _categories = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      final productsResp = await api.listMarketingProducts();
      final brands = await api.listMarketingBrands();
      final categories = await api.listMarketingCategories();
      if (!mounted) return;
      setState(() {
        _products = ((productsResp['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _brands = brands;
        _categories = categories;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addProduct() async {
    final nameCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final ptrCtrl = TextEditingController();
    final mrpCtrl = TextEditingController();
    String? brandId;
    String? categoryId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Add product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name *')),
                TextField(controller: skuCtrl, decoration: const InputDecoration(labelText: 'SKU')),
                TextField(controller: ptrCtrl, decoration: const InputDecoration(labelText: 'PTR'), keyboardType: TextInputType.number),
                TextField(controller: mrpCtrl, decoration: const InputDecoration(labelText: 'MRP'), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: brandId,
                  decoration: const InputDecoration(labelText: 'Brand'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    ..._brands.map((b) => DropdownMenuItem(
                          value: b['id']?.toString(),
                          child: Text(b['name']?.toString() ?? 'Brand'),
                        )),
                  ],
                  onChanged: (v) => setDialog(() => brandId = v),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    ..._categories.map((b) => DropdownMenuItem(
                          value: b['id']?.toString(),
                          child: Text(b['name']?.toString() ?? 'Category'),
                        )),
                  ],
                  onChanged: (v) => setDialog(() => categoryId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) {
      nameCtrl.dispose();
      skuCtrl.dispose();
      ptrCtrl.dispose();
      mrpCtrl.dispose();
      return;
    }
    try {
      await ref.read(apiProvider).createMarketingProduct({
        'name': nameCtrl.text.trim(),
        if (skuCtrl.text.trim().isNotEmpty) 'sku': skuCtrl.text.trim(),
        if (ptrCtrl.text.trim().isNotEmpty) 'ptr': double.tryParse(ptrCtrl.text.trim()),
        if (mrpCtrl.text.trim().isNotEmpty) 'mrp': double.tryParse(mrpCtrl.text.trim()),
        if (brandId != null) 'brandId': brandId,
        if (categoryId != null) 'categoryId': categoryId,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Failed', body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      nameCtrl.dispose();
      skuCtrl.dispose();
      ptrCtrl.dispose();
      mrpCtrl.dispose();
    }
  }

  Future<void> _addBrand() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add brand'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Brand name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).createMarketingBrand({'name': nameCtrl.text.trim()});
      await _load();
    } finally {
      nameCtrl.dispose();
    }
  }

  Future<void> _addCategory() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add category'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Category name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).createMarketingCategory({'name': nameCtrl.text.trim()});
      await _load();
    } finally {
      nameCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final isManager = ref.watch(authStoreProvider).user?.isFieldManager ?? false;
    if (!isManager) {
      return FieldSubScaffold(
        title: 'Catalog',
        body: Center(child: Text('Managers only', style: TextStyle(color: c.textMuted))),
      );
    }
    return FieldSubScaffold(
      title: 'Product catalog',
      body: _loading
          ? const Center(child: BestieSpinner())
          : DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    labelColor: c.brand,
                    tabs: const [
                      Tab(text: 'Products'),
                      Tab(text: 'Brands'),
                      Tab(text: 'Categories'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _ProductsTab(products: _products, onAdd: _addProduct),
                        _SimpleListTab(items: _brands, label: 'brand', onAdd: _addBrand),
                        _SimpleListTab(items: _categories, label: 'category', onAdd: _addCategory),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ProductsTab extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final VoidCallback onAdd;
  const _ProductsTab({required this.products, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(onPressed: onAdd, child: const Icon(Icons.add)),
      body: products.isEmpty
          ? Center(child: Text('No products yet', style: TextStyle(color: c.textMuted)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = products[i];
                final brand = (p['brand'] as Map?)?['name'];
                final category = (p['category'] as Map?)?['name'];
                return ListTile(
                  tileColor: c.surface2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text(p['name']?.toString() ?? 'Product'),
                  subtitle: Text(
                    'PTR ${p['ptr'] ?? p['mrp'] ?? '—'}'
                    '${brand != null ? ' · $brand' : ''}'
                    '${category != null ? ' · $category' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
    );
  }
}

class _SimpleListTab extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String label;
  final VoidCallback onAdd;
  const _SimpleListTab({required this.items, required this.label, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(onPressed: onAdd, child: const Icon(Icons.add)),
      body: items.isEmpty
          ? Center(child: Text('No $label yet', style: TextStyle(color: c.textMuted)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => ListTile(
                tileColor: c.surface2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text(items[i]['name']?.toString() ?? label),
              ),
            ),
    );
  }
}
