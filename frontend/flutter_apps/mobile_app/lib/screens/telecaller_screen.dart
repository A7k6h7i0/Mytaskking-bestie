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
      if (mounted) bestieToast(context, 'Could not call',
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
        title: const Text('Telecaller'),
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
}
