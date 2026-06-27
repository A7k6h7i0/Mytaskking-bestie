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
    final name = TextEditingController();
    final slug = TextEditingController();
    final adminName = TextEditingController();
    final adminUserId = TextEditingController();
    final adminPassword = TextEditingController();
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final c = BestieColors.of(ctx);
        return StatefulBuilder(
          builder: (context, setSheet) => Padding(
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
                  Text('New organisation',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: c.text)),
                  const SizedBox(height: 6),
                  Text(
                    'Creates an isolated workspace with its own admin login.',
                    style: TextStyle(color: c.textMuted, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  BestieTextField(
                    label: 'Company name',
                    controller: name,
                    icon: Icons.business_rounded,
                  ),
                  const SizedBox(height: 12),
                  BestieTextField(
                    label: 'Organisation ID (login slug)',
                    controller: slug,
                    icon: Icons.tag_rounded,
                    hint: 'e.g. digital-links',
                    onChanged: (v) {
                      final s = v
                          .toLowerCase()
                          .replaceAll(RegExp(r'[^a-z0-9-]'), '-');
                      if (s != slug.text) {
                        slug.value = slug.value.copyWith(
                          text: s,
                          selection: TextSelection.collapsed(offset: s.length),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  BestieTextField(
                    label: 'Admin full name',
                    controller: adminName,
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 12),
                  BestieTextField(
                    label: 'Admin user ID',
                    controller: adminUserId,
                    icon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 12),
                  BestieTextField(
                    label: 'Admin password',
                    controller: adminPassword,
                    icon: Icons.lock_outline,
                    obscure: true,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (name.text.trim().isEmpty ||
                                slug.text.trim().isEmpty ||
                                adminName.text.trim().isEmpty ||
                                adminUserId.text.trim().isEmpty ||
                                adminPassword.text.length < 8) {
                              bestieToast(
                                context,
                                'Fill all fields (password min 8 chars)',
                                kind: BestieToastKind.warning,
                              );
                              return;
                            }
                            setSheet(() => saving = true);
                            try {
                              final result =
                                  await ref.read(apiProvider).createTenant({
                                'name': name.text.trim(),
                                'slug': slug.text.trim(),
                                'adminName': adminName.text.trim(),
                                'adminUserId': adminUserId.text.trim(),
                                'adminPassword': adminPassword.text,
                              });
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              await _load();
                              if (!mounted) return;
                              final org = result['organisation']
                                  as Map<String, dynamic>?;
                              final admin =
                                  result['admin'] as Map<String, dynamic>?;
                              bestieToast(
                                this.context,
                                'Organisation created',
                                body:
                                    'Login: ${org?['slug']} / ${admin?['userId']}',
                                kind: BestieToastKind.success,
                              );
                            } catch (e) {
                              if (mounted) {
                                bestieToast(
                                  this.context,
                                  'Could not create organisation',
                                  body: formatApiError(e),
                                  kind: BestieToastKind.error,
                                );
                              }
                              setSheet(() => saving = false);
                            }
                          },
                    child: Text(saving ? 'Creating…' : 'Create organisation'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    name.dispose();
    slug.dispose();
    adminName.dispose();
    adminUserId.dispose();
    adminPassword.dispose();
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
