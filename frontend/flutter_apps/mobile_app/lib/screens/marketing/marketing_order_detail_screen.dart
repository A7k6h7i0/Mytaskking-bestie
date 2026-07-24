import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import 'field_sub_scaffold.dart';

/// Full field order — outlet, line items, totals, executive (read-only).
class MarketingOrderDetailScreen extends ConsumerStatefulWidget {
  const MarketingOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<MarketingOrderDetailScreen> createState() =>
      _MarketingOrderDetailScreenState();
}

class _MarketingOrderDetailScreenState
    extends ConsumerState<MarketingOrderDetailScreen> {
  Map<String, dynamic>? _order;
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
      final order = await ref.read(apiProvider).getFieldOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
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

  String _money(dynamic v) {
    if (v == null) return '—';
    final n = double.tryParse(v.toString());
    if (n == null) return v.toString();
    return n.toStringAsFixed(2);
  }

  String _formatDt(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final order = _order;

    return FieldSubScaffold(
      title: 'Order details',
      body: _loading
          ? const Center(child: BestieSpinner())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: TextStyle(color: c.danger)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : order == null
                  ? Center(
                      child: Text('Order not found',
                          style: TextStyle(color: c.textMuted)),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        _headerCard(c, order),
                        const SizedBox(height: 16),
                        _outletCard(c, order),
                        const SizedBox(height: 16),
                        Text(
                          'Line items',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: c.text,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ..._lineItems(c, order),
                        const SizedBox(height: 16),
                        _totalsCard(c, order),
                        if (order['notes']?.toString().trim().isNotEmpty == true) ...[
                          const SizedBox(height: 16),
                          _notesCard(c, order['notes'].toString()),
                        ],
                      ],
                    ),
    );
  }

  Widget _headerCard(BestieColors c, Map<String, dynamic> order) {
    final user = (order['user'] as Map?)?.cast<String, dynamic>();
    final status = order['status']?.toString() ?? 'submitted';
    return _card(
      c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: c.brandSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: c.brand,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatDt(order['createdAt']?.toString()),
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Total ${_money(order['total'] ?? order['subtotal'])}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: c.text,
            ),
          ),
          if (user?['name'] != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person_outline, size: 16, color: c.textMuted),
                const SizedBox(width: 6),
                Text(
                  user!['name'].toString(),
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ),
              ],
            ),
          ],
          if (order['paymentMode'] != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.payment_outlined, size: 16, color: c.textMuted),
                const SizedBox(width: 6),
                Text(
                  order['paymentMode'].toString(),
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _outletCard(BestieColors c, Map<String, dynamic> order) {
    final outlet = (order['outlet'] as Map?)?.cast<String, dynamic>() ?? {};
    final outletId = outlet['id']?.toString();
    final lines = [
      if (outlet['address'] != null) outlet['address'].toString(),
      if (outlet['city'] != null) outlet['city'].toString(),
      if (outlet['phone'] != null) outlet['phone'].toString(),
    ].where((s) => s.isNotEmpty).toList();

    return _card(
      c,
      child: InkWell(
        onTap: outletId != null ? () => context.push('/marketing/outlets/$outletId') : null,
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                child: Icon(Icons.storefront_outlined, color: c.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      outlet['name']?.toString() ?? 'Outlet',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: c.text,
                      ),
                    ),
                    for (final line in lines) ...[
                      const SizedBox(height: 4),
                      Text(
                        line,
                        style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
              if (outletId != null)
                Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _lineItems(BestieColors c, Map<String, dynamic> order) {
    final items = ((order['items'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (items.isEmpty) {
      return [
        _card(
          c,
          child: Text('No line items', style: TextStyle(color: c.textMuted)),
        ),
      ];
    }
    return items.map((item) {
      final product = (item['product'] as Map?)?.cast<String, dynamic>();
      final name = product?['name']?.toString() ?? 'Product';
      final sku = product?['sku']?.toString();
      final qty = item['quantity'] ?? 0;
      final free = item['freeQuantity'] ?? 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _card(
          c,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: c.text,
                        fontSize: 14,
                      ),
                    ),
                    if (sku != null && sku.isNotEmpty)
                      Text('SKU $sku', style: TextStyle(color: c.textMuted, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      'Qty $qty${free > 0 ? ' + $free free' : ''} · PTR ${_money(item['ptr'])}',
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                _money(item['lineTotal']),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: c.text,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _totalsCard(BestieColors c, Map<String, dynamic> order) {
    return _card(
      c,
      child: Column(
        children: [
          _totalRow(c, 'Subtotal', _money(order['subtotal'])),
          if (order['discount'] != null && order['discount'].toString() != '0')
            _totalRow(c, 'Discount', _money(order['discount'])),
          if (order['gst'] != null && order['gst'].toString() != '0')
            _totalRow(c, 'GST', _money(order['gst'])),
          const Divider(height: 20),
          _totalRow(
            c,
            'Total',
            _money(order['total'] ?? order['subtotal']),
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _totalRow(BestieColors c, String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: bold ? c.text : c.textMuted,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              fontSize: bold ? 16 : 14,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: c.text,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notesCard(BestieColors c, String notes) {
    return _card(
      c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notes', style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(height: 6),
          Text(notes, style: TextStyle(color: c.textMuted, height: 1.4)),
        ],
      ),
    );
  }

  Widget _card(BestieColors c, {required Widget child}) {
    return Material(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        side: BorderSide(color: c.borderSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}
