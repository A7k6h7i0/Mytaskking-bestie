import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: BestieTokens.cSurface,
        title: const Text('Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search people, messages, files',
            onPressed: () => context.go('/search'),
          ),
          IconButton(icon: const Icon(Icons.add_comment_outlined), onPressed: () {}),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(channelsProvider.future),
        child: channels.when(
          loading: () => const Center(child: BestieSpinner()),
          error: (e, _) => BestieEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Couldn\'t load channels',
            description: formatApiError(e),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const BestieEmptyState(
                icon: Icons.tag,
                title: 'No channels yet',
                description: 'An admin needs to add you to a channel before you can chat.',
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (ctx, i) {
                final c = items[i];
                final members = (c['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
                final lastReadAt = members
                    .firstWhere((m) => m['userId'] == ref.read(authStoreProvider).user?.id, orElse: () => {})['lastReadAt'];
                final name = c['name'] ?? '—';
                final kind = c['kind'] ?? 'GROUP';
                final isClient = c['isClientChannel'] == true;
                final unread = lastReadAt == null;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isClient ? BestieTokens.cClientSoft : BestieTokens.cBrandSoft,
                    child: Icon(
                      kind == 'CLIENT' ? Icons.business_center : Icons.tag,
                      color: isClient ? BestieTokens.cClient : BestieTokens.cBrandStrong,
                    ),
                  ),
                  title: BestieUserName(name: name, isClient: isClient,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  subtitle: Text(
                    '${(members.length)} members · $kind',
                    style: const TextStyle(color: BestieTokens.cTextMuted),
                  ),
                  trailing: unread
                      ? const BestieBadge(tone: BestieTone.brand, child: Text('NEW'))
                      : null,
                  onTap: () => context.go('/chat/${c['id']}'),
                );
              },
            );
          },
        ),
      ),
    );
  }

}
