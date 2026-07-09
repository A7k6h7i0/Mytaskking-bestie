import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Public organisation registration from the login screen.
/// Creates a PENDING tenant; platform super-admin must approve before login.
class OrganizationRegisterSheet extends StatefulWidget {
  const OrganizationRegisterSheet({
    super.key,
    required this.onRegister,
  });

  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)
      onRegister;

  @override
  State<OrganizationRegisterSheet> createState() =>
      _OrganizationRegisterSheetState();
}

class _OrganizationRegisterSheetState extends State<OrganizationRegisterSheet> {
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
      _adminNameError = adminName.isEmpty ? 'Enter admin full name' : null;
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
      final result = await widget.onRegister({
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
        'Could not submit registration',
        body: formatApiError(e),
        kind: BestieToastKind.error,
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final content = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Register organisation',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Creates your workspace and admin account. A platform administrator must approve before you can sign in.',
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
            child: Text(_saving ? 'Submitting…' : 'Submit registration'),
          ),
        ],
      ),
    );

    if (wide) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: content,
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: content,
    );
  }
}

Future<void> showOrganizationRegisterSheet(
  BuildContext context, {
  required Future<Map<String, dynamic>> Function(Map<String, dynamic> data)
      onRegister,
}) async {
  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => OrganizationRegisterSheet(onRegister: onRegister),
  );
  if (result == null || !context.mounted) return;
  final org = result['organisation'] as Map<String, dynamic>?;
  final slug = org?['slug']?.toString() ?? '';
  final adminUserId = result['adminUserId']?.toString() ?? '';
  bestieToast(
    context,
    'Registration submitted',
    body: slug.isEmpty
        ? 'Pending platform approval.'
        : 'Login after approval: $slug / $adminUserId',
    kind: BestieToastKind.success,
  );
}

Future<void> showOrganizationRegisterDialog(
  BuildContext context, {
  required Future<Map<String, dynamic>> Function(Map<String, dynamic> data)
      onRegister,
}) async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => OrganizationRegisterSheet(onRegister: onRegister),
  );
  if (result == null || !context.mounted) return;
  final org = result['organisation'] as Map<String, dynamic>?;
  final slug = org?['slug']?.toString() ?? '';
  final adminUserId = result['adminUserId']?.toString() ?? '';
  bestieToast(
    context,
    'Registration submitted',
    body: slug.isEmpty
        ? 'Pending platform approval.'
        : 'Login after approval: $slug / $adminUserId',
    kind: BestieToastKind.success,
  );
}
