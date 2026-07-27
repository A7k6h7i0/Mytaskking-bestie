import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Super admin inbox + assignee issues list.
class SupportIssuesScreen extends ConsumerStatefulWidget {
  const SupportIssuesScreen({super.key});

  @override
  ConsumerState<SupportIssuesScreen> createState() => _SupportIssuesScreenState();
}

class _SupportIssuesScreenState extends ConsumerState<SupportIssuesScreen> {
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _statuses = const [];
  bool _loading = true;
  String? _error;

  bool get _isSuperAdmin =>
      ref.read(authStoreProvider).user?.isPlatformSuperAdmin ?? false;

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
      final api = ref.read(apiProvider);
      final meta = await api.supportTicketMeta();
      final items = _isSuperAdmin
          ? await api.listSupportTicketsAdmin()
          : await api.listSupportTicketsAssigned();
      if (!mounted) return;
      setState(() {
        _statuses = List<Map<String, dynamic>>.from(meta['statuses'] ?? const []);
        _items = items;
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

  Future<void> _assign(String ticketId) async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> assignees = const [];

    Future<void> search(String q) async {
      assignees = await ref.read(apiProvider).listSupportTicketAssignees(q: q);
    }

    await search('');

    if (!mounted) return;
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Assign to employee'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Search by name or email',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) async {
                    await search(v.trim());
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 240,
                  child: ListView.builder(
                    itemCount: assignees.length,
                    itemBuilder: (_, i) {
                      final u = assignees[i];
                      final tenantName =
                          (u['tenant'] as Map?)?['name']?.toString();
                      return ListTile(
                        title: Text(u['name']?.toString() ?? ''),
                        subtitle: Text(
                          [
                            u['email']?.toString(),
                            if (tenantName != null) tenantName,
                          ].whereType<String>().join(' · '),
                        ),
                        onTap: () => Navigator.pop(ctx, u),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                await search(searchCtrl.text.trim());
                setDialogState(() {});
              },
              child: const Text('Search'),
            ),
          ],
        ),
      ),
    );
    searchCtrl.dispose();
    if (picked == null || !mounted) return;

    try {
      await ref.read(apiProvider).assignSupportTicket(
            ticketId,
            assigneeId: picked['id'].toString(),
          );
      await _load();
      if (mounted) {
        bestieToast(context, 'Issue assigned',
            body: picked['name']?.toString(), kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Assign failed',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> ticket) async {
    final notesCtrl = TextEditingController(
      text: ticket['resolutionNotes']?.toString() ?? '',
    );
    String status = ticket['status']?.toString() ?? 'OPEN';
    final c = BestieColors.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(ticket['ticketNumber']?.toString() ?? 'Update status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: _statuses
                    .map(
                      (s) => DropdownMenuItem<String>(
                        value: s['value']?.toString(),
                        child: Text(s['label']?.toString() ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setDialogState(() => status = v ?? status),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Resolution notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: c.brand),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) {
      notesCtrl.dispose();
      return;
    }
    try {
      await ref.read(apiProvider).updateSupportTicketStatus(
            ticket['id'].toString(),
            status: status,
            resolutionNotes: notesCtrl.text.trim(),
          );
      notesCtrl.dispose();
      await _load();
    } catch (e) {
      notesCtrl.dispose();
      if (mounted) {
        bestieToast(context, 'Update failed',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  BestieTone _toneForStatus(String status) {
    switch (status) {
      case 'RESOLVED':
      case 'CLOSED':
        return BestieTone.success;
      case 'IN_PROGRESS':
      case 'ASSIGNED':
        return BestieTone.info;
      default:
        return BestieTone.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuper = ref.watch(authStoreProvider).user?.isPlatformSuperAdmin ?? false;
    final c = BestieColors.of(context);
    final canPop = context.canPop();

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        backgroundColor: c.surface,
        foregroundColor: c.textMuted,
        automaticallyImplyLeading: canPop,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              )
            : null,
        title: Text(isSuper ? 'Support inbox' : 'Issues'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: BestieSpinner())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: c.danger)))
              : _items.isEmpty
                  ? Center(
                      child: Text(
                        isSuper ? 'No support tickets yet' : 'No assigned issues',
                        style: TextStyle(color: c.textMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final t = _items[i];
                        final status = t['status']?.toString() ?? 'OPEN';
                        final reporter = t['reporter'] as Map?;
                        final assignee = t['assignee'] as Map?;
                        return Card(
                          child: InkWell(
                            onTap: () => _showDetail(t, isSuper),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          t['ticketNumber']?.toString() ?? '',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      BestieBadge(
                                        tone: _toneForStatus(status),
                                        child: Text(
                                          t['statusLabel']?.toString() ?? status,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(t['issueTypeLabel']?.toString() ?? ''),
                                  if (isSuper && reporter != null)
                                    Text(
                                      'From ${reporter['name']} (${reporter['email'] ?? reporter['userId']})',
                                      style: TextStyle(
                                        color: c.textMuted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  if (assignee != null)
                                    Text(
                                      'Assignee: ${assignee['name']}',
                                      style: TextStyle(
                                        color: c.textMuted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Text(
                                    t['description']?.toString() ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Future<void> _showDetail(Map<String, dynamic> ticket, bool isSuper) async {
    final c = BestieColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ticket['ticketNumber']?.toString() ?? '',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(ticket['description']?.toString() ?? ''),
              const SizedBox(height: 16),
              if (isSuper)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _assign(ticket['id'].toString());
                  },
                  style: FilledButton.styleFrom(backgroundColor: c.brand),
                  child: const Text('Assign employee'),
                ),
              if (!isSuper || ticket['assigneeId'] != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _updateStatus(ticket);
                  },
                  child: const Text('Update status'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
