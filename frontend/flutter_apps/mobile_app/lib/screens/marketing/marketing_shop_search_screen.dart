import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';

/// Shop/business directory search — proxied via MyTaskKing `/marketing/businesses/search`.
class MarketingShopSearchScreen extends ConsumerStatefulWidget {
  const MarketingShopSearchScreen({super.key});

  @override
  ConsumerState<MarketingShopSearchScreen> createState() =>
      _MarketingShopSearchScreenState();
}

class _MarketingShopSearchScreenState
    extends ConsumerState<MarketingShopSearchScreen> {
  final _query = TextEditingController();
  final _area = TextEditingController();
  List<Map<String, dynamic>> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    final area = _area.text.trim();
    if (q.isEmpty && area.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await ref.read(apiProvider).searchBusinessDirectory(
            q: q.isNotEmpty ? q : area,
          );
      final data = resp['data'];
      List<Map<String, dynamic>> items = const [];
      if (data is List) {
        items = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else if (data is Map && data['items'] is List) {
        items = (data['items'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _results = items;
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

  Future<void> _saveAsOutlet(Map<String, dynamic> biz) async {
    try {
      await ref.read(apiProvider).createMarketingOutlet({
        'name': biz['name'] ?? biz['business_name'] ?? 'Shop',
        'phone': biz['phone'],
        'address': biz['address'],
        'latitude': biz['latitude'] ?? biz['lat'],
        'longitude': biz['longitude'] ?? biz['lng'],
        'category': (biz['categories'] is List && (biz['categories'] as List).isNotEmpty)
            ? (biz['categories'] as List).first.toString()
            : biz['category']?.toString(),
        'source': 'directory',
      });
      if (mounted) {
        bestieToast(context, 'Saved as outlet', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not save outlet',
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
        title: const Text('Shop search'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    labelText: 'Shop type (e.g. Plywood, Medical)',
                    filled: true,
                    fillColor: c.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _area,
                  decoration: InputDecoration(
                    labelText: 'Area (optional)',
                    filled: true,
                    fillColor: c.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _search,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search_rounded),
                    label: const Text('Search directory'),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: c.danger)),
            ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _loading ? 'Searching…' : 'Search businesses to add as outlets',
                      style: TextStyle(color: c.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final b = _results[i];
                      final name =
                          b['name']?.toString() ?? b['business_name']?.toString() ?? 'Business';
                      final address = b['address']?.toString() ?? '';
                      return Material(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(BestieTokens.rLg),
                        child: ListTile(
                          title: Text(name,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, color: c.text)),
                          subtitle: Text(address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.textMuted, fontSize: 12)),
                          trailing: IconButton(
                            tooltip: 'Save as outlet',
                            icon: Icon(Icons.add_business_outlined, color: c.brand),
                            onPressed: () => _saveAsOutlet(b),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
