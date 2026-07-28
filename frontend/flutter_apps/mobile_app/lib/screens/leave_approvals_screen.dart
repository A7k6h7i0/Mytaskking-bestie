import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

const _statusFilters = [
  ('ALL', 'All'),
  ('PENDING', 'Pending'),
  ('APPROVED', 'Approved'),
  ('REJECTED', 'Rejected'),
];

String _leaveTypeLabel(String? type) {
  if (type == null || type.isEmpty) return 'Leave';
  return type
      .replaceAll('_', ' ')
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String _statusLabel(String? status) {
  switch (status) {
    case 'APPROVED':
      return 'Approved';
    case 'REJECTED':
      return 'Rejected';
    default:
      return 'Pending';
  }
}

BestieTone _statusTone(String? status) {
  switch (status) {
    case 'APPROVED':
      return BestieTone.success;
    case 'REJECTED':
      return BestieTone.danger;
    default:
      return BestieTone.warning;
  }
}

class LeaveApprovalsScreen extends ConsumerStatefulWidget {
  const LeaveApprovalsScreen({super.key});

  @override
  ConsumerState<LeaveApprovalsScreen> createState() =>
      _LeaveApprovalsScreenState();
}

class _LeaveApprovalsScreenState extends ConsumerState<LeaveApprovalsScreen> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'ALL';
  String? _dateFilter;
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref.read(apiProvider).listOrgLeaves(
            status: _statusFilter == 'ALL' ? null : _statusFilter,
            q: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
            date: _dateFilter,
          );
      if (!mounted) return;
      setState(() {
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFilter != null
          ? DateTime.tryParse(_dateFilter!) ?? now
          : now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      _dateFilter =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    });
    await _load();
  }

  int get _pendingCount =>
      _items.where((row) => row['status']?.toString() == 'PENDING').length;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: const Text('Leave requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Review leave requests. Approved leave pauses GPS tracking.',
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ),
                if (!_loading && _pendingCount > 0) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BestieBadge(
                      tone: BestieTone.warning,
                      child: Text('$_pendingCount pending'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search employee name or ID',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BestieTokens.rMd),
                    ),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Text(
                          _dateFilter ?? 'Filter by date',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (_dateFilter != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Clear date',
                        onPressed: () {
                          setState(() => _dateFilter = null);
                          _load();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final chip in _statusFilters)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(chip.$2),
                            selected: _statusFilter == chip.$1,
                            onSelected: (_) {
                              setState(() => _statusFilter = chip.$1);
                              _load();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: BestieSpinner())
                : _error != null
                    ? BestieEmptyState(
                        icon: Icons.cloud_off_outlined,
                        title: 'Could not load requests',
                        description: _error!,
                      )
                    : _items.isEmpty
                        ? BestieEmptyState(
                            icon: Icons.event_available_outlined,
                            title: 'No leave requests',
                            description:
                                'Try changing search, date, or status filters.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final row = _items[i];
                              final user = (row['user'] as Map?)
                                      ?.cast<String, dynamic>() ??
                                  {};
                              return _LeaveCard(
                                row: row,
                                user: user,
                                onChanged: _load,
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _LeaveCard extends ConsumerStatefulWidget {
  const _LeaveCard({
    required this.row,
    required this.user,
    required this.onChanged,
  });

  final Map<String, dynamic> row;
  final Map<String, dynamic> user;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_LeaveCard> createState() => _LeaveCardState();
}

class _LeaveCardState extends ConsumerState<_LeaveCard> {
  bool _busy = false;

  String get _status => widget.row['status']?.toString() ?? 'PENDING';

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .approveOrgLeave(widget.row['id'].toString());
      await widget.onChanged();
      if (mounted) {
        bestieToast(context, 'Leave approved', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not approve',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject leave?'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true) {
      reasonCtrl.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).rejectOrgLeave(
            widget.row['id'].toString(),
            reason: reasonCtrl.text.trim().isEmpty
                ? null
                : reasonCtrl.text.trim(),
          );
      reasonCtrl.dispose();
      await widget.onChanged();
      if (mounted) {
        bestieToast(context, 'Leave rejected', kind: BestieToastKind.success);
      }
    } catch (e) {
      reasonCtrl.dispose();
      if (mounted) {
        bestieToast(context, 'Could not reject',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final row = widget.row;
    final user = widget.user;
    final status = _status;
    final isPending = status == 'PENDING';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        color: c.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BestieAvatar(
                name: user['name']?.toString() ?? 'User',
                imageUrl: user['avatarUrl']?.toString(),
                size: 40,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user['name']?.toString() ?? 'User',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      _leaveTypeLabel(row['leaveType']?.toString()),
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              BestieBadge(
                tone: _statusTone(status),
                child: Text(_statusLabel(status)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${row['fromDate']}${row['toDate'] != null ? ' → ${row['toDate']}' : ''}'
            '${row['startTime'] != null ? ' · ${row['startTime']}-${row['endTime'] ?? ''}' : ''}',
            style: TextStyle(fontSize: 13, color: c.textSoft, fontWeight: FontWeight.w600),
          ),
          if (row['description'] != null) ...[
            const SizedBox(height: 8),
            Text(row['description'].toString()),
          ],
          if (status == 'REJECTED' && row['rejectionReason'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Reason: ${row['rejectionReason']}',
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ],
          if (!isPending && row['approvedAt'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Reviewed ${row['approvedAt']}',
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ],
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _reject,
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _approve,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
