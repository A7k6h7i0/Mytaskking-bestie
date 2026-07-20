import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Client directory — external users who have at least one client channel.
/// Tapping a client opens (or creates) the client channel with them.
class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});
  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch('');
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await ref.read(apiProvider).listClients(q: q.isEmpty ? null : q);
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = formatApiError(e); _loading = false; });
    }
  }

  Future<void> _openChannel(Map<String, dynamic> client) async {
    final clientId = client['id']?.toString();
    if (clientId == null) return;
    try {
      final cached = ref.read(channelsProvider).asData?.value ?? const [];
      for (final c in cached) {
        final kind = (c['kind'] ?? '').toString();
        if (kind != 'CLIENT' && c['isClientChannel'] != true) continue;
        final members =
            (c['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final hasClient = members.any((m) {
          final uid = m['userId']?.toString() ?? m['user']?['id']?.toString();
          return uid == clientId;
        });
        if (hasClient) {
          if (mounted) context.push('/chat/${c['id']}');
          return;
        }
      }

      final ch = await ref.read(apiProvider).createChannel(
        kind: 'CLIENT',
        name: client['name']?.toString() ??
            client['clientCompany']?.toString() ??
            'Client',
        memberIds: [clientId],
      );
      ref.invalidate(channelsProvider);
      if (mounted) context.push('/chat/${ch['id']}');
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not open channel',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _deleteClient(Map<String, dynamic> client) async {
    final id = client['id']?.toString();
    final name = (client['name'] ?? 'Client').toString();
    if (id == null) return;
    final ok = await bestieConfirm(
      context,
      title: 'Delete client?',
      description:
          'Remove $name and their access. Their chat history may remain in channels.',
      confirmLabel: 'Delete',
      dangerous: true,
    );
    if (!ok) return;
    try {
      await ref.read(apiProvider).deleteClient(id);
      ref.invalidate(channelsProvider);
      await _fetch(_search.text);
      if (mounted) {
        bestieToast(context, 'Client deleted', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not delete client',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final user = ref.watch(authStoreProvider).user;
    final canCreate = user?.role == 'ADMIN' || user?.role == 'SUPER_ADMIN';

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Clients'),
        actions: [
          if (canCreate)
            IconButton(
              tooltip: 'Create client',
              icon: const Icon(Icons.add_rounded),
              onPressed: _showCreateClientSheet,
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
              hintText: 'Find a client by name or company',
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
        Expanded(
          child: _loading && _items.isEmpty
              ? const Center(child: BestieSpinner())
              : _error != null
                  ? BestieEmptyState(
                      icon: Icons.error_outline_rounded, iconColor: c.danger,
                      title: 'Could not load clients', description: _error,
                    )
                  : _items.isEmpty
                      ? const BestieEmptyState(
                          icon: Icons.business_center_outlined,
                          title: 'No clients yet',
                          description: 'Clients will appear here once admins onboard them.',
                        )
                      : RefreshIndicator(
                          onRefresh: () => _fetch(_search.text),
                          child: ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => Divider(height: 1, indent: 72, color: c.border),
                            itemBuilder: (ctx, i) {
                              final u = _items[i];
                              final name = (u['name'] ?? '—').toString();
                              final company = (u['clientCompany'] ?? '').toString();
                              return ListTile(
                                leading: BestieAvatar(
                                  name: name,
                                  imageUrl: u['avatarUrl']?.toString(),
                                  isClient: true,
                                  size: 40,
                                ),
                                title: BestieUserName(name: name, isClient: true,
                                    style: const TextStyle(fontWeight: BestieTokens.fwSemibold)),
                                subtitle: Text(company.isEmpty ? 'Client' : company,
                                    style: TextStyle(color: c.textMuted, fontSize: 12)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.business_center_outlined,
                                          color: c.client),
                                      tooltip: 'Open client channel',
                                      onPressed: () => _openChannel(u),
                                    ),
                                    if (canCreate)
                                      IconButton(
                                        icon: Icon(Icons.delete_outline_rounded,
                                            color: c.danger),
                                        tooltip: 'Delete client',
                                        onPressed: () => _deleteClient(u),
                                      ),
                                  ],
                                ),
                                onTap: () => _openChannel(u),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }

  Future<void> _showCreateClientSheet() async {
    final created = await bestieBottomSheet<bool>(
      context,
      title: 'Create client',
      builder: (_) => _CreateClientSheet(ref: ref),
    );
    if (created == true) {
      await _fetch(_search.text);
    }
  }
}

class _CreateClientSheet extends StatefulWidget {
  const _CreateClientSheet({required this.ref});

  final WidgetRef ref;

  @override
  State<_CreateClientSheet> createState() => _CreateClientSheetState();
}

class _CreateClientSheetState extends State<_CreateClientSheet> {
  final _userId = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  DateTime? _accessEndsAt;
  bool _saving = false;

  @override
  void dispose() {
    _userId.dispose();
    _password.dispose();
    _name.dispose();
    _company.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickAccessEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _accessEndsAt ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _accessEndsAt = picked);
    }
  }

  Future<void> _save() async {
    final userId = _userId.text.trim();
    final password = _password.text;
    final name = _name.text.trim();
    if (userId.length < 2 || name.isEmpty || password.length < 8) {
      bestieToast(context, 'Fill required fields',
          body: 'User ID, name, and password min 8 chars are required.',
          kind: BestieToastKind.warning);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.ref.read(apiProvider).createClient({
        'userId': userId,
        'password': password,
        'name': name,
        if (_company.text.trim().isNotEmpty)
          'clientCompany': _company.text.trim(),
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
        if (_accessEndsAt != null)
          'accessEndsAt': _accessEndsAt!.toIso8601String(),
      });
      if (!mounted) return;
      bestieToast(context, 'Client created', kind: BestieToastKind.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not create client',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
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
              _ClientField(controller: _userId, label: 'User ID *'),
              const SizedBox(height: 10),
              _ClientField(
                controller: _password,
                label: 'Password *',
                obscureText: true,
              ),
              const SizedBox(height: 10),
              _ClientField(controller: _name, label: 'Client name *'),
              const SizedBox(height: 10),
              _ClientField(controller: _company, label: 'Client company'),
              const SizedBox(height: 10),
              _ClientField(
                controller: _email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 10),
              _ClientField(
                controller: _phone,
                label: 'Phone',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickAccessEndDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(_accessEndsAt == null
                    ? 'Set access end date'
                    : 'Access ends ${_formatDate(_accessEndsAt!)}'),
              ),
              if (_accessEndsAt != null)
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _accessEndsAt = null),
                  child: Text('Remove expiry',
                      style: TextStyle(color: c.textMuted)),
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
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: Text(_saving ? 'Saving...' : 'Create client'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientField extends StatelessWidget {
  const _ClientField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
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
      ),
    );
  }
}
