import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Call history — recent calls with a one-tap "ring back" action.
class CallsScreen extends ConsumerWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Calls'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: ref.read(apiProvider).callHistory(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: BestieSpinner());
          }
          if (snap.hasError) {
            return BestieEmptyState(
              icon: Icons.error_outline_rounded,
              iconColor: c.danger,
              title: 'Could not load calls',
              description: formatApiError(snap.error!),
            );
          }
          final items = ((snap.data?['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
          if (items.isEmpty) {
            return const BestieEmptyState(
              icon: Icons.phone_outlined,
              title: 'No calls yet',
              description: 'Voice and video calls will show up here.',
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(height: 1, indent: 72, color: c.border),
            itemBuilder: (ctx, i) => _CallRow(call: items[i], colors: c),
          );
        },
      ),
    );
  }
}

class _CallRow extends ConsumerWidget {
  final Map<String, dynamic> call;
  final BestieColors colors;
  const _CallRow({required this.call, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.read(authStoreProvider).user;
    final initiator = (call['initiator'] as Map?)?.cast<String, dynamic>() ?? const {};
    final participants = (call['participants'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final outgoing = initiator['id'] == me?.id;

    // Pick a "header" person — for outgoing calls the first non-me participant;
    // for incoming, the initiator.
    Map<String, dynamic> header = initiator;
    if (outgoing && participants.isNotEmpty) {
      final p = participants.firstWhere(
        (p) => (p['user'] as Map?)?['id'] != me?.id,
        orElse: () => participants.first,
      );
      header = (p['user'] as Map?)?.cast<String, dynamic>() ?? initiator;
    }

    final name = (header['name'] ?? '—').toString();
    final isClient = header['isClient'] == true;
    final status = (call['status'] ?? 'COMPLETED').toString();
    final kind = (call['kind'] ?? 'ONE_TO_ONE').toString();
    final mode = (call['mode'] ?? 'VIDEO').toString();
    final isVideo = mode == 'VIDEO';

    final Color statusColor = switch (status) {
      'MISSED'  => colors.danger,
      'RINGING' => colors.warning,
      'ACTIVE'  => colors.success,
      _         => colors.textMuted,
    };

    return ListTile(
      leading: BestieAvatar(
        name: name,
        imageUrl: header['avatarUrl']?.toString(),
        isClient: isClient,
        size: 40,
      ),
      title: BestieUserName(name: name, isClient: isClient,
          style: TextStyle(fontWeight: BestieTokens.fwSemibold, color: colors.text)),
      subtitle: Row(children: [
        Icon(
          outgoing ? Icons.call_made_rounded : Icons.call_received_rounded,
          size: 12,
          color: status == 'MISSED' ? colors.danger : colors.textMuted,
        ),
        const SizedBox(width: 4),
        Text(
          '${outgoing ? "Outgoing" : "Incoming"} · $kind · ${status.toLowerCase()}',
          style: TextStyle(color: statusColor, fontSize: 12),
        ),
      ]),
      trailing: IconButton(
        icon: Icon(isVideo ? Icons.videocam_outlined : Icons.call_outlined, color: colors.brand),
        tooltip: isVideo ? 'Video call back' : 'Call back',
        onPressed: () => _ringBack(context, ref, header['id'] as String?, mode),
      ),
    );
  }

  Future<void> _ringBack(BuildContext context, WidgetRef ref, String? userId, String mode) async {
    if (userId == null) return;
    try {
      final res = await ref.read(apiProvider).initiateCall(
        participantIds: [userId],
        kind: 'ONE_TO_ONE',
      );
      final id = ((res['call'] as Map?)?['id'] ?? res['id'])?.toString();
      if (id != null && context.mounted) {
        context.go('/call/$id?mode=${mode.toLowerCase()}');
      }
    } catch (e) {
      if (context.mounted) bestieToast(context, 'Could not call',
          body: formatApiError(e), kind: BestieToastKind.error);
    }
  }
}
