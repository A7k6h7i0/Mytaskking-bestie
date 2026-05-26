import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;

import '../state.dart' hide ThemeMode;

/// App-level settings with a light/dark theme toggle and links to the rest of
/// the workspace. Secondary screens open with push so Android back returns here
/// instead of closing the app.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<bool> _handleBack(BuildContext context) async {
    final router = GoRouter.of(context);
    if (router.canPop()) return true;
    context.go('/dashboard');
    return false;
  }

  void _openRoute(BuildContext context, String route) {
    context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final mode = ref.watch(themeModeProvider);
    final displayMode =
        mode == core.ThemeMode.system ? core.ThemeMode.light : mode;
    final user = ref.watch(authStoreProvider).user;
    final canPop = GoRouter.of(context).canPop();

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack(context);
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: c.surface,
          foregroundColor: c.text,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: () async {
              if (await _handleBack(context) && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: const Text('Settings'),
        ),
        body: ListView(
          children: [
            if (user != null) _Identity(user: user, colors: c),
            _SectionLabel('Appearance', colors: c),
            Container(
              color: c.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: BestieSegmentedControl<core.ThemeMode>(
                value: displayMode,
                onChanged: (v) =>
                    ref.read(themeModeProvider.notifier).state = v,
                options: const [
                  BestieSegmentOption(
                    value: core.ThemeMode.light,
                    label: 'Light',
                    icon: Icons.light_mode_rounded,
                  ),
                  BestieSegmentOption(
                    value: core.ThemeMode.dark,
                    label: 'Dark',
                    icon: Icons.dark_mode_rounded,
                  ),
                ],
              ),
            ),
            _SectionLabel('Workspace', colors: c),
            if (!(user?.isClient ?? false))
              _SettingTile(
                colors: c,
                icon: Icons.access_time_filled_rounded,
                label: 'Workday (check-in / lunch / logout)',
                onTap: () => _openRoute(context, '/attendance'),
              ),
            _SettingTile(
              colors: c,
              icon: Icons.campaign_outlined,
              label: 'Announcements',
              onTap: () => _openRoute(context, '/announcements'),
            ),
            _SettingTile(
              colors: c,
              icon: Icons.bookmark_outline_rounded,
              label: 'Saved items',
              onTap: () => _openRoute(context, '/saved'),
            ),
            _SettingTile(
              colors: c,
              icon: Icons.event_outlined,
              label: 'Calendar',
              onTap: () => _openRoute(context, '/calendar'),
            ),
            _SettingTile(
              colors: c,
              icon: Icons.history_rounded,
              label: 'Call history',
              onTap: () => _openRoute(context, '/calls'),
            ),
            _SectionLabel('People', colors: c),
            if (!(user?.isClient ?? false))
              _SettingTile(
                colors: c,
                icon: Icons.people_outline_rounded,
                label: 'Employees',
                onTap: () => _openRoute(context, '/employees'),
              ),
            if (user?.role == 'ADMIN' ||
                user?.role == 'SUPER_ADMIN' ||
                user?.role == 'MANAGER')
              _SettingTile(
                colors: c,
                icon: Icons.business_center_outlined,
                label: 'Clients',
                onTap: () => _openRoute(context, '/clients'),
              ),
            if (user?.role == 'TELECALLER' ||
                user?.role == 'ADMIN' ||
                user?.role == 'SUPER_ADMIN')
              _SettingTile(
                colors: c,
                icon: Icons.headset_mic_outlined,
                label: 'Telecaller leads',
                onTap: () => _openRoute(context, '/telecaller'),
              ),
            _SectionLabel('Security', colors: c),
            _SettingTile(
              colors: c,
              icon: Icons.devices_outlined,
              label: 'Active sessions',
              onTap: () => _openRoute(context, '/sessions'),
            ),
            _SettingTile(
              colors: c,
              icon: Icons.logout_rounded,
              label: 'Sign out',
              danger: true,
              onTap: () async {
                final ok = await bestieConfirm(
                  context,
                  title: 'Sign out?',
                  confirmLabel: 'Sign out',
                );
                if (!ok) return;
                await ref.read(authStoreProvider).clear();
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  final dynamic user;
  final BestieColors colors;
  const _Identity({required this.user, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: colors.surface,
      child: Row(
        children: [
          BestieAvatar(
            name: user.name,
            imageUrl: user.avatarUrl,
            isClient: user.isClient,
            size: 56,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BestieUserName(
                  name: user.name,
                  isClient: user.isClient,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: BestieTokens.fwBold,
                    color: colors.text,
                  ),
                ),
                Text(
                  user.userId ?? '',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                BestieBadge(
                  tone: user.isClient ? BestieTone.client : BestieTone.brand,
                  child: Text((user.role ?? '').replaceAll('_', ' ')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final BestieColors colors;
  const _SectionLabel(this.label, {required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: BestieTokens.fwBold,
          color: colors.textMuted,
          letterSpacing: BestieTokens.lsEyebrow,
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final BestieColors colors;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _SettingTile({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? colors.danger : colors.text;
    return Material(
      color: colors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon,
                  color: danger ? colors.danger : colors.textSoft, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: BestieTokens.fwMedium,
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: colors.textFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
