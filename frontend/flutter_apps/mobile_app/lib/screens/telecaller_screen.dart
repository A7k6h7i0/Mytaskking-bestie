import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Telecaller leads — searchable, status-filtered list with a one-tap call.
class TelecallerScreen extends ConsumerStatefulWidget {
  const TelecallerScreen({super.key});
  @override
  ConsumerState<TelecallerScreen> createState() => _TelecallerScreenState();
}

class _TelecallerScreenState extends ConsumerState<TelecallerScreen> {
  final _search = TextEditingController();
  String? _status;
  Timer? _debounce;
  List<Map<String, dynamic>> _leads = const [];
  bool _loading = true;
  String? _error;

  static const _statuses = ['ALL', 'NEW', 'CONTACTED', 'INTERESTED', 'FOLLOWUP', 'WON', 'LOST'];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _fetch);
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await ref.read(apiProvider).listLeads(
        q: _search.text.isEmpty ? null : _search.text,
        status: _status == null || _status == 'ALL' ? null : _status,
      );
      if (!mounted) return;
      setState(() { _leads = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = formatApiError(e); _loading = false; });
    }
  }

  Future<void> _call(String leadId) async {
    try {
      await ref.read(apiProvider).callLead(leadId);
      if (mounted) bestieToast(context, 'Calling…', kind: BestieToastKind.info);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not call',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Telecaller'),
        actions: [
          IconButton(
            tooltip: 'Add lead',
            icon: const Icon(Icons.add_rounded),
            onPressed: _showCreateLeadSheet,
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onQuery,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, color: c.textMuted, size: 18),
              hintText: 'Find a lead',
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _statuses.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) {
              final s = _statuses[i];
              final active = (s == 'ALL' && _status == null) || s == _status;
              return ChoiceChip(
                label: Text(s),
                selected: active,
                onSelected: (_) {
                  setState(() => _status = s == 'ALL' ? null : s);
                  _fetch();
                },
                selectedColor: c.brandSoft,
                labelStyle: TextStyle(
                  color: active ? c.brandStrong : c.textSoft,
                  fontWeight: BestieTokens.fwSemibold,
                  fontSize: 11,
                ),
                shape: StadiumBorder(side: BorderSide(color: active ? c.brand : c.border)),
                backgroundColor: c.surface2,
              );
            },
          ),
        ),
        Expanded(
          child: _loading && _leads.isEmpty
              ? const Center(child: BestieSpinner())
              : _error != null
                  ? BestieEmptyState(
                      icon: Icons.error_outline_rounded, iconColor: c.danger,
                      title: 'Could not load leads', description: _error,
                    )
                  : _leads.isEmpty
                      ? const BestieEmptyState(
                          icon: Icons.headset_mic_outlined,
                          title: 'No leads match',
                          description: 'Try a different filter or search term.',
                        )
                      : RefreshIndicator(
                          onRefresh: _fetch,
                          child: ListView.separated(
                            itemCount: _leads.length,
                            separatorBuilder: (_, __) => Divider(height: 1, indent: 72, color: c.border),
                            itemBuilder: (ctx, i) {
                              final l = _leads[i];
                              final name = (l['name'] ?? '—').toString();
                              final company = (l['company'] ?? '').toString();
                              final phone = (l['phone'] ?? '').toString();
                              final st = (l['status'] ?? 'NEW').toString();
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: c.brandSoft,
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: TextStyle(color: c.brandStrong, fontWeight: BestieTokens.fwBold),
                                  ),
                                ),
                                title: Text(name,
                                    style: TextStyle(fontWeight: BestieTokens.fwSemibold, color: c.text)),
                                subtitle: Text(
                                  [company, phone].where((s) => s.isNotEmpty).join(' · '),
                                  style: TextStyle(color: c.textMuted, fontSize: 12),
                                ),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  BestieBadge(tone: _toneFor(st), child: Text(st)),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(Icons.call_rounded, color: c.success),
                                    tooltip: 'Call',
                                    onPressed: () => _call(l['id'] as String),
                                  ),
                                ]),
                                onTap: () => _showStatusSheet(l),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }

  BestieTone _toneFor(String status) => switch (status) {
        'WON'        => BestieTone.success,
        'CONTACTED'  => BestieTone.info,
        'INTERESTED' => BestieTone.warning,
        'FOLLOWUP'   => BestieTone.warning,
        'LOST'       => BestieTone.danger,
        _            => BestieTone.brand,
      };

  Future<void> _showCreateLeadSheet() async {
    final created = await bestieBottomSheet<bool>(
      context,
      title: 'Add lead',
      builder: (_) => _CreateLeadSheet(ref: ref),
    );
    if (created == true) {
      await _fetch();
    }
  }

  Future<void> _showStatusSheet(Map<String, dynamic> lead) async {
    final updated = await bestieBottomSheet<bool>(
      context,
      title: 'Change status',
      builder: (_) => _LeadStatusSheet(ref: ref, lead: lead),
    );
    if (updated == true) {
      await _fetch();
    }
  }
}

