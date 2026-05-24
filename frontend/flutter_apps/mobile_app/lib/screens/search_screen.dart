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
      onOpen: (kind, item) => _openHit(context, kind, item),
    );
  }

  void _openHit(BuildContext context, String kind, Map<String, dynamic> item) {
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
          // Standalone file → open the URL externally via a snackbar hint.
          final url = item['url']?.toString();
          if (url != null) {
            bestieToast(context, 'File link copied',
                body: url, kind: BestieToastKind.info);
          }
        }
        break;
      }
      case 'tasks':
        context.go('/tasks');
        break;
      case 'leads':
        // Mobile shell doesn't expose telecaller — fall back to dashboard.
        context.go('/dashboard');
        break;
      case 'users':
        // No people detail screen yet; the chat list is the closest landing.
        context.go('/chat');
        break;
    }
  }
}
