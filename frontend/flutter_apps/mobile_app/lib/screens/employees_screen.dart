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
  static const _baseRoles = [
    'ADMIN',
    'MANAGER',
    'PROJECT_COORDINATOR_MANAGER',
    'EMPLOYEE',
    'TELECALLER',
  ];

  static List<String> _rolesFor(BestieUser? user) {
    if (user?.isPlatformSuperAdmin == true) {
      return [..._baseRoles, 'SALES_HEAD'];
    }
    return _baseRoles;
  }

  static String _roleLabel(String role) => switch (role) {
        'PROJECT_COORDINATOR_MANAGER' => 'Project coordinator',
        'TELECALLER' => 'Telecaller',
        'SALES_HEAD' => 'Sales head',
        _ => role[0] + role.substring(1).toLowerCase().replaceAll('_', ' '),
      };
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
      if (mounted) {
        context.push('/chat/${ch['id']}');
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not open chat',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _openEmployeeForm([Map<String, dynamic>? employee]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EmployeeFormDialog(
        employee: employee,
        candidates: _items,
      ),
    );
    if (!mounted || saved != true) return;
    await _fetch(_search.text);
    if (!mounted) return;
    bestieToast(
      context,
      employee != null ? 'Employee updated' : 'Employee added',
      kind: BestieToastKind.success,
    );
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
    final canManage = me != null &&
        const {'SUPER_ADMIN', 'ADMIN', 'MANAGER'}.contains(me.role);
    final list = _items.where((u) => u['id'] != me?.id).toList();

    return Scaffold(
      backgroundColor: c.surface,
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
                                    if (u['role']?.toString() != 'SUPER_ADMIN')
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
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openEmployeeForm(),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add employee'),
            )
          : null,
    );
  }
}

class _EmployeeFormDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? employee;
  final List<Map<String, dynamic>> candidates;

  const _EmployeeFormDialog({
    required this.employee,
    required this.candidates,
  });

  @override
  ConsumerState<_EmployeeFormDialog> createState() =>
      _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends ConsumerState<_EmployeeFormDialog> {
  late final TextEditingController _userId;
  late final TextEditingController _password;
  late final TextEditingController _name;
  late final TextEditingController _customTitle;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _avatarUrl;
  late final Set<String> _supervisorIds;
  late String _role;
  late String _status;
  bool _showPassword = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.employee != null;

  @override
  void initState() {
    super.initState();
    final employee = widget.employee;
    _userId = TextEditingController(text: employee?['userId']?.toString());
    _password = TextEditingController();
    _name = TextEditingController(text: employee?['name']?.toString());
    _customTitle =
        TextEditingController(text: employee?['customTitle']?.toString());
    _email = TextEditingController(text: employee?['email']?.toString());
    _phone = TextEditingController(text: employee?['phone']?.toString());
    _avatarUrl =
        TextEditingController(text: employee?['avatarUrl']?.toString());
    _supervisorIds = ((employee?['supervisors'] as List?) ?? const [])
        .map((entry) => (entry as Map?)?['supervisorId']?.toString())
        .whereType<String>()
        .toSet();
    _role = employee?['role']?.toString() ?? 'EMPLOYEE';
    _status = employee?['status']?.toString() ?? 'ACTIVE';
  }

  @override
  void dispose() {
    _userId.dispose();
    _password.dispose();
    _name.dispose();
    _customTitle.dispose();
    _email.dispose();
    _phone.dispose();
    _avatarUrl.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
      );

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _submit() async {
    if (_userId.text.trim().length < 2 ||
        _name.text.trim().isEmpty ||
        (!_editing && _password.text.length < 8) ||
        (_editing &&
            _password.text.isNotEmpty &&
            _password.text.length < 8)) {
      setState(() => _error =
          'Enter a name, User ID, and a password of at least 8 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final data = <String, dynamic>{
      'userId': _userId.text.trim(),
      'name': _name.text.trim(),
      'role': _role,
      'status': _status,
      'customTitle': _optional(_customTitle),
      'email': _optional(_email),
      'phone': _optional(_phone),
      'avatarUrl': _optional(_avatarUrl),
      'supervisorIds': _supervisorIds.toList(),
      if (_password.text.isNotEmpty) 'password': _password.text,
    };
    try {
      if (_editing) {
        await ref
            .read(apiProvider)
            .updateEmployee(widget.employee!['id'] as String, data);
      } else {
        data.remove('status');
        await ref.read(apiProvider).createEmployee(data);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = formatApiError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width - 48;
    final maxHeight = size.height * 0.72;
    final reportCandidates = widget.candidates
        .where((item) => item['id'] != widget.employee?['id'])
        .toList();

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: Text(_editing ? 'Edit employee' : 'Add employee'),
      content: SizedBox(
        width: maxWidth.clamp(280, 440),
        height: maxHeight,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _userId,
              decoration: _decoration('User ID'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: _decoration(
                _editing ? 'New password (optional)' : 'Password',
                hint: _editing ? 'Leave blank to keep current password' : null,
              ).copyWith(
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: _decoration('Full name'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customTitle,
              decoration: _decoration('Job title'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              decoration: _decoration('Email'),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              decoration: _decoration('Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _avatarUrl,
              decoration: _decoration('Avatar URL'),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              isExpanded: true,
              decoration: _decoration('Role'),
              items: _EmployeesScreenState._rolesFor(ref.read(authStoreProvider).user)
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(
                          _EmployeesScreenState._roleLabel(value),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _role = value ?? _role),
            ),
            if (_editing) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                isExpanded: true,
                decoration: _decoration('Status'),
                items: const [
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                  DropdownMenuItem(value: 'SUSPENDED', child: Text('Suspended')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _status = value ?? _status),
              ),
            ],
            if (reportCandidates.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Reports to',
                  style: TextStyle(
                    color: c.textMuted,
                    fontWeight: BestieTokens.fwSemibold,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final candidate in reportCandidates)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _supervisorIds
                            .contains(candidate['id']?.toString()),
                        title: Text(
                          (candidate['name'] ?? candidate['userId']).toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                        onChanged: _saving
                            ? null
                            : (checked) => setState(() {
                                  final id = candidate['id'].toString();
                                  checked == true
                                      ? _supervisorIds.add(id)
                                      : _supervisorIds.remove(id);
                                }),
                      ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: c.danger, fontSize: 12),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Saving…' : (_editing ? 'Save' : 'Add')),
        ),
      ],
    );
  }
}
