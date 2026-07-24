import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import 'field_sub_scaffold.dart';

String? _visitSelfieUrl(Map<String, dynamic> visit) {
  final raw = visit['selfieUrl']?.toString() ?? '';
  if (raw.isEmpty || raw == 'auto-detected') return null;
  return raw;
}

/// Manager view — org-wide visit log.
class FieldManagerScreen extends ConsumerStatefulWidget {
  const FieldManagerScreen({super.key});

  @override
  ConsumerState<FieldManagerScreen> createState() =>
      _FieldManagerScreenState();
}

class _FieldManagerScreenState extends ConsumerState<FieldManagerScreen> {
  List<Map<String, dynamic>> _visits = const [];
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
      final resp = await ref.read(apiProvider).listFieldVisits();
      final items = (resp['items'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _visits = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final isManager = ref.watch(authStoreProvider).user?.isFieldManager ?? false;
    if (!isManager) {
      return FieldSubScaffold(
        title: 'Team visits',
        body: Center(
          child: Text('Managers only', style: TextStyle(color: c.textMuted)),
        ),
      );
    }
    return FieldSubScaffold(
      title: 'Team visits',
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: BestieSpinner())
            : _error != null
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, style: TextStyle(color: c.danger)),
                      ),
                    ],
                  )
                : _visits.isEmpty
                    ? ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Text('No visits logged yet',
                                  style: TextStyle(color: c.textMuted)),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: _visits.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final v = _visits[i];
                          final user = (v['user'] as Map?)?.cast<String, dynamic>();
                          final outlet =
                              (v['outlet'] as Map?)?.cast<String, dynamic>();
                          final selfie = _visitSelfieUrl(v);
                          return Material(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(BestieTokens.rLg),
                            child: ListTile(
                              leading: selfie != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        selfie,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                            Icons.place_outlined,
                                            color: c.brand),
                                      ),
                                    )
                                  : Icon(Icons.place_outlined, color: c.brand),
                              title: Text(outlet?['name']?.toString() ?? 'Visit',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600, color: c.text)),
                              subtitle: Text(
                                '${user?['name'] ?? 'Executive'} · ${v['status'] ?? ''}',
                                style: TextStyle(color: c.textMuted, fontSize: 12),
                              ),
                              onTap: selfie == null
                                  ? null
                                  : () => showDialog<void>(
                                        context: context,
                                        builder: (ctx) => Dialog(
                                          child: InteractiveViewer(
                                            child: Image.network(selfie),
                                          ),
                                        ),
                                      ),
                              trailing: BestieBadge(
                                tone: v['status'] == 'completed'
                                    ? BestieTone.success
                                    : BestieTone.warning,
                                child: Text((v['status'] ?? 'planned').toString()),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
