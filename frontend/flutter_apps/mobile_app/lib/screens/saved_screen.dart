import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Bookmarks — messages / tasks / files the user has saved for later.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final saved = ref.watch(savedProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Saved'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(savedProvider.future),
        child: saved.when(
          loading: () => const Center(child: BestieSpinner()),
          error: (e, _) => BestieEmptyState(
            icon: Icons.error_outline_rounded,
            iconColor: c.danger,
            title: 'Could not load saved items',
            description: formatApiError(e),
          ),
          data: (items) {
            if (items.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: const Center(
                      child: BestieEmptyState(
                        icon: Icons.bookmark_outline_rounded,
                        title: 'Nothing saved yet',
                        description:
                            'Long-press a message, file, or task to save it for later.',
                      ),
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, indent: 56, color: c.border),
              itemBuilder: (ctx, i) {
                final s = items[i];
                final kind = (s['kind'] ?? 'item').toString().toUpperCase();
                final icon = switch (kind) {
                  'MESSAGE' => Icons.chat_bubble_outline_rounded,
                  'TASK' => Icons.task_alt_outlined,
                  'FILE' => Icons.description_outlined,
                  _ => Icons.bookmark_outline_rounded,
                };
                final accent = switch (kind) {
                  'MESSAGE' => c.brand,
                  'TASK' => c.success,
                  'FILE' => c.info,
                  _ => c.textMuted,
                };
                return ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(BestieTokens.rSm),
                    ),
                    child: Icon(icon, color: accent, size: 18),
                  ),
                  title: Text(
                    (s['title'] ?? s['note'] ?? '—').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: BestieTokens.fwSemibold, color: c.text),
                  ),
                  subtitle: Text(
                    kind.toLowerCase(),
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                  onTap: () {
                    // Best-effort route by kind.
                    switch (kind) {
                      case 'MESSAGE':
                        final cid = s['channelId']?.toString();
                        if (cid != null) context.push('/chat/$cid');
                        break;
                      case 'TASK':
                        context.go('/tasks');
                        break;
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
