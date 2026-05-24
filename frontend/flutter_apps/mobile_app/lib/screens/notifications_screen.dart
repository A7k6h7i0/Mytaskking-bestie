import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

const _categoryLabels = {
  'chat':   'Messages',
  'task':   'Tasks',
  'call':   'Calls',
  'lead':   'Telecaller',
  'system': 'System',
};
const _categoryIcons = {
  'chat':   Icons.chat_bubble_outline,
  'task':   Icons.task_alt_outlined,
  'call':   Icons.call_outlined,
  'lead':   Icons.headset_mic_outlined,
  'system': Icons.campaign_outlined,
};

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: BestieTokens.cSurface,
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark all read',
            onPressed: () async {
              try {
                await ref.read(apiProvider).markAllNotificationsRead();
                ref.invalidate(notificationsProvider);
              } catch (e) {
                if (context.mounted) bestieToast(context, 'Could not update', body: formatApiError(e), kind: BestieToastKind.error);
              }
            },
          ),
        ],
      ),
      body: stream.when(
        loading: () => const Center(child: BestieSpinner()),
        error: (e, _) => BestieEmptyState(
          icon: Icons.error_outline, iconColor: BestieTokens.cDanger,
          title: 'Couldn\'t load', description: formatApiError(e),
        ),
        data: (data) {
          final groups = (data['groups'] as Map?)?.cast<String, dynamic>() ?? const {};
          final unread = data['unread'] ?? 0;
          if (groups.isEmpty) {
            return const BestieEmptyState(
              icon: Icons.notifications_none,
              title: 'You\'re all caught up',
              description: 'New notifications will appear here in realtime.',
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(children: [
                  Text('$unread unread', style: const TextStyle(color: BestieTokens.cTextMuted)),
                  const Spacer(),
                  BestieBadge(tone: BestieTone.success, dot: true, child: const Text('Live')),
                ]),
              ),
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(children: [
                    Icon(_categoryIcons[entry.key] ?? Icons.bolt, size: 14, color: BestieTokens.cTextMuted),
                    const SizedBox(width: 6),
                    Text(
                      (_categoryLabels[entry.key] ?? entry.key).toUpperCase(),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BestieTokens.cTextMuted, letterSpacing: 0.5),
                    ),
                  ]),
                ),
                ...((entry.value as List).cast<Map<String, dynamic>>().map((n) {
                  final unreadItem = n['readAt'] == null;
                  return Container(
                    color: unreadItem ? BestieTokens.cBrandSoft : Colors.transparent,
                    child: ListTile(
                      title: Text(n['title'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(n['body'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: BestieTokens.cTextMuted, fontSize: 12)),
                      trailing: Text(_fmtTime(n['createdAt']),
                          style: const TextStyle(color: BestieTokens.cTextFaint, fontSize: 11)),
                    ),
                  );
                })),
              ],
            ],
          );
        },
      ),
    );
  }

  String _fmtTime(dynamic v) {
    final d = DateTime.tryParse('$v')?.toLocal();
    if (d == null) return '';
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
