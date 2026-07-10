import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Active device sessions — security view with per-session revoke and a
/// "sign out everywhere" nuclear option.
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final sessions = ref.watch(mySessionsProvider);

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              final desktop = defaultTargetPlatform == TargetPlatform.windows ||
                  defaultTargetPlatform == TargetPlatform.linux ||
                  defaultTargetPlatform == TargetPlatform.macOS;
              context.go(desktop ? '/dashboard' : '/chat');
            }
          },
        ),
        title: const Text('Sessions'),
        actions: [
          TextButton.icon(
            onPressed: () => _signOutAll(context, ref),
            icon: Icon(Icons.logout_rounded, size: 16, color: c.danger),
            label: Text('Sign out all',
                style: TextStyle(
                    color: c.danger, fontWeight: BestieTokens.fwSemibold)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(mySessionsProvider.future),
        child: sessions.when(
          loading: () => const Center(child: BestieSpinner()),
          error: (e, _) => BestieEmptyState(
            icon: Icons.error_outline_rounded,
            iconColor: c.danger,
            title: 'Could not load sessions',
            description: formatApiError(e),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const BestieEmptyState(
                icon: Icons.devices_outlined,
                title: 'No active sessions',
                description: 'You are not signed in anywhere — odd.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, indent: 56, color: c.border),
              itemBuilder: (ctx, i) {
                final s = items[i];
                final platform =
                    (s['platform'] ?? 'unknown').toString().toLowerCase();
                final mobile = platform == 'ios' || platform == 'android';
                final isCurrent = s['current'] == true;
                return ListTile(
                  leading: Icon(
                    mobile ? Icons.smartphone_rounded : Icons.computer_rounded,
                    color: isCurrent ? c.brand : c.textMuted,
                  ),
                  title: Text(
                    _deviceLabel(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: BestieTokens.fwSemibold, color: c.text),
                  ),
                  subtitle: Text(
                    [
                      if (s['ip'] != null) s['ip'],
                      if (s['lastSeenAt'] != null)
                        'active ${_relative(s['lastSeenAt'].toString())}',
                    ].join(' · '),
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                  trailing: isCurrent
                      ? BestieBadge(
                          tone: BestieTone.success,
                          child: const Text('THIS DEVICE'))
                      : IconButton(
                          icon: Icon(Icons.close_rounded, color: c.danger),
                          tooltip: 'Revoke',
                          onPressed: () =>
                              _revoke(context, ref, s['id'] as String),
                        ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, String id) async {
    final ok = await bestieConfirm(context,
        title: 'Sign out this device?',
        description: 'The device will be signed out immediately.',
        confirmLabel: 'Sign out');
    if (!ok) return;
    try {
      await ref.read(apiProvider).revokeSession(id);
      ref.invalidate(mySessionsProvider);
    } catch (e) {
      if (context.mounted)
        bestieToast(context, 'Could not revoke',
            body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  Future<void> _signOutAll(BuildContext context, WidgetRef ref) async {
    final ok = await bestieConfirm(context,
        title: 'Sign out everywhere?',
        description:
            'You will need to sign in again on every device, including this one.',
        confirmLabel: 'Sign out all');
    if (!ok) return;
    try {
      await ref.read(apiProvider).signOutEverywhere();
      ref.invalidate(mySessionsProvider);
    } catch (e) {
      if (context.mounted)
        bestieToast(context, 'Could not sign out',
            body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  String _relative(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

String _deviceLabel(Map<String, dynamic> s) {
  final raw = (s['device'] ?? '').toString().trim();
  if (raw.isNotEmpty && raw.toLowerCase() != 'dart:io') return raw;
  final platform = (s['platform'] ?? '').toString().toLowerCase();
  return switch (platform) {
    'android' => 'Android phone',
    'ios' => 'iPhone / iPad',
    'windows' => 'Windows PC',
    'macos' => 'Mac',
    'linux' => 'Linux PC',
    'web' => 'Web browser',
    _ => 'MyTaskKing mobile app',
  };
}
