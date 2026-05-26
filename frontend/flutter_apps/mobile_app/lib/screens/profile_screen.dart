import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;

import '../state.dart' hide ThemeMode;
import 'leaderboard_card.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStoreProvider).user;
    final themeMode = ref.watch(themeModeProvider);
    final displayThemeMode =
        themeMode == core.ThemeMode.system ? core.ThemeMode.light : themeMode;
    final presence = ref.watch(presenceStatusProvider);
    final sessions = ref.watch(mySessionsProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Profile'),
      ),
      body: ListView(children: [
        // ----- identity card -----
        Padding(
          padding: const EdgeInsets.all(BestieTokens.s4),
          child: Row(children: [
            BestieAvatar(
              name: user?.name ?? '—',
              imageUrl: user?.avatarUrl,
              isClient: user?.isClient ?? false,
              size: 64,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BestieUserName(
                      name: user?.name ?? '—',
                      isClient: user?.isClient ?? false,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(user?.userId ?? '',
                        style: const TextStyle(
                            color: BestieTokens.cTextMuted, fontSize: 12)),
                    const SizedBox(height: 6),
                    BestieBadge(
                      tone: user?.isClient == true
                          ? BestieTone.client
                          : BestieTone.brand,
                      child: Text((user?.role ?? '').replaceAll('_', ' ')),
                    ),
                  ]),
            ),
          ]),
        ),

        // ----- score summary -----
        const MyScoreCard(),

        // ----- presence picker -----
        _section(context, 'Presence', [
          for (final s in const [
            'ACTIVE',
            'BUSY',
            'IN_MEETING',
            'AWAY',
            'INVISIBLE'
          ])
            RadioListTile<String>(
              value: s,
              groupValue: presence,
              title: Text(_presenceLabel(s)),
              secondary: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: _presenceColor(s), shape: BoxShape.circle),
              ),
              onChanged: (v) async {
                if (v == null) return;
                ref.read(presenceStatusProvider.notifier).state = v;
                try {
                  await ref.read(apiProvider).setPresence(status: v);
                  ref.read(realtimeProvider).updatePresence(status: v);
                } catch (e) {
                  if (context.mounted)
                    bestieToast(context, 'Couldn\'t update',
                        body: formatApiError(e), kind: BestieToastKind.error);
                }
              },
            ),
        ]),

        // ----- appearance -----
        _section(context, 'Appearance', [
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            trailing: BestieSegmentedControl<core.ThemeMode>(
              value: displayThemeMode,
              onChanged: (v) => ref.read(themeModeProvider.notifier).state = v,
              options: const [
                BestieSegmentOption(
                    value: core.ThemeMode.light,
                    label: 'Light',
                    icon: Icons.light_mode),
                BestieSegmentOption(
                    value: core.ThemeMode.dark,
                    label: 'Dark',
                    icon: Icons.dark_mode),
              ],
            ),
          ),
          // Font scale + reduce-motion give people with low vision or
          // vestibular sensitivities a more comfortable experience.
          ListTile(
            leading: const Icon(Icons.text_fields_rounded),
            title: const Text('Text size'),
            subtitle: Text(
              switch (ref.watch(fontScaleProvider)) {
                <= 0.9 => 'Compact',
                >= 1.3 => 'Largest',
                >= 1.15 => 'Larger',
                _ => 'Default',
              },
              style: const TextStyle(color: BestieTokens.cTextMuted, fontSize: 12),
            ),
            trailing: SizedBox(
              width: 220,
              child: Slider(
                min: 0.85,
                max: 1.4,
                divisions: 11,
                value: ref.watch(fontScaleProvider),
                onChanged: (v) =>
                    ref.read(fontScaleProvider.notifier).state = v,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.animation_rounded),
            title: const Text('Reduce motion'),
            subtitle: const Text(
              'Skip page-transition animations and decorative motion.',
              style: TextStyle(color: BestieTokens.cTextMuted, fontSize: 12),
            ),
            value: ref.watch(reduceMotionProvider),
            onChanged: (v) =>
                ref.read(reduceMotionProvider.notifier).state = v,
          ),
        ]),

        // ----- sessions -----
        _section(context, 'Active sessions', [
          sessions.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(16), child: BestieSpinner()),
            error: (e, _) => ListTile(
                title: Text('Couldn\'t load: ${formatApiError(e)}',
                    style: const TextStyle(color: BestieTokens.cDanger))),
            data: (items) => Column(children: [
              for (final s in items.take(5))
                ListTile(
                  leading: Icon(
                    _isMobile(s) ? Icons.smartphone : Icons.computer,
                    color: BestieTokens.cTextSoft,
                  ),
                  title: Text(s['device'] ??
                      s['userAgent']?.toString().split(' ').last ??
                      'Unknown device'),
                  subtitle: Text(
                      '${s['platform'] ?? 'web'} · ${s['ip'] ?? 'unknown ip'}'),
                  trailing: (s['status'] == 'ACTIVE')
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Revoke',
                          onPressed: () async {
                            try {
                              await ref
                                  .read(apiProvider)
                                  .revokeSession(s['id']);
                              ref.invalidate(mySessionsProvider);
                            } catch (_) {}
                          },
                        )
                      : BestieBadge(
                          tone: BestieTone.neutral,
                          child: Text(s['status'] ?? '')),
                ),
              if (items.length > 1)
                ListTile(
                  leading:
                      const Icon(Icons.logout, color: BestieTokens.cDanger),
                  title: const Text('Sign out everywhere else'),
                  onTap: () async {
                    final ok = await bestieConfirm(context,
                        title: 'Sign out of all other devices?',
                        description: 'This device will stay signed in.',
                        confirmLabel: 'Sign out');
                    if (!ok) return;
                    try {
                      await ref.read(apiProvider).signOutEverywhere();
                      if (context.mounted)
                        bestieToast(context, 'Done',
                            kind: BestieToastKind.success);
                      ref.invalidate(mySessionsProvider);
                    } catch (e) {
                      if (context.mounted)
                        bestieToast(context, 'Failed',
                            body: formatApiError(e),
                            kind: BestieToastKind.error);
                    }
                  },
                ),
            ]),
          ),
        ]),

        // ----- sign out -----
        Padding(
          padding: const EdgeInsets.all(BestieTokens.s4),
          child: OutlinedButton.icon(
            style:
                OutlinedButton.styleFrom(foregroundColor: BestieTokens.cDanger),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            onPressed: () async {
              await ref.read(apiProvider).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ),
      ]),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: BestieTokens.s3, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(BestieTokens.rMd),
          border: Border.all(color: BestieTokens.cBorder),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: BestieTokens.cTextMuted,
                  letterSpacing: 0.5),
            ),
          ),
          ...children,
          const SizedBox(height: 4),
        ]),
      ),
    );
  }

  String _presenceLabel(String s) => switch (s) {
        'ACTIVE' => 'Active',
        'BUSY' => 'Busy',
        'IN_MEETING' => 'In a meeting',
        'AWAY' => 'Away',
        'INVISIBLE' => 'Invisible',
        _ => s,
      };

  Color _presenceColor(String s) => switch (s) {
        'ACTIVE' => BestieTokens.cSuccess,
        'BUSY' => BestieTokens.cDanger,
        'IN_MEETING' => BestieTokens.cAccent,
        'AWAY' => BestieTokens.cWarning,
        'INVISIBLE' => BestieTokens.cTextFaint,
        _ => BestieTokens.cTextMuted,
      };

  bool _isMobile(Map<String, dynamic> s) {
    final p = (s['platform'] ?? '').toString().toLowerCase();
    return p == 'ios' || p == 'android';
  }
}
