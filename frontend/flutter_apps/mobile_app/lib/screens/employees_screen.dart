import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Employee directory — searchable list of teammates with a tap-to-DM action.
/// Backed by `GET /employees?q=`.
class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});
  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  static const _roles = [
    'ADMIN',
    'MANAGER',
    'PROJECT_COORDINATOR_MANAGER',
    'EMPLOYEE',
    'TELECALLER',
  ];
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
      final items = await ref.read(apiProvider).listEmployees(q: q.isEmpty ? null : q);
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = formatApiError(e); _loading = false; });
    }
  }

  Future<void> _openDm(Map<String, dynamic> user) async {
    try {
      final ch = await ref.read(apiProvider).createChannel(
        kind: 'DM',
        memberIds: [user['id'] as String],
      );
      ref.invalidate(channelsProvider);
      if (mounted) context.push('/chat/${ch['id']}');
    } catch (e) {
      if (mounted) bestieToast(context, 'Could not open chat',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  Future<void> _openEmployeeForm([Map<String, dynamic>? employee]) async {
    final editing = employee != null;
    final userId = TextEditingController(text: employee?['userId']?.toString());
    final password = TextEditingController();
    final name = TextEditingController(text: employee?['name']?.toString());
    final customTitle =
        TextEditingController(text: employee?['customTitle']?.toString());
    final email = TextEditingController(text: employee?['email']?.toString());
    final phone = TextEditingController(text: employee?['phone']?.toString());
    final avatarUrl =
        TextEditingController(text: employee?['avatarUrl']?.toString());
    final departmentId =
        TextEditingController(text: employee?['departmentId']?.toString());
    final supervisorIds = ((employee?['supervisors'] as List?) ?? const [])
        .map((entry) => (entry as Map?)?['supervisorId']?.toString())
        .whereType<String>()
        .toSet();
    var role = employee?['role']?.toString() ?? 'EMPLOYEE';
    var status = employee?['status']?.toString() ?? 'ACTIVE';
    var saving = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          InputDecoration decoration(String label, {String? hint}) =>
              InputDecoration(labelText: label, hintText: hint);

          Future<void> submit() async {
            if (userId.text.trim().length < 2 ||
                name.text.trim().isEmpty ||
                (!editing && password.text.length < 8) ||
                (editing &&
                    password.text.isNotEmpty &&
                    password.text.length < 8)) {
              setLocal(() => error =
                  'Enter a name, User ID, and a password of at least 8 characters.');
              return;
            }
            setLocal(() {
              saving = true;
              error = null;
            });
            String? optional(TextEditingController controller) {
              final value = controller.text.trim();
              return value.isEmpty ? null : value;
            }
            final data = <String, dynamic>{
              'userId': userId.text.trim(),
              'name': name.text.trim(),
              'role': role,
              'status': status,
              'customTitle': optional(customTitle),
              'email': optional(email),
              'phone': optional(phone),
              'avatarUrl': optional(avatarUrl),
              'departmentId': optional(departmentId),
              'supervisorIds': supervisorIds.toList(),
              if (password.text.isNotEmpty) 'password': password.text,
            };
            try {
              if (editing) {
                await ref
                    .read(apiProvider)
                    .updateEmployee(employee['id'] as String, data);
              } else {
                data.remove('status');
                await ref.read(apiProvider).createEmployee(data);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _fetch(_search.text);
              if (mounted) {
                bestieToast(
                  context,
                  editing ? 'Employee updated' : 'Employee added',
                  kind: BestieToastKind.success,
                );
              }
            } catch (e) {
              if (ctx.mounted) {
                setLocal(() {
                  saving = false;
                  error = formatApiError(e);
                });
              }
            }
          }

          return AlertDialog(
            title: Text(editing ? 'Edit employee' : 'Add employee'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: userId,
                    decoration: decoration('User ID'),
                    textInputAction: TextInputAction.next,
                  ),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: decoration(
                      editing ? 'New password (optional)' : 'Password',
                      hint: editing ? 'Leave blank to keep current password' : null,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  TextField(
                    controller: name,
                    decoration: decoration('Full name'),
                    textInputAction: TextInputAction.next,
                  ),
                  TextField(
                    controller: customTitle,
                    decoration: decoration('Job title'),
                    textInputAction: TextInputAction.next,
                  ),
                  TextField(
                    controller: email,
                    decoration: decoration('Email'),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  TextField(
                    controller: phone,
                    decoration: decoration('Phone'),
                    keyboardType: TextInputType.phone,
                  ),
                  TextField(
                    controller: avatarUrl,
                    decoration: decoration('Avatar URL'),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                  ),
                  TextField(
                    controller: departmentId,
                    decoration: decoration('Department ID'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: decoration('Role'),
                    items: _roles
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.replaceAll('_', ' ')),
                            ))
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) => setLocal(() => role = value ?? role),
                  ),
                  if (editing) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: decoration('Status'),
                      items: const [
                        DropdownMenuItem(value: 'ACTIVE', child: Text('ACTIVE')),
                        DropdownMenuItem(
                            value: 'SUSPENDED', child: Text('SUSPENDED')),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setLocal(() => status = value ?? status),
                    ),
                  ],
                  if (_items
                      .where((item) => item['id'] != employee?['id'])
                      .isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Reports to',
                          style: TextStyle(
                              color: BestieColors.of(ctx).textMuted,
                              fontWeight: BestieTokens.fwSemibold)),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final candidate in _items.where(
                              (item) => item['id'] != employee?['id']))
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value:
                                  supervisorIds.contains(candidate['id']?.toString()),
                              title: Text(
                                  (candidate['name'] ?? candidate['userId'])
                                      .toString()),
                              onChanged: saving
                                  ? null
                                  : (checked) => setLocal(() {
                                        final id = candidate['id'].toString();
                                        checked == true
                                            ? supervisorIds.add(id)
                                            : supervisorIds.remove(id);
                                      }),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: TextStyle(
                            color: BestieColors.of(ctx).danger, fontSize: 12)),
                  ],
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving ? null : submit,
                child: Text(saving ? 'Saving…' : (editing ? 'Save' : 'Add')),
              ),
            ],
          );
        },
      ),
    );

    userId.dispose();
    password.dispose();
    name.dispose();
    customTitle.dispose();
    email.dispose();
    phone.dispose();
    avatarUrl.dispose();
    departmentId.dispose();
  }

  Future<void> _deleteEmployee(Map<String, dynamic> employee) async {
    final name = (employee['name'] ?? 'this employee').toString();
    final ok = await bestieConfirm(
      context,
      title: 'Delete $name?',
      description:
          'This permanently removes the employee account and cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await ref.read(apiProvider).deleteEmployee(employee['id'] as String);
      await _fetch(_search.text);
      if (mounted) {
        bestieToast(context, 'Employee deleted', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not delete employee',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final me = ref.watch(authStoreProvider).user;
    final canManage = me?.role == 'SUPER_ADMIN';
    final list = _items.where((u) => u['id'] != me?.id).toList();

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Employees'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_rounded),
              tooltip: 'Add employee',
              onPressed: () => _openEmployeeForm(),
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
              hintText: 'Find a teammate',
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
          child: _loading && list.isEmpty
              ? const Center(child: BestieSpinner())
              : _error != null
                  ? BestieEmptyState(
                      icon: Icons.error_outline_rounded, iconColor: c.danger,
                      title: 'Could not load teammates', description: _error,
                    )
                  : list.isEmpty
                      ? const BestieEmptyState(
                          icon: Icons.person_search_rounded,
                          title: 'No teammates match',
                          description: 'Try a different search term.',
                        )
                      : RefreshIndicator(
                          onRefresh: () => _fetch(_search.text),
                          child: ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => Divider(height: 1, indent: 72, color: c.border),
                            itemBuilder: (ctx, i) {
                              final u = list[i];
                              final name = (u['name'] ?? '—').toString();
                              final isClient = u['isClient'] == true;
                              final role = (u['customTitle'] ?? u['role'] ?? '').toString().replaceAll('_', ' ');
                              return ListTile(
                                leading: BestieAvatar(
                                  name: name,
                                  imageUrl: u['avatarUrl']?.toString(),
                                  isClient: isClient,
                                  size: 40,
                                ),
                                title: BestieUserName(name: name, isClient: isClient,
                                    style: TextStyle(fontWeight: BestieTokens.fwSemibold, color: c.text)),
                                subtitle: Text(role.toLowerCase(),
                                    style: TextStyle(color: c.textMuted, fontSize: 12)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (canManage)
                                      PopupMenuButton<String>(
                                        tooltip: 'Manage employee',
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _openEmployeeForm(u);
                                          } else if (value == 'delete') {
                                            _deleteEmployee(u);
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit employee'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete employee'),
                                          ),
                                        ],
                                      ),
                                    IconButton(
                                      icon: Icon(Icons.chat_bubble_outline_rounded, color: c.brand),
                                      tooltip: 'Message',
                                      onPressed: () => _openDm(u),
                                    ),
                                  ],
                                ),
                                onTap: canManage
                                    ? () => _openEmployeeForm(u)
                                    : () => _openDm(u),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
