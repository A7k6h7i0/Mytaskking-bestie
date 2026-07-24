import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import 'field_sub_scaffold.dart';

class FieldGpsScreen extends ConsumerStatefulWidget {
  const FieldGpsScreen({super.key});

  @override
  ConsumerState<FieldGpsScreen> createState() => _FieldGpsScreenState();
}

class _FieldGpsScreenState extends ConsumerState<FieldGpsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ref.read(apiProvider).listFieldGps();
      if (!mounted) return;
      setState(() {
        _items = ((resp['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final isManager = ref.watch(authStoreProvider).user?.isFieldManager ?? false;
    if (!isManager) {
      return FieldSubScaffold(
        title: 'GPS log',
        body: Center(child: Text('Managers only', style: TextStyle(color: c.textMuted))),
      );
    }
    return FieldSubScaffold(
      title: 'Team GPS log',
      body: _loading
          ? const Center(child: BestieSpinner())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(children: [
                      Center(
                          child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No GPS pings yet', style: TextStyle(color: c.textMuted)),
                      ))
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final g = _items[i];
                        final user = (g['user'] as Map?)?.cast<String, dynamic>();
                        return ListTile(
                          tileColor: c.surface2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          title: Text(user?['name']?.toString() ?? 'Executive'),
                          subtitle: Text(
                            '${g['latitude']}, ${g['longitude']}\n${g['loggedAt'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                        );
                      },
                    ),
            ),
    );
  }
}
