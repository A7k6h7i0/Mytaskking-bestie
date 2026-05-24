import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Host screen — wires [BestieSearchScreen] to the API and routes results
/// to the right destination (chat detail, file URL, telecaller, etc.).
class SearchScreen extends ConsumerWidget {
  final String? initialQuery;
  final String? initialKind;

  const SearchScreen({super.key, this.initialQuery, this.initialKind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BestieSearchScreen(
      initialQuery: initialQuery,
      initialKind: initialKind,
      fetcher: (q, kind) => ref.read(apiProvider).search(q, kinds: kind),
      onOpen: (kind, item) => _openHit(context, ref, kind, item),
      // /search is a top-level go_router route, so the default
      // Navigator.maybePop() inside the design system widget is a no-op.
      // Use go_router's pop with a /dashboard fallback so the back arrow
      // always takes the user somewhere coherent.
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/dashboard');
        }
      },
    );
  }

  Future<void> _openHit(
    BuildContext context,
    WidgetRef ref,
    String kind,
    Map<String, dynamic> item,
  ) async {
    switch (kind) {
      case 'channels': {
        final id = item['id']?.toString();
        if (id != null) context.go('/chat/$id');
        break;
      }
      case 'messages': {
        final channelId = item['channelId']?.toString();
        if (channelId != null) context.go('/chat/$channelId');
        break;
      }
      case 'files': {
        // Files prefer landing in the channel they were shared in.
        final firstMsg = ((item['messages'] as List?) ?? const []).isEmpty
            ? null
            : ((item['messages'] as List).first as Map?)?.cast<String, dynamic>();
        final channel = firstMsg != null
            ? (firstMsg['channel'] as Map?)?.cast<String, dynamic>()
            : null;
        final channelId = channel?['id']?.toString();
        if (channelId != null) {
          context.go('/chat/$channelId');
        } else {
          final url = item['url']?.toString();
          if (url != null && context.mounted) {
            bestieToast(context, 'File link', body: url, kind: BestieToastKind.info);
          }
        }
        break;
      }
      case 'tasks':
        context.go('/tasks');
        break;
      case 'leads':
        context.go('/dashboard');
        break;
      case 'users': {
        // Tap a person → open (or create) a DM with them.
        final me = ref.read(authStoreProvider).user;
        final userId = item['id']?.toString();
        if (userId == null || userId == me?.id) {
          context.go('/chat');
          return;
        }
        if (item['isClient'] == true) {
          // Clients live in client channels — directory route, not DM.
          context.go('/chat');
          return;
        }
        try {
          final channel = await ref.read(apiProvider).createChannel(
            kind: 'DM',
            memberIds: [userId],
          );
          ref.invalidate(channelsProvider);
          final id = channel['id']?.toString();
          if (id != null && context.mounted) {
            context.go('/chat/$id');
          }
        } catch (e) {
          if (context.mounted) {
            bestieToast(context, 'Could not open chat',
                body: formatApiError(e), kind: BestieToastKind.error);
          }
        }
        break;
      }
    }
  }
}
