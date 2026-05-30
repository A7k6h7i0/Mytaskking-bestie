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
    try {
      final ch = await ref.read(apiProvider).createChannel(
        kind: 'CLIENT',
        name: client['name']?.toString() ?? client['clientCompany']?.toString() ?? 'Client',
        memberIds: [client['id'] as String],
      );
      ref.invalidate(channelsProvider);
      if (mounted) context.push('/chat/${ch['id']}');
    } catch (e) {
      if (mounted) bestieToast(context, 'Could not open channel',
          body: formatApiError(e), kind: BestieToastKind.error);
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
        title: const Text('Clients'),
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
                                trailing: IconButton(
                                  icon: Icon(Icons.business_center_outlined, color: c.client),
                                  tooltip: 'Open client channel',
                                  onPressed: () => _openChannel(u),
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
}
