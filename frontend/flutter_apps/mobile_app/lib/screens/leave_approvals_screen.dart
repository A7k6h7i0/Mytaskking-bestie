import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

final _pendingLeavesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.read(apiProvider).listOrgLeaves(status: 'PENDING');
});

class LeaveApprovalsScreen extends ConsumerWidget {
  const LeaveApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final pending = ref.watch(_pendingLeavesProvider);

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: const Text('Leave requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_pendingLeavesProvider),
          ),
        ],
      ),
      body: pending.when(
        loading: () => const Center(child: BestieSpinner()),
        error: (e, _) => BestieEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load requests',
          description: formatApiError(e),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const BestieEmptyState(
              icon: Icons.event_available_outlined,
              title: 'No pending requests',
              description: 'Approved or rejected requests move off this list.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final row = items[i];
              final user =
                  (row['user'] as Map?)?.cast<String, dynamic>() ?? {};
              return _LeaveCard(row: row, user: user, ref: ref);
            },
          );
        },
      ),
    );
  }
}

class _LeaveCard extends StatefulWidget {
  const _LeaveCard({
    required this.row,
    required this.user,
    required this.ref,
  });

  final Map<String, dynamic> row;
  final Map<String, dynamic> user;
  final WidgetRef ref;

  @override
  State<_LeaveCard> createState() => _LeaveCardState();
}

class _LeaveCardState extends State<_LeaveCard> {
  bool _busy = false;

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await widget.ref
          .read(apiProvider)
          .approveOrgLeave(widget.row['id'].toString());
      widget.ref.invalidate(_pendingLeavesProvider);
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
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.ref.read(apiProvider).rejectOrgLeave(
            widget.row['id'].toString(),
            reason: reasonCtrl.text.trim().isEmpty
                ? null
                : reasonCtrl.text.trim(),
          );
      widget.ref.invalidate(_pendingLeavesProvider);
      if (mounted) {
        bestieToast(context, 'Leave rejected', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not reject',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      reasonCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final row = widget.row;
    final user = widget.user;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BestieAvatar(
                name: user['name']?.toString() ?? 'User',
                imageUrl: user['avatarUrl']?.toString(),
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user['name']?.toString() ?? 'User',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      row['leaveType']?.toString() ?? '',
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${row['fromDate']}${row['toDate'] != null ? ' → ${row['toDate']}' : ''}'
            '${row['startTime'] != null ? ' · ${row['startTime']}-${row['endTime'] ?? ''}' : ''}',
            style: TextStyle(fontSize: 13, color: c.textSoft),
          ),
          if (row['description'] != null) ...[
            const SizedBox(height: 8),
            Text(row['description'].toString()),
          ],
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
      ),
    );
  }
}
