import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state.dart';

const _paymentBaseUrl = String.fromEnvironment(
  'PAYMENT_URL',
  defaultValue: 'https://payment.mytaskking.com',
);

const _govtIdTypes = [
  ('AADHAAR', 'Aadhaar'),
  ('PAN', 'PAN'),
  ('VOTER_ID', 'Voter ID'),
  ('DRIVING_LICENSE', 'Driving License'),
];

typedef RegisterFn = Future<Map<String, dynamic>> Function(Map<String, dynamic>);
typedef ApiOps = ({
  Future<Map<String, dynamic>> Function({required String email, required String phone}) sendOtp,
  Future<Map<String, dynamic>> Function({required String email, required String code}) verifyOtp,
  Future<Map<String, dynamic>> Function({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) uploadFile,
  Future<void> Function(String tenantId) requestTrial,
  Future<List<Map<String, dynamic>>> Function() fetchPlans,
});

class OrganizationRegistrationWizard extends StatefulWidget {
  const OrganizationRegistrationWizard({
    super.key,
    required this.onRegister,
    required this.api,
  });

  final RegisterFn onRegister;
  final ApiOps api;

  @override
  State<OrganizationRegistrationWizard> createState() =>
      _OrganizationRegistrationWizardState();
}

class _OrganizationRegistrationWizardState
    extends State<OrganizationRegistrationWizard> {
  int _step = 0;
  bool _busy = false;
  String? _otpToken;
  String? _id1Url;
  String? _id2Url;

  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _adminName = TextEditingController();
  final _adminUserId = TextEditingController();
  final _adminPassword = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPhone = TextEditingController();
  final _otpCode = TextEditingController();
  final _govtId1Number = TextEditingController();
  final _govtId2Number = TextEditingController();
  String _govtId1Type = 'AADHAAR';
  String _govtId2Type = 'PAN';
  bool _slugTouched = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _slug,
      _adminName,
      _adminUserId,
      _adminPassword,
      _adminEmail,
      _adminPhone,
      _otpCode,
      _govtId1Number,
      _govtId2Number,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _slugFromName(String name) => name
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  Future<void> _sendOtp() async {
    final email = _adminEmail.text.trim();
    final phone = _adminPhone.text.trim();
    if (!email.contains('@') || phone.length < 10) {
      bestieToast(context, 'Enter valid email and phone',
          kind: BestieToastKind.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.sendOtp(email: email, phone: phone);
      if (mounted) {
        bestieToast(context, 'OTP sent to your email',
            kind: BestieToastKind.success);
        setState(() => _step = 2);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not send OTP',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    setState(() => _busy = true);
    try {
      final res = await widget.api.verifyOtp(
        email: _adminEmail.text.trim(),
        code: _otpCode.text.trim(),
      );
      _otpToken = res['verificationToken']?.toString();
      if (mounted) setState(() => _step = 3);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Invalid OTP',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickIdImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.first.bytes == null) {
      return null;
    }
    final file = result.files.first;
    final asset = await widget.api.uploadFile(
      bytes: file.bytes!,
      filename: file.name,
      mimeType: 'image/${file.extension ?? 'jpeg'}',
    );
    return asset['url']?.toString();
  }

  Future<void> _submit() async {
    if (_otpToken == null) return;
    if (_govtId1Type == _govtId2Type) {
      bestieToast(context, 'Select two different ID types',
          kind: BestieToastKind.warning);
      return;
    }
    if (_id1Url == null || _id2Url == null) {
      bestieToast(context, 'Upload both ID images',
          kind: BestieToastKind.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.onRegister({
        'name': _name.text.trim(),
        'slug': _slug.text.trim(),
        'adminName': _adminName.text.trim(),
        'adminUserId': _adminUserId.text.trim(),
        'adminPassword': _adminPassword.text,
        'adminEmail': _adminEmail.text.trim(),
        'adminPhone': _adminPhone.text.trim(),
        'otpVerificationToken': _otpToken,
        'govtId1Type': _govtId1Type,
        'govtId1Number': _govtId1Number.text.trim(),
        'govtId1ImageUrl': _id1Url,
        'govtId2Type': _govtId2Type,
        'govtId2Number': _govtId2Number.text.trim(),
        'govtId2ImageUrl': _id2Url,
      });
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Registration failed',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
            Text('Register organisation',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: c.text)),
            const SizedBox(height: 4),
            Text('Step ${_step + 1} of 4',
                style: TextStyle(color: c.textMuted)),
            const SizedBox(height: 16),
            if (_step == 0) ...[
              _field(_name, 'Company name', onChanged: (v) {
                if (!_slugTouched) {
                  _slug.text = _slugFromName(v);
                }
              }),
              _field(_slug, 'Organisation ID (login slug)', onChanged: (_) {
                _slugTouched = true;
              }),
              _field(_adminName, 'Admin full name'),
              _field(_adminUserId, 'Admin user ID'),
              _field(_adminPassword, 'Admin password', obscure: true),
            ],
            if (_step == 1) ...[
              _field(_adminEmail, 'Admin email'),
              _field(_adminPhone, 'Phone number'),
            ],
            if (_step == 2) ...[
              Text('Enter the 6-digit OTP sent to ${_adminEmail.text.trim()}',
                  style: TextStyle(color: c.textMuted)),
              const SizedBox(height: 8),
              _field(_otpCode, 'OTP code', keyboard: TextInputType.number),
            ],
            if (_step == 3) ...[
              _idBlock(
                c,
                label: 'Government ID 1',
                type: _govtId1Type,
                onType: (v) => setState(() => _govtId1Type = v),
                number: _govtId1Number,
                imageUrl: _id1Url,
                onPick: () async {
                  final url = await _pickIdImage();
                  if (url != null) setState(() => _id1Url = url);
                },
              ),
              const SizedBox(height: 12),
              _idBlock(
                c,
                label: 'Government ID 2',
                type: _govtId2Type,
                onType: (v) => setState(() => _govtId2Type = v),
                number: _govtId2Number,
                imageUrl: _id2Url,
                onPick: () async {
                  final url = await _pickIdImage();
                  if (url != null) setState(() => _id2Url = url);
                },
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                if (_step > 0)
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _step -= 1),
                    child: const Text('Back'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _onNext,
                  style: FilledButton.styleFrom(backgroundColor: c.brand),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_step == 3 ? 'Submit' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onNext() async {
    if (_step == 0) {
      if (_name.text.trim().isEmpty ||
          _slug.text.trim().length < 2 ||
          _adminPassword.text.length < 8) {
        bestieToast(context, 'Fill all organisation fields',
            kind: BestieToastKind.warning);
        return;
      }
      setState(() => _step = 1);
      return;
    }
    if (_step == 1) {
      await _sendOtp();
      return;
    }
    if (_step == 2) {
      await _verifyOtp();
      return;
    }
    await _submit();
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool obscure = false,
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _idBlock(
    BestieColors c, {
    required String label,
    required String type,
    required ValueChanged<String> onType,
    required TextEditingController number,
    required String? imageUrl,
    required VoidCallback onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
        DropdownButtonFormField<String>(
          value: type,
          items: [
            for (final t in _govtIdTypes)
              DropdownMenuItem(value: t.$1, child: Text(t.$2)),
          ],
          onChanged: (v) {
            if (v != null) onType(v);
          },
        ),
        _field(number, 'ID number'),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(imageUrl == null ? 'Upload ID image' : 'ID image uploaded'),
        ),
      ],
    );
  }
}

Future<void> showOrgRegistrationFlow(
  BuildContext context, {
  required RegisterFn onRegister,
  required ApiOps api,
}) async {
  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => OrganizationRegistrationWizard(
      onRegister: onRegister,
      api: api,
    ),
  );
  if (result == null || !context.mounted) return;

  final tenantId = result['tenantId']?.toString() ??
      (result['organisation'] as Map?)?['id']?.toString();
  if (tenantId == null) return;

  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Choose subscription'),
      content: const Text(
        'Start with a 7-day free trial (activates after sales approval) or pay monthly now.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'trial'),
          child: const Text('7-day free trial'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'pay'),
          child: const Text('Pay monthly'),
        ),
      ],
    ),
  );
  if (!context.mounted || choice == null) return;

  if (choice == 'trial') {
    try {
      await api.requestTrial(tenantId);
      bestieToast(context, 'Trial requested',
          body: 'Return after sales team approval.',
          kind: BestieToastKind.success);
    } catch (e) {
      bestieToast(context, 'Could not request trial',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
    return;
  }

  List<Map<String, dynamic>> plans;
  try {
    plans = await api.fetchPlans();
  } catch (e) {
    if (context.mounted) {
      bestieToast(context, 'Could not load plans',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
    return;
  }
  if (plans.isEmpty) {
    if (context.mounted) {
      bestieToast(context, 'No plans available',
          body: 'Ask super admin to add subscription plans.',
          kind: BestieToastKind.error);
    }
    return;
  }

  final planId = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Choose a plan'),
      children: plans.map((plan) {
        final id = plan['id']?.toString() ?? '';
        final label = plan['label']?.toString() ?? 'Plan';
        final inr = plan['amountInr'] ??
            (((plan['amountPaise'] as num?) ?? 0) / 100);
        return SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, id),
          child: Text('$label — ₹$inr'),
        );
      }).toList(),
    ),
  );
  if (!context.mounted || planId == null || planId.isEmpty) return;

  final uri = Uri.parse(
    '$_paymentBaseUrl/checkout?tenantId=$tenantId&plan=$planId',
  );
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (context.mounted) {
      bestieToast(context, 'Complete payment in browser',
          body: 'Then return here and wait for approval.',
          kind: BestieToastKind.info);
    }
  }
}