class _CreateLeadSheet extends StatefulWidget {
  const _CreateLeadSheet({required this.ref});

  final WidgetRef ref;

  @override
  State<_CreateLeadSheet> createState() => _CreateLeadSheetState();
}

class _CreateLeadSheetState extends State<_CreateLeadSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();
  final _email = TextEditingController();
  final _source = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _company.dispose();
    _email.dispose();
    _source.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      bestieToast(context, 'Name and phone are required',
          kind: BestieToastKind.warning);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.ref.read(apiProvider).createLead({
        'name': name,
        'phone': phone,
        if (_company.text.trim().isNotEmpty) 'company': _company.text.trim(),
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        'status': 'NEW',
        if (_source.text.trim().isNotEmpty) 'source': _source.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      });
      if (!mounted) return;
      bestieToast(context, 'Lead created', kind: BestieToastKind.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not create lead',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LeadField(controller: _name, label: 'Lead name *'),
              const SizedBox(height: 10),
              _LeadField(
                controller: _phone,
                label: 'Phone *',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              _LeadField(controller: _company, label: 'Company'),
              const SizedBox(height: 10),
              _LeadField(
                controller: _email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 10),
              _LeadField(controller: _source, label: 'Source'),
              const SizedBox(height: 10),
              _LeadField(controller: _notes, label: 'Notes', maxLines: 3),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
                label: Text(_saving ? 'Saving...' : 'Create lead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadStatusSheet extends StatefulWidget {
  const _LeadStatusSheet({required this.ref, required this.lead});

  final WidgetRef ref;
  final Map<String, dynamic> lead;

  @override
  State<_LeadStatusSheet> createState() => _LeadStatusSheetState();
}

class _LeadStatusSheetState extends State<_LeadStatusSheet> {
  static const _statuses = ['NEW', 'CONTACTED', 'INTERESTED', 'FOLLOWUP', 'WON', 'LOST'];

  late String _status = _statuses.contains(widget.lead['status'])
      ? widget.lead['status'] as String
      : 'NEW';
  bool _saving = false;

  Future<void> _save() async {
    final id = widget.lead['id'] as String?;
    if (id == null) return;

    setState(() => _saving = true);
    try {
      await widget.ref.read(apiProvider).updateLeadStatus(id, _status);
      if (!mounted) return;
      bestieToast(context, 'Lead status updated',
          kind: BestieToastKind.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not update status',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final name = (widget.lead['name'] ?? 'Lead').toString();
    final phone = (widget.lead['phone'] ?? '').toString();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              name,
              style: TextStyle(
                color: c.text,
                fontWeight: BestieTokens.fwBold,
                fontSize: 18,
              ),
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(phone, style: TextStyle(color: c.textMuted)),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _status,
              items: _statuses
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _status = value ?? 'NEW'),
              decoration: _fieldDecoration(c, 'Lead status'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Saving...' : 'Update status'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadField extends StatelessWidget {
  const _LeadField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: _fieldDecoration(c, label),
    );
  }
}

InputDecoration _fieldDecoration(BestieColors c, String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: c.surface2,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(BestieTokens.rSm),
      borderSide: BorderSide(color: c.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(BestieTokens.rSm),
      borderSide: BorderSide(color: c.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(BestieTokens.rSm),
      borderSide: BorderSide(color: c.brand),
    ),
  );
}
