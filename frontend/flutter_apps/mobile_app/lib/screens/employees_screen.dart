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
      if (mounted) context.go('/chat/${ch['id']}');
    } catch (e) {
      if (mounted) bestieToast(context, 'Could not open chat',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final me = ref.watch(authStoreProvider).user;
    final list = _items.where((u) => u['id'] != me?.id).toList();

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Employees'),
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
                                trailing: IconButton(
                                  icon: Icon(Icons.chat_bubble_outline_rounded, color: c.brand),
                                  tooltip: 'Message',
                                  onPressed: () => _openDm(u),
                                ),
                                onTap: () => _openDm(u),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
