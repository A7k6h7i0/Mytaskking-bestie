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
  static const _assigneeStatusValues = {'IN_PROGRESS', 'RESOLVED', 'CLOSED'};

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

  Future<void> _assign(String ticketId, {List<String> initialIds = const []}) async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> assignees = const [];
    final selected = Set<String>.from(initialIds);

    Future<void> search(String q) async {
      assignees = await ref.read(apiProvider).listSupportTicketAssignees(q: q);
    }

    await search('');

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final hasExisting = initialIds.isNotEmpty;
          return AlertDialog(
            title: Text(hasExisting ? 'Edit assigns' : 'Assign employees'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select platform team members. Unchecked people lose access to this issue.',
                    style: TextStyle(
                      color: BestieColors.of(ctx).textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                    height: 280,
                    child: ListView.builder(
                      itemCount: assignees.length,
                      itemBuilder: (_, i) {
                        final u = assignees[i];
                        final id = u['id']?.toString() ?? '';
                        final tenantName =
                            (u['tenant'] as Map?)?['name']?.toString();
                        return CheckboxListTile(
                          value: selected.contains(id),
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) {
                                selected.add(id);
                              } else {
                                selected.remove(id);
                              }
                            });
                          },
                          title: Text(u['name']?.toString() ?? ''),
                          subtitle: Text(
                            [
                              u['email']?.toString(),
                              if (tenantName != null) tenantName,
                            ].whereType<String>().join(' · '),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () async {
                  await search(searchCtrl.text.trim());
                  setDialogState(() {});
                },
                child: const Text('Search'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    searchCtrl.dispose();
    if (saved != true || !mounted) return;

    try {
      await ref.read(apiProvider).assignSupportTicket(
            ticketId,
            assigneeIds: selected.toList(),
          );
      await _load();
      if (mounted) {
        bestieToast(context, 'Assignees updated', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Assign failed',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  List<String> _assigneeIds(Map<String, dynamic> ticket) {
    final ids = ticket['assigneeIds'];
    if (ids is List) return ids.map((e) => e.toString()).toList();
    final assignees = ticket['assignees'];
    if (assignees is List) {
      return assignees
          .map((a) => (a as Map)['id']?.toString())
          .whereType<String>()
          .toList();
    }
    final single = ticket['assigneeId']?.toString();
    return single != null ? [single] : [];
  }

  String _assigneeNames(Map<String, dynamic> ticket) {
    final assignees = ticket['assignees'];
    if (assignees is List && assignees.isNotEmpty) {
      return assignees
          .map((a) => (a as Map)['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .join(', ');
    }
    final assignee = ticket['assignee'] as Map?;
    return assignee?['name']?.toString() ?? '';
  }

  bool _userCanUpdate(Map<String, dynamic> ticket) {
    if (_isSuperAdmin) return true;
    final status = ticket['status']?.toString() ?? 'OPEN';
    if (status == 'CLOSED') return false;
    final me = ref.read(authStoreProvider).user?.id;
    if (me == null) return false;
    return _assigneeIds(ticket).contains(me);
  }

  List<Map<String, dynamic>> _statusOptionsForUser(bool isSuper) {
    if (isSuper) return _statuses;
    return _statuses
        .where((s) => _assigneeStatusValues.contains(s['value']?.toString()))
        .toList();
  }

  String _defaultStatusForUser(String current, bool isSuper) {
    if (isSuper) return current;
    if (_assigneeStatusValues.contains(current)) return current;
    return 'IN_PROGRESS';
  }

  Future<void> _updateStatus(Map<String, dynamic> ticket, {required bool isSuper}) async {
    final notesCtrl = TextEditingController(
      text: ticket['resolutionNotes']?.toString() ?? '',
    );
    final options = _statusOptionsForUser(isSuper);
    String status = _defaultStatusForUser(
      ticket['status']?.toString() ?? 'OPEN',
      isSuper,
    );
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
                items: options
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
    final user = ref.watch(authStoreProvider).user;
    final isSuper = user?.isPlatformSuperAdmin ?? false;
    final isAssignee = user?.isDefaultTenantSupportAssignee ?? false;
    final c = BestieColors.of(context);
    final canPop = context.canPop();

    if (!isSuper && !isAssignee) {
      return Scaffold(
        appBar: AppBar(title: const Text('Issues')),
        body: BestieEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available',
          description: isSuper
              ? 'Support inbox is for platform super admin only.'
              : 'Issues are only for default organisation support team members.',
        ),
      );
    }

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
                        final names = _assigneeNames(t);
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
                                  if (names.isNotEmpty)
                                    Text(
                                      'Assigned: $names',
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
    final status = ticket['status']?.toString() ?? 'OPEN';
    final closed = status == 'CLOSED';
    final assigneeIds = _assigneeIds(ticket);
    final canUpdate = _userCanUpdate(ticket);

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
              if (assigneeIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Assigned: ${_assigneeNames(ticket)}',
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              if (isSuper)
                FilledButton(
                  onPressed: closed
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _assign(
                            ticket['id'].toString(),
                            initialIds: assigneeIds,
                          );
                        },
                  style: FilledButton.styleFrom(backgroundColor: c.brand),
                  child: Text(
                    assigneeIds.isNotEmpty
                        ? 'Edit assigns'
                        : 'Assign employees',
                  ),
                ),
              if (canUpdate) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _updateStatus(ticket, isSuper: isSuper);
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
