import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import 'field_sub_scaffold.dart';

class FieldMyVisitsScreen extends ConsumerStatefulWidget {
  const FieldMyVisitsScreen({super.key});

  @override
  ConsumerState<FieldMyVisitsScreen> createState() => _FieldMyVisitsScreenState();
}

class _FieldMyVisitsScreenState extends ConsumerState<FieldMyVisitsScreen> {
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
      final resp = await ref.read(apiProvider).listMyFieldVisits();
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
    return FieldSubScaffold(
      title: 'My visits',
      body: _loading
          ? const Center(child: BestieSpinner())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(children: [
                      Center(
                          child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No visits yet', style: TextStyle(color: c.textMuted)),
                      ))
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final v = _items[i];
                        final outlet = (v['outlet'] as Map?)?.cast<String, dynamic>();
                        return ListTile(
                          tileColor: c.surface2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          title: Text(outlet?['name']?.toString() ?? 'Outlet'),
                          subtitle: Text(
                            '${v['checkInAt'] ?? ''} · ${v['status'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: BestieBadge(
                            tone: v['status'] == 'completed'
                                ? BestieTone.success
                                : BestieTone.warning,
                            child: Text(v['status']?.toString() ?? ''),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
