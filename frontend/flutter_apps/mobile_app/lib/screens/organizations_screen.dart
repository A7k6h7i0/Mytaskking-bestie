import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';
import 'shell_screen.dart';
import '../utils/subscription_status.dart';
import '../widgets/document_image_viewer.dart';

/// Platform super-admin screen — create and manage customer organisations.
class OrganizationsScreen extends ConsumerStatefulWidget {
  const OrganizationsScreen({super.key});

  @override
  ConsumerState<OrganizationsScreen> createState() => _OrganizationsScreenState();
}

class _OrganizationsScreenState extends ConsumerState<OrganizationsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _isOrgPaid(Map<String, dynamic> org) {
    final sub = (org['subscription'] as Map?)?.cast<String, dynamic>();
    return (sub?['status'] ?? '').toString() == 'PAID';
  }

  List<Map<String, dynamic>> _filteredItems() {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((org) {
      if (q == 'paid') return _isOrgPaid(org);
      if (q == 'unpaid') return !_isOrgPaid(org);
      final name = (org['name'] ?? '').toString().toLowerCase();
      final slug = (org['slug'] ?? '').toString().toLowerCase();
      final status = (org['status'] ?? '').toString().toLowerCase();
      final sub = (org['subscription'] as Map?)?.cast<String, dynamic>();
      final subLabel = subscriptionStatusLabel(sub).toLowerCase();
      final subStatus = (sub?['status'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          slug.contains(q) ||
          status.contains(q) ||
          subLabel.contains(q) ||
          subStatus.contains(q);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref.read(apiProvider).listTenants();
      if (!mounted) return;
      setState(() {
        _items = items.where((o) => (o['slug'] ?? '') != 'default').toList()
          ..sort((a, b) {
            final aPending = (a['status'] ?? '') == 'PENDING';
            final bPending = (b['status'] ?? '') == 'PENDING';
            if (aPending != bPending) return aPending ? -1 : 1;
            return 0;
          });
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

  Future<void> _setStatus(String id, String status) async {
    try {
      await ref.read(apiProvider).updateTenant(id, {'status': status});
      await _load();
      if (mounted) {
        bestieToast(context, 'Organisation updated',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not update organisation',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _showCreateSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _CreateOrganizationSheet(
        onCreate: (data) => ref.read(apiProvider).createTenant(data),
      ),
    );
    if (result == null || !mounted) return;
    await _load();
    if (!mounted) return;
    final org = result['organisation'] as Map<String, dynamic>?;
    final admin = result['admin'] as Map<String, dynamic>?;
    bestieToast(
      context,
      'Organisation created',
      body: 'Login: ${org?['slug']} / ${admin?['userId']}',
      kind: BestieToastKind.success,
    );
  }

  Future<void> _approve(String id) async {
    try {
      await ref.read(apiProvider).approveTenantRegistration(id);
      await _load();
      if (mounted) {
        bestieToast(context, 'Organisation approved',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not approve',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _reject(String id) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject registration'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    if (ok != true) {
      reasonCtrl.dispose();
      return;
    }
    try {
      await ref.read(apiProvider).rejectTenantRegistration(
            id,
            reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
          );
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not reject',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      reasonCtrl.dispose();
    }
  }

  Future<void> _deleteOrg(String id) async {
    final ok = await bestieConfirm(context,
        title: 'Delete organisation?',
        description: 'This permanently removes the organisation and its data.',
        confirmLabel: 'Delete',
        dangerous: true);
    if (!ok) return;
    try {
      await ref.read(apiProvider).deleteTenant(id);
      await _load();
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not delete',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _showDetails(Map<String, dynamic> org) async {
    final id = org['id']?.toString();
    if (id == null) return;

    final c = BestieColors.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic> full = org;
    try {
      full = await ref.read(apiProvider).getTenant(id);
    } catch (_) {
      // Fall back to list row if detail fetch fails.
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final content = _OrganizationDetailsBody(
      org: full,
      colors: c,
      onEdit: (full['status'] ?? '') == 'ACTIVE'
          ? () => _showEditOrg(full)
          : null,
    );

    if (wide) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
            child: content,
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          child: content,
        ),
      ),
    );
  }

  Future<void> _showEditOrg(Map<String, dynamic> org) async {
    final id = org['id']?.toString();
    if (id == null) return;

    final c = BestieColors.of(context);
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => _EditOrganizationSheet(
          scrollController: scrollCtrl,
          org: org,
          onSaveRegistration: (data) =>
              ref.read(apiProvider).updateTenantRegistration(id, data),
          onSaveSubscription: (data) =>
              ref.read(apiProvider).updateTenantSubscription(id, data),
        ),
      ),
    );
    if (updated == null || !mounted) return;
    await _load();
    if (mounted) {
      bestieToast(context, 'Organisation updated',
          kind: BestieToastKind.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final user = ref.watch(authStoreProvider).user;
    final isSuper = user?.isPlatformSuperAdmin ?? false;
    final isSales = user?.isSalesHead ?? false;
    final filtered = _filteredItems();
    final bottomClearance = shellNavClearance(context);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: Text(isSales ? 'Registration requests' : 'Organisations'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
      ),
      floatingActionButton: isSuper
          ? Padding(
              padding: EdgeInsets.only(bottom: bottomClearance - 24),
              child: FloatingActionButton.extended(
                onPressed: _showCreateSheet,
                icon: const Icon(Icons.add_business_rounded),
                label: const Text('Add organisation'),
              ),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon:
                    Icon(Icons.search_rounded, color: c.textMuted, size: 18),
                hintText: isSales
                    ? 'Search name, slug, paid, unpaid…'
                    : 'Search organisation name or slug…',
                filled: true,
                fillColor: c.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BestieTokens.rPill),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BestieTokens.rPill),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(_error!, style: TextStyle(color: c.danger)),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  )
                : _items.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Icon(Icons.apartment_rounded,
                              size: 48, color: c.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            'No customer organisations yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: c.text),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap Add organisation to onboard a company like Digital Links. Each org is fully private — only you see this list.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.textMuted, height: 1.4),
                          ),
                        ],
                      )
                    : filtered.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(24),
                            children: [
                              Icon(Icons.search_off_rounded,
                                  size: 48, color: c.textMuted),
                              const SizedBox(height: 12),
                              Text(
                                'No matches',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: c.text),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Try another name, slug, or type paid / unpaid.',
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(color: c.textMuted, height: 1.4),
                              ),
                            ],
                          )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          isSuper ? bottomClearance + 72 : bottomClearance,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final org = filtered[i];
                          final status =
                              (org['status'] ?? 'ACTIVE').toString();
                          final pending = status == 'PENDING';
                          final active = status == 'ACTIVE';
                          final statusColor = pending
                              ? c.brand
                              : active
                                  ? c.success
                                  : c.warning;
                          final statusBg = pending
                              ? c.brandSoft
                              : active
                                  ? c.successSoft
                                  : c.warningSoft;
                          final sub =
                              (org['subscription'] as Map?)?.cast<String, dynamic>();
                          return Material(
                            color: c.surface,
                            borderRadius:
                                BorderRadius.circular(BestieTokens.rLg),
                            child: InkWell(
                            onTap: () => _showDetails(org),
                            borderRadius:
                                BorderRadius.circular(BestieTokens.rLg),
                            child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius:
                                  BorderRadius.circular(BestieTokens.rLg),
                              border: Border.all(color: c.borderSoft),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.business_rounded,
                                        color: c.brand, size: 22),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        (org['name'] ?? 'Organisation')
                                            .toString(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: c.text,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusBg,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.info_outline_rounded,
                                          color: c.textMuted, size: 20),
                                      tooltip: 'View details',
                                      onPressed: () => _showDetails(org),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Login slug: ${org['slug']}',
                                  style: TextStyle(
                                      color: c.textMuted, fontSize: 13),
                                ),
                                Text(
                                  '${org['userCount'] ?? 0} users',
                                  style: TextStyle(
                                      color: c.textMuted, fontSize: 13),
                                ),
                                if (sub != null)
                                  Text(
                                    subscriptionStatusLabel(sub),
                                    style: TextStyle(
                                        color: c.textMuted, fontSize: 13),
                                  ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: pending
                                      ? Wrap(
                                          spacing: 8,
                                          children: [
                                            FilledButton(
                                              onPressed: () => _approve(
                                                org['id'].toString(),
                                              ),
                                              child: const Text('Approve'),
                                            ),
                                            TextButton(
                                              onPressed: () => _reject(
                                                org['id'].toString(),
                                              ),
                                              child: const Text('Reject'),
                                            ),
                                          ],
                                        )
                                      : Wrap(
                                          spacing: 8,
                                          children: [
                                            TextButton(
                                              onPressed: () => _setStatus(
                                                org['id'].toString(),
                                                active ? 'SUSPENDED' : 'ACTIVE',
                                              ),
                                              child: Text(active
                                                  ? 'Suspend'
                                                  : 'Activate'),
                                            ),
                                            if (isSuper)
                                              TextButton(
                                                onPressed: () => _deleteOrg(
                                                  org['id'].toString(),
                                                ),
                                                child: Text('Delete',
                                                    style: TextStyle(
                                                        color: c.danger)),
                                              ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
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

class _OrganizationDetailsBody extends StatelessWidget {
  const _OrganizationDetailsBody({
    required this.org,
    required this.colors,
    this.onEdit,
  });

  final Map<String, dynamic> org;
  final BestieColors colors;
  final VoidCallback? onEdit;

  String _fmt(dynamic v) {
    if (v == null) return '—';
    final s = v.toString().trim();
    return s.isEmpty ? '—' : s;
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '—';
    return v.toString().replaceFirst('T', ' ').split('.').first;
  }

  Widget _section(String title, List<Widget> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(color: colors.textMuted, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: colors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _idImage(BuildContext context, String? url, String title) {
    if (url == null || url.trim().isEmpty) {
      return Text('No image uploaded',
          style: TextStyle(color: colors.textMuted, fontSize: 12));
    }
    return InkWell(
      onTap: () => DocumentImageViewer.show(
        context,
        title: title,
        imageUrl: url,
      ),
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              height: 120,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Text('Could not load image',
                  style: TextStyle(color: colors.danger, fontSize: 12)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.fullscreen_rounded,
                color: Colors.white.withValues(alpha: 0.9), size: 20),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reg = (org['registration'] as Map?)?.cast<String, dynamic>();
    final sub = (org['subscription'] as Map?)?.cast<String, dynamic>();
    final status = _fmt(org['status']);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.business_rounded, color: colors.brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _fmt(org['name']),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit organisation',
                    onPressed: () {
                      Navigator.pop(context);
                      onEdit!();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _section('Organisation', [
              _row('Status', status),
              _row('Login slug', _fmt(org['slug'])),
              _row('Users', _fmt(org['userCount'])),
              _row('Created', _fmtDate(org['createdAt'])),
            ]),
            if (reg != null)
              _section('Registration & KYC', [
                _row('Admin phone', _fmt(reg['adminPhone'])),
                _row('Admin email', _fmt(reg['adminEmail'])),
                _row('Review status', _fmt(reg['reviewStatus'])),
                _row('Submitted', _fmtDate(reg['submittedAt'])),
                if ((reg['rejectReason'] ?? '').toString().isNotEmpty)
                  _row('Reject reason', _fmt(reg['rejectReason'])),
                const SizedBox(height: 6),
                Text('Government ID 1 (${_fmt(reg['govtId1Type'])})',
                    style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                _row('Number', _fmt(reg['govtId1Number'])),
                _idImage(
                  context,
                  reg['govtId1ImageUrl']?.toString(),
                  'Government ID 1 (${_fmt(reg['govtId1Type'])})',
                ),
                const SizedBox(height: 10),
                Text('Government ID 2 (${_fmt(reg['govtId2Type'])})',
                    style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                _row('Number', _fmt(reg['govtId2Number'])),
                _idImage(
                  context,
                  reg['govtId2ImageUrl']?.toString(),
                  'Government ID 2 (${_fmt(reg['govtId2Type'])})',
                ),
              ]),
            if (sub != null)
              _section('Billing', [
                _row('Account status', subscriptionStatusLabel(sub)),
                if (sub['planLabel'] != null)
                  _row('Plan', _fmt(sub['planLabel']))
                else if (sub['planMonths'] != null)
                  _row('Plan', '${sub['planMonths']} month(s)'),
                if (sub['amountPaise'] != null)
                  _row('Paid', '₹${(sub['amountPaise'] as num) / 100}'),
                _row('Trial ends', _fmtDate(sub['trialEndsAt'])),
                _row('Paid until', _fmtDate(sub['paidUntil'])),
                _row('Payment ref', _fmt(sub['paymentReference'])),
                _row('Razorpay order', _fmt(sub['razorpayOrderId'])),
              ]),
            if (reg == null && sub == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'No registration or billing details on file for this organisation.',
                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EditOrganizationSheet extends StatefulWidget {
  const _EditOrganizationSheet({
    required this.org,
    required this.onSaveRegistration,
    required this.onSaveSubscription,
    this.scrollController,
  });

  final ScrollController? scrollController;
  final Map<String, dynamic> org;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)
      onSaveRegistration;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)
      onSaveSubscription;

  @override
  State<_EditOrganizationSheet> createState() => _EditOrganizationSheetState();
}

class _EditOrganizationSheetState extends State<_EditOrganizationSheet> {
  late final TextEditingController _name;
  late final TextEditingController _adminName;
  late final TextEditingController _adminEmail;
  late final TextEditingController _adminPhone;
  late final TextEditingController _adminPassword;
  DateTime? _trialEndsAt;
  DateTime? _paidUntil;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final reg = (widget.org['registration'] as Map?)?.cast<String, dynamic>();
    final sub = (widget.org['subscription'] as Map?)?.cast<String, dynamic>();
    _name = TextEditingController(text: widget.org['name']?.toString() ?? '');
    _adminName = TextEditingController();
    _adminEmail =
        TextEditingController(text: reg?['adminEmail']?.toString() ?? '');
    _adminPhone =
        TextEditingController(text: reg?['adminPhone']?.toString() ?? '');
    _adminPassword = TextEditingController();
    _trialEndsAt = _parseDate(sub?['trialEndsAt']);
    _paidUntil = _parseDate(sub?['paidUntil']);
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  @override
  void dispose() {
    _name.dispose();
    _adminName.dispose();
    _adminEmail.dispose();
    _adminPhone.dispose();
    _adminPassword.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required bool trial,
  }) async {
    final initial = trial ? _trialEndsAt : _paidUntil;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (trial) {
        _trialEndsAt = picked;
      } else {
        _paidUntil = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final regData = <String, dynamic>{
        'name': _name.text.trim(),
        'adminEmail': _adminEmail.text.trim(),
        'adminPhone': _adminPhone.text.trim(),
      };
      if (_adminName.text.trim().isNotEmpty) {
        regData['adminName'] = _adminName.text.trim();
      }
      if (_adminPassword.text.isNotEmpty) {
        regData['adminPassword'] = _adminPassword.text;
      }
      await widget.onSaveRegistration(regData);
      await widget.onSaveSubscription({
        if (_trialEndsAt != null)
          'trialEndsAt': _trialEndsAt!.toIso8601String(),
        if (_paidUntil != null) 'paidUntil': _paidUntil!.toIso8601String(),
      });
      if (!mounted) return;
      Navigator.pop(context, {'ok': true});
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not save',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        controller: widget.scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: c.textMuted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Edit organisation',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: c.text)),
            const SizedBox(height: 16),
            TextField(
                controller: _name, decoration: const InputDecoration(labelText: 'Company name')),
            TextField(
                controller: _adminName,
                decoration: const InputDecoration(labelText: 'Admin name')),
            TextField(
                controller: _adminEmail,
                decoration: const InputDecoration(labelText: 'Admin email')),
            TextField(
                controller: _adminPhone,
                decoration: const InputDecoration(labelText: 'Admin phone')),
            TextField(
                controller: _adminPassword,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'New admin password (optional)')),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Trial ends'),
              subtitle: Text(_trialEndsAt?.toString().split(' ').first ??
                  'Not set'),
              trailing: IconButton(
                icon: const Icon(Icons.calendar_today_outlined),
                onPressed: () => _pickDate(trial: true),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Account expires (paid until)'),
              subtitle: Text(_paidUntil?.toString().split(' ').first ??
                  'Not set'),
              trailing: IconButton(
                icon: const Icon(Icons.calendar_today_outlined),
                onPressed: () => _pickDate(trial: false),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateOrganizationSheet extends StatefulWidget {
  const _CreateOrganizationSheet({required this.onCreate});

  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)
      onCreate;

  @override
  State<_CreateOrganizationSheet> createState() =>
      _CreateOrganizationSheetState();
}

class _CreateOrganizationSheetState extends State<_CreateOrganizationSheet> {
  late final TextEditingController _name;
  late final TextEditingController _slug;
  late final TextEditingController _adminName;
  late final TextEditingController _adminUserId;
  late final TextEditingController _adminPassword;
  bool _saving = false;
  bool _slugTouched = false;
  String? _nameError;
  String? _slugError;
  String? _adminNameError;
  String? _adminUserIdError;
  String? _adminPasswordError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _slug = TextEditingController();
    _adminName = TextEditingController();
    _adminUserId = TextEditingController();
    _adminPassword = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _adminName.dispose();
    _adminUserId.dispose();
    _adminPassword.dispose();
    super.dispose();
  }

  String _slugFromName(String name) {
    return name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  void _onCompanyNameChanged(String value) {
    if (_slugTouched) return;
    final generated = _slugFromName(value);
    if (generated == _slug.text) return;
    _slug.value = _slug.value.copyWith(
      text: generated,
      selection: TextSelection.collapsed(offset: generated.length),
    );
  }

  void _normalizeSlug(String value) {
    _slugTouched = true;
    final normalized =
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-');
    if (normalized == _slug.text) return;
    _slug.value = _slug.value.copyWith(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  bool _validate() {
    final name = _name.text.trim();
    final slug = _slug.text.trim();
    final adminName = _adminName.text.trim();
    final adminUserId = _adminUserId.text.trim();
    final password = _adminPassword.text;

    setState(() {
      _nameError = name.isEmpty ? 'Enter company name' : null;
      _slugError = slug.isEmpty
          ? 'Enter organisation ID (used at login)'
          : slug.length < 2
              ? 'At least 2 characters'
              : null;
      _adminNameError =
          adminName.isEmpty ? 'Enter admin full name' : null;
      _adminUserIdError =
          adminUserId.isEmpty ? 'Enter admin user ID' : null;
      _adminPasswordError = password.length < 8
          ? 'At least 8 characters (currently ${password.length})'
          : null;
    });

    return _nameError == null &&
        _slugError == null &&
        _adminNameError == null &&
        _adminUserIdError == null &&
        _adminPasswordError == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() => _saving = true);
    try {
      final result = await widget.onCreate({
        'name': _name.text.trim(),
        'slug': _slug.text.trim(),
        'adminName': _adminName.text.trim(),
        'adminUserId': _adminUserId.text.trim(),
        'adminPassword': _adminPassword.text,
      });
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      bestieToast(
        context,
        'Could not create organisation',
        body: formatApiError(e),
        kind: BestieToastKind.error,
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'New organisation',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Creates an isolated workspace with its own admin login.',
              style: TextStyle(color: c.textMuted, height: 1.35),
            ),
            const SizedBox(height: 16),
            BestieTextField(
              label: 'Company name',
              controller: _name,
              icon: Icons.business_rounded,
              errorText: _nameError,
              onChanged: _onCompanyNameChanged,
            ),
            const SizedBox(height: 12),
            BestieTextField(
              label: 'Organisation ID (login slug)',
              controller: _slug,
              icon: Icons.tag_rounded,
              hint: 'e.g. digital-links',
              errorText: _slugError,
              onChanged: _normalizeSlug,
            ),
            const SizedBox(height: 12),
            BestieTextField(
              label: 'Admin full name',
              controller: _adminName,
              icon: Icons.person_outline,
              errorText: _adminNameError,
            ),
            const SizedBox(height: 12),
            BestieTextField(
              label: 'Admin user ID',
              controller: _adminUserId,
              icon: Icons.badge_outlined,
              errorText: _adminUserIdError,
            ),
            const SizedBox(height: 12),
            BestieTextField(
              label: 'Admin password',
              controller: _adminPassword,
              icon: Icons.lock_outline,
              obscure: true,
              errorText: _adminPasswordError,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: Text(_saving ? 'Creating…' : 'Create organisation'),
            ),
          ],
        ),
      ),
    );
  }
}
