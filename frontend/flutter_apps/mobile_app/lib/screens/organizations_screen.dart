import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

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
      final items = await ref.read(apiProvider).listTenants();
      if (!mounted) return;
      setState(() {
        _items = items.where((o) => (o['slug'] ?? '') != 'default').toList();
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

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Organisations'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Add organisation'),
      ),
      body: RefreshIndicator(
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
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final org = _items[i];
                          final status =
                              (org['status'] ?? 'ACTIVE').toString();
                          final active = status == 'ACTIVE';
                          return Container(
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
                                        color: active
                                            ? c.successSoft
                                            : c.warningSoft,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: active
                                              ? c.success
                                              : c.warning,
                                        ),
                                      ),
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
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => _setStatus(
                                      org['id'].toString(),
                                      active ? 'SUSPENDED' : 'ACTIVE',
                                    ),
                                    child: Text(
                                        active ? 'Suspend' : 'Activate'),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
