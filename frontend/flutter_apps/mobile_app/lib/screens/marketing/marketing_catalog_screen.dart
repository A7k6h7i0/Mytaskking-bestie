import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  Future<bool> _confirmDelete(String label) async {
    return bestieConfirm(
      context,
      title: 'Delete $label?',
      description: 'This cannot be undone.',
      confirmLabel: 'Delete',
      dangerous: true,
    );
  }

  Future<void> _showProductDialog({Map<String, dynamic>? product}) async {
    final editing = product != null;
    final nameCtrl = TextEditingController(text: product?['name']?.toString() ?? '');
    final skuCtrl = TextEditingController(text: product?['sku']?.toString() ?? '');
    final ptrCtrl = TextEditingController(text: product?['ptr']?.toString() ?? '');
    final mrpCtrl = TextEditingController(text: product?['mrp']?.toString() ?? '');
    String? brandId = (product?['brand'] as Map?)?['id']?.toString() ??
        product?['brandId']?.toString();
    String? categoryId = (product?['category'] as Map?)?['id']?.toString() ??
        product?['categoryId']?.toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(editing ? 'Edit product' : 'Add product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name *')),
                TextField(
                    controller: skuCtrl,
                    decoration: const InputDecoration(labelText: 'SKU')),
                TextField(
                    controller: ptrCtrl,
                    decoration: const InputDecoration(labelText: 'PTR'),
                    keyboardType: TextInputType.number),
                TextField(
                    controller: mrpCtrl,
                    decoration: const InputDecoration(labelText: 'MRP'),
                    keyboardType: TextInputType.number),
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
    final payload = {
      'name': nameCtrl.text.trim(),
      if (skuCtrl.text.trim().isNotEmpty) 'sku': skuCtrl.text.trim(),
      if (ptrCtrl.text.trim().isNotEmpty) 'ptr': double.tryParse(ptrCtrl.text.trim()),
      if (mrpCtrl.text.trim().isNotEmpty) 'mrp': double.tryParse(mrpCtrl.text.trim()),
      'brandId': brandId,
      'categoryId': categoryId,
    };
    nameCtrl.dispose();
    skuCtrl.dispose();
    ptrCtrl.dispose();
    mrpCtrl.dispose();
    try {
      final api = ref.read(apiProvider);
      if (editing) {
        await api.updateMarketingProduct(product['id'].toString(), payload);
      } else {
        await api.createMarketingProduct(payload);
      }
      await _load();
      if (mounted) {
        bestieToast(context, editing ? 'Product updated' : 'Product added',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Failed', body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final name = product['name']?.toString() ?? 'product';
    if (!await _confirmDelete(name)) return;
    try {
      await ref.read(apiProvider).deleteMarketingProduct(product['id'].toString());
      await _load();
      if (mounted) {
        bestieToast(context, 'Product removed', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Delete failed', body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _showNameDialog({
    required String title,
    Map<String, dynamic>? item,
    required Future<void> Function(String name) onSave,
  }) async {
    final nameCtrl = TextEditingController(text: item?['name']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) {
      nameCtrl.dispose();
      return;
    }
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    try {
      await onSave(name);
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Failed', body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _deleteNamedItem({
    required Map<String, dynamic> item,
    required String label,
    required Future<void> Function(String id) onDelete,
  }) async {
    final name = item['name']?.toString() ?? label;
    if (!await _confirmDelete(name)) return;
    try {
      await onDelete(item['id'].toString());
      await _load();
      if (mounted) {
        bestieToast(context, '${label[0].toUpperCase()}${label.substring(1)} removed',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Delete failed', body: formatApiError(e), kind: BestieToastKind.error);
      }
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
      actions: [
        IconButton(
          tooltip: 'Export Excel',
          icon: const Icon(Icons.download_rounded),
          onPressed: () => context.push('/field/export'),
        ),
      ],
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
                        _ProductsTab(
                          products: _products,
                          onAdd: () => _showProductDialog(),
                          onEdit: (p) => _showProductDialog(product: p),
                          onDelete: _deleteProduct,
                        ),
                        _SimpleListTab(
                          items: _brands,
                          label: 'brand',
                          onAdd: () => _showNameDialog(
                            title: 'Add brand',
                            onSave: (name) =>
                                ref.read(apiProvider).createMarketingBrand({'name': name}),
                          ),
                          onEdit: (item) => _showNameDialog(
                            title: 'Edit brand',
                            item: item,
                            onSave: (name) => ref
                                .read(apiProvider)
                                .updateMarketingBrand(item['id'].toString(), {'name': name}),
                          ),
                          onDelete: (item) => _deleteNamedItem(
                            item: item,
                            label: 'brand',
                            onDelete: ref.read(apiProvider).deleteMarketingBrand,
                          ),
                        ),
                        _SimpleListTab(
                          items: _categories,
                          label: 'category',
                          onAdd: () => _showNameDialog(
                            title: 'Add category',
                            onSave: (name) =>
                                ref.read(apiProvider).createMarketingCategory({'name': name}),
                          ),
                          onEdit: (item) => _showNameDialog(
                            title: 'Edit category',
                            item: item,
                            onSave: (name) => ref
                                .read(apiProvider)
                                .updateMarketingCategory(item['id'].toString(), {'name': name}),
                          ),
                          onDelete: (item) => _deleteNamedItem(
                            item: item,
                            label: 'category',
                            onDelete: ref.read(apiProvider).deleteMarketingCategory,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CatalogActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CatalogActions({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Edit',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.edit_outlined, color: c.brand, size: 20),
          onPressed: onEdit,
        ),
        IconButton(
          tooltip: 'Delete',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.delete_outline, color: c.danger, size: 20),
          onPressed: onDelete,
        ),
      ],
    );
  }
}

class _ProductsTab extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;

  const _ProductsTab({
    required this.products,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

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
                  trailing: _CatalogActions(
                    onEdit: () => onEdit(p),
                    onDelete: () => onDelete(p),
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
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;

  const _SimpleListTab({
    required this.items,
    required this.label,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

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
              itemBuilder: (_, i) {
                final item = items[i];
                return ListTile(
                  tileColor: c.surface2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text(item['name']?.toString() ?? label),
                  trailing: _CatalogActions(
                    onEdit: () => onEdit(item),
                    onDelete: () => onDelete(item),
                  ),
                );
              },
            ),
    );
  }
}
