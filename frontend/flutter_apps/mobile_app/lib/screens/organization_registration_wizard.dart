import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

const _govtIdTypes = [
  ('AADHAAR', 'Aadhaar'),
  ('PAN', 'PAN'),
  ('VOTER_ID', 'Voter ID'),
  ('DRIVING_LICENSE', 'Driving License'),
];

typedef RegisterFn = Future<Map<String, dynamic>> Function(Map<String, dynamic>);
typedef ApiOps = ({
  Future<Map<String, dynamic>> Function({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) uploadFile,
});

class OrganizationRegistrationWizard extends StatefulWidget {
  const OrganizationRegistrationWizard({
    super.key,
    required this.onRegister,
    required this.api,
    this.fullScreen = false,
    this.onBackToLogin,
  });

  final RegisterFn onRegister;
  final ApiOps api;
  final bool fullScreen;
  final VoidCallback? onBackToLogin;

  @override
  State<OrganizationRegistrationWizard> createState() =>
      _OrganizationRegistrationWizardState();
}

class _OrganizationRegistrationWizardState
    extends State<OrganizationRegistrationWizard> {
  int _step = 0;
  bool _busy = false;
  bool _submitted = false;
  int? _uploadingIdSlot;
  String? _id1Url;
  String? _id2Url;
  String? _id1Fingerprint;
  String? _id2Fingerprint;

  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _adminName = TextEditingController();
  final _adminUserId = TextEditingController();
  final _adminPassword = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPhone = TextEditingController();
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

  String _mimeForImage(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  /// Detect re-using the exact same picked file for both ID slots.
  String _fingerprintFile(PlatformFile file) {
    final bytes = file.bytes!;
    final sample = bytes.length <= 8192
        ? bytes
        : Uint8List.fromList([
            ...bytes.sublist(0, 4096),
            ...bytes.sublist(bytes.length - 4096),
          ]);
    return '${file.name.toLowerCase()}|${bytes.length}|${Object.hashAll(sample)}';
  }

  String? _otherFingerprint(int slot) =>
      slot == 1 ? _id2Fingerprint : _id1Fingerprint;

  Future<void> _pickIdImageForSlot(int slot) async {
    if (_uploadingIdSlot != null || _busy) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null ||
          result.files.isEmpty ||
          result.files.first.bytes == null) {
        return;
      }
      final file = result.files.first;
      final fingerprint = _fingerprintFile(file);
      final otherFp = _otherFingerprint(slot);
      if (otherFp != null && otherFp == fingerprint) {
        if (!mounted) return;
        bestieToast(
          context,
          'Use a different ID image',
          body:
              'Government ID 1 and ID 2 must be photos of two different documents.',
          kind: BestieToastKind.warning,
        );
        return;
      }

      setState(() => _uploadingIdSlot = slot);
      final asset = await widget.api.uploadFile(
        bytes: file.bytes!,
        filename: file.name,
        mimeType: _mimeForImage(file.extension),
      );
      final url = asset['url']?.toString();
      if (url == null || url.isEmpty) {
        throw 'Upload returned no image URL';
      }
      if (!mounted) return;
      setState(() {
        if (slot == 1) {
          _id1Url = url;
          _id1Fingerprint = fingerprint;
        } else {
          _id2Url = url;
          _id2Fingerprint = fingerprint;
        }
      });
      bestieToast(context, 'ID image uploaded',
          kind: BestieToastKind.success);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not upload ID image',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _uploadingIdSlot = null);
    }
  }

  Future<void> _submit() async {
    if (_govtId1Type == _govtId2Type) {
      bestieToast(context, 'Select two different ID types',
          kind: BestieToastKind.warning);
      return;
    }
    if (_govtId1Number.text.trim().length < 4 ||
        _govtId2Number.text.trim().length < 4) {
      bestieToast(context, 'Enter both government ID numbers',
          kind: BestieToastKind.warning);
      return;
    }
    if (_id1Url == null || _id2Url == null) {
      bestieToast(context, 'Upload both ID images',
          kind: BestieToastKind.warning);
      return;
    }
    if (_id1Fingerprint != null &&
        _id2Fingerprint != null &&
        _id1Fingerprint == _id2Fingerprint) {
      bestieToast(
        context,
        'Use two different ID photos',
        body: 'Each government ID must have its own image.',
        kind: BestieToastKind.warning,
      );
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
        'govtId1Type': _govtId1Type,
        'govtId1Number': _govtId1Number.text.trim(),
        'govtId1ImageUrl': _id1Url,
        'govtId2Type': _govtId2Type,
        'govtId2Number': _govtId2Number.text.trim(),
        'govtId2ImageUrl': _id2Url,
      });
      if (!mounted) return;
      if (widget.fullScreen) {
        setState(() => _submitted = true);
      } else {
        Navigator.pop(context, result);
      }
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
    final content = _submitted ? _successView(c) : _formView(c);
    if (!widget.fullScreen) {
      return content;
    }
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: const Text('Register organisation'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
        leading: _submitted
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBackToLogin,
              ),
      ),
      body: SafeArea(child: content),
    );
  }

  Widget _successView(BestieColors c) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.check_circle_rounded, size: 72, color: c.success),
          const SizedBox(height: 20),
          Text(
            'Registration submitted',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Our sales team will review your organisation. After approval you will get a 7-day free trial.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textMuted, height: 1.45, fontSize: 15),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: widget.onBackToLogin,
            style: FilledButton.styleFrom(backgroundColor: c.brand),
            child: const Text('Back to login'),
          ),
        ],
      ),
    );
  }

  Widget _formView(BestieColors c) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: widget.fullScreen ? 8 : 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.fullScreen)
              Text('Register organisation',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: c.text)),
            if (!widget.fullScreen) const SizedBox(height: 4),
            Text('Step ${_step + 1} of 2',
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
              _field(_adminEmail, 'Admin email'),
              _field(_adminPhone, 'Phone number', keyboard: TextInputType.phone),
            ],
            if (_step == 1) ...[
              _idBlock(
                c,
                label: 'Government ID 1',
                type: _govtId1Type,
                onType: (v) => setState(() => _govtId1Type = v),
                number: _govtId1Number,
                imageUrl: _id1Url,
                uploading: _uploadingIdSlot == 1,
                disabled: _uploadingIdSlot != null || _busy,
                onPick: () => _pickIdImageForSlot(1),
              ),
              const SizedBox(height: 12),
              _idBlock(
                c,
                label: 'Government ID 2',
                type: _govtId2Type,
                onType: (v) => setState(() => _govtId2Type = v),
                number: _govtId2Number,
                imageUrl: _id2Url,
                uploading: _uploadingIdSlot == 2,
                disabled: _uploadingIdSlot != null || _busy,
                onPick: () => _pickIdImageForSlot(2),
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
                  onPressed: (_busy || _uploadingIdSlot != null) ? null : _onNext,
                  style: FilledButton.styleFrom(backgroundColor: c.brand),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_step == 1 ? 'Submit' : 'Next'),
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
      final email = _adminEmail.text.trim();
      final phone = _adminPhone.text.trim();
      if (_name.text.trim().isEmpty ||
          _slug.text.trim().length < 2 ||
          _adminPassword.text.length < 8 ||
          !email.contains('@') ||
          phone.length < 10) {
        bestieToast(context, 'Fill all fields (valid email & 10-digit phone)',
            kind: BestieToastKind.warning);
        return;
      }
      setState(() => _step = 1);
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
    required bool uploading,
    required bool disabled,
    required VoidCallback onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
        DropdownButtonFormField<String>(
          key: ValueKey(type),
          initialValue: type,
          items: [
            for (final t in _govtIdTypes)
              DropdownMenuItem(value: t.$1, child: Text(t.$2)),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) onType(v);
                },
        ),
        _field(number, 'ID number'),
        OutlinedButton.icon(
          onPressed: disabled ? null : onPick,
          icon: uploading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.brand,
                  ),
                )
              : Icon(
                  imageUrl == null
                      ? Icons.upload_file_outlined
                      : Icons.check_circle_outline,
                  color: imageUrl == null ? null : c.success,
                ),
          label: Text(
            uploading
                ? 'Uploading…'
                : imageUrl == null
                    ? 'Upload ID image'
                    : 'ID image uploaded — tap to replace',
          ),
        ),
      ],
    );
  }
}
