import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';
import '../utils/payment_checkout.dart';
import '../utils/subscription_status.dart';

/// Organisation admin — account details, subscription status, and payment.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _account;
  List<Map<String, dynamic>> _plans = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  late final TextEditingController _name;
  late final TextEditingController _adminName;
  late final TextEditingController _adminEmail;
  late final TextEditingController _adminPhone;
  late final TextEditingController _newPassword;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _name = TextEditingController();
    _adminName = TextEditingController();
    _adminEmail = TextEditingController();
    _adminPhone = TextEditingController();
    _newPassword = TextEditingController();
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _adminName.dispose();
    _adminEmail.dispose();
    _adminPhone.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load(showSpinner: false));
    }
  }

  void _fillForm(Map<String, dynamic> account) {
    final admin = (account['admin'] as Map?)?.cast<String, dynamic>();
    final reg = (account['registration'] as Map?)?.cast<String, dynamic>();
    _name.text = account['name']?.toString() ?? '';
    _adminName.text = admin?['name']?.toString() ?? '';
    _adminEmail.text =
        reg?['adminEmail']?.toString() ?? admin?['email']?.toString() ?? '';
    _adminPhone.text =
        reg?['adminPhone']?.toString() ?? admin?['phone']?.toString() ?? '';
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = ref.read(apiProvider);
      final results = await Future.wait([
        api.getMyOrganizationAccount(),
        api.listPublicBillingPlans(),
      ]);
      if (!mounted) return;
      final account = results[0] as Map<String, dynamic>;
      final plans = results[1] as List<Map<String, dynamic>>;
      _fillForm(account);
      setState(() {
        _account = account;
        _plans = plans;
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

  String? get _tenantId => _account?['id']?.toString();

  Future<void> _saveDetails() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'adminName': _adminName.text.trim(),
        'adminEmail': _adminEmail.text.trim(),
        'adminPhone': _adminPhone.text.trim(),
      };
      if (_newPassword.text.isNotEmpty) {
        data['adminPassword'] = _newPassword.text;
      }
      final updated =
          await ref.read(apiProvider).updateMyOrganizationAccount(data);
      _newPassword.clear();
      if (!mounted) return;
      setState(() => _account = updated);
      bestieToast(context, 'Account updated',
          kind: BestieToastKind.success);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not save',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _payNow(String planId) async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    final launched = await launchPaymentCheckout(
      context,
      tenantId: tenantId,
      planId: planId,
    );
    if (launched && mounted) {
      bestieToast(
        context,
        'Complete payment in browser',
        body: 'Return here to see your updated plan.',
        kind: BestieToastKind.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final sub = (_account?['subscription'] as Map?)?.cast<String, dynamic>();
    final statusLabel = subscriptionStatusLabel(sub);

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: const Text('Subscription'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: TextStyle(color: c.danger)),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      MediaQuery.paddingOf(context).bottom + 48,
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: c.brandSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: c.borderSoft),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Account status',
                                style: TextStyle(
                                    color: c.textMuted,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: c.text,
                              ),
                            ),
                            if (_account?['slug'] != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Login slug: ${_account!['slug']}',
                                style: TextStyle(color: c.textMuted),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Organisation details',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: c.text)),
                      const SizedBox(height: 10),
                      _field(_name, 'Company name'),
                      _field(_adminName, 'Admin name'),
                      _field(_adminEmail, 'Admin email'),
                      _field(_adminPhone, 'Admin phone',
                          keyboard: TextInputType.phone),
                      _field(_newPassword, 'New password (optional)',
                          obscure: true),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _saving ? null : _saveDetails,
                        style: FilledButton.styleFrom(
                            backgroundColor: c.brand),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save changes'),
                      ),
                      const SizedBox(height: 28),
                      Text('Available plans',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: c.text)),
                      const SizedBox(height: 10),
                      if (_plans.isEmpty)
                        Text('No plans available yet.',
                            style: TextStyle(color: c.textMuted))
                      else
                        ..._plans.map((plan) {
                          final id = plan['id']?.toString() ?? '';
                          final label =
                              plan['label']?.toString() ?? 'Plan';
                          final inr = plan['amountInr'] ??
                              (((plan['amountPaise'] as num?) ?? 0) / 100);
                          final monthCount =
                              (plan['months'] ?? plan['planMonths']) as num?;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: c.text,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    monthCount != null
                                        ? '₹$inr · ${monthCount.toInt()} month${monthCount == 1 ? '' : 's'}'
                                        : '₹$inr',
                                    style: TextStyle(color: c.textMuted),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed:
                                        id.isEmpty ? null : () => _payNow(id),
                                    style: FilledButton.styleFrom(
                                        backgroundColor: c.brand),
                                    child: const Text('Pay now'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool obscure = false,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
