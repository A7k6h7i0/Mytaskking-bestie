import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

String _savedTitle(Map<String, dynamic> s) {
  final note = (s['note'] ?? '').toString().trim();
  if (note.isNotEmpty) return note;
  final target = (s['target'] as Map?)?.cast<String, dynamic>();
  if (target == null) return 'Saved item';
  final kind = (s['kind'] ?? 'item').toString().toUpperCase();
  switch (kind) {
    case 'MESSAGE':
      final body = (target['body'] ?? '').toString().trim();
      if (body.isNotEmpty) return body;
      final kindLabel = (target['kind'] ?? '').toString();
      if (kindLabel == 'FILE') return 'Attachment';
      return 'Message';
    case 'TASK':
      return (target['title'] ?? 'Task').toString();
    case 'FILE':
      return (target['filename'] ?? target['name'] ?? 'File').toString();
    case 'CHANNEL':
      return (target['name'] ?? 'Chat').toString();
    case 'LEAD':
      return (target['name'] ?? target['phone'] ?? 'Lead').toString();
    default:
      return 'Saved item';
  }
}

String _savedSubtitle(Map<String, dynamic> s) {
  final kind = (s['kind'] ?? 'item').toString().toUpperCase();
  final target = (s['target'] as Map?)?.cast<String, dynamic>();
  if (kind == 'MESSAGE' && target != null) {
    final author = (target['author'] as Map?)?.cast<String, dynamic>();
    final name = (author?['name'] ?? 'Someone').toString();
    final channel = (target['channel'] as Map?)?.cast<String, dynamic>();
    final channelName = (channel?['name'] ?? '').toString().trim();
    if (channelName.isNotEmpty) return '$name · $channelName';
    return name;
  }
  return kind.toLowerCase();
}

void _openSaved(BuildContext context, Map<String, dynamic> s) {
  final kind = (s['kind'] ?? 'item').toString().toUpperCase();
  final target = (s['target'] as Map?)?.cast<String, dynamic>();
  switch (kind) {
    case 'MESSAGE':
      final cid = target?['channelId']?.toString() ??
          (target?['channel'] as Map?)?['id']?.toString() ??
          s['channelId']?.toString();
      if (cid != null) context.push('/chat/$cid');
      break;
    case 'TASK':
      final id = target?['id']?.toString() ?? s['refId']?.toString();
      if (id != null) {
        context.push('/tasks/$id');
      } else {
        context.go('/tasks');
      }
      break;
    case 'CHANNEL':
      final id = target?['id']?.toString() ?? s['refId']?.toString();
      if (id != null) context.push('/chat/$id');
      break;
    case 'FILE':
      final cid = target?['channelId']?.toString();
      if (cid != null) context.push('/chat/$cid');
      break;
    case 'LEAD':
      context.go('/telecaller');
      break;
  }
}

/// Bookmarks — messages / tasks / files the user has saved for later.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final saved = ref.watch(savedProvider);

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/chat');
            }
          },
        ),
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
                    _savedTitle(s),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: BestieTokens.fwSemibold, color: c.text),
                  ),
                  subtitle: Text(
                    _savedSubtitle(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                  onTap: () => _openSaved(context, s),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
