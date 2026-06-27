import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;

import '../state.dart' hide ThemeMode;

/// App-level settings and links to the rest of the workspace.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _buzzerEnabled = true;
  String _headOfficeName = 'HQ India';
  String? _buzzerSoundUrl;
  String? _ringingSoundUrl;
  String? _uploadingSound;

  @override
  void initState() {
    super.initState();
    _loadBuzzerSetting();
  }

  Future<void> _loadBuzzerSetting() async {
    try {
      final data = await ref.read(apiProvider).settingsScope(scope: 'calls');
      final calls = (data['calls'] as Map?)?.cast<String, dynamic>();
      if (mounted && calls != null) {
        setState(() {
          _buzzerEnabled = calls['emergencyBuzzerEnabled'] is bool
              ? calls['emergencyBuzzerEnabled'] as bool
              : true;
          _headOfficeName = (calls['headOfficeName'] ?? 'HQ India').toString();
          _buzzerSoundUrl = calls['emergencyBuzzerSoundUrl']?.toString();
          _ringingSoundUrl = calls['ringingSoundUrl']?.toString();
        });
      }
    } catch (_) {}
  }

  Future<void> _uploadCallSound({
    required String key,
    required String label,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null ||
          result.files.isEmpty ||
          result.files.first.bytes == null) {
        return;
      }
      final file = result.files.first;
      setState(() => _uploadingSound = key);
      final asset = await ref.read(apiProvider).uploadFile(
            bytes: file.bytes!,
            filename: file.name,
            mimeType: 'audio/mpeg',
          );
      final url = asset['url']?.toString();
      if (url == null || url.isEmpty) throw 'Upload returned no audio URL';
      await ref
          .read(apiProvider)
          .setSetting(scope: 'calls', key: key, value: url);
      if (!mounted) return;
      setState(() {
        if (key == 'emergencyBuzzerSoundUrl') _buzzerSoundUrl = url;
        if (key == 'ringingSoundUrl') _ringingSoundUrl = url;
      });
      bestieToast(context, '$label updated', kind: BestieToastKind.success);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not upload $label',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _uploadingSound = null);
    }
  }

  Future<void> _editHeadOffice() async {
    final controller = TextEditingController(text: _headOfficeName);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Head office name'),
        content:
            TextField(controller: controller, autofocus: true, maxLength: 80),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    try {
      await ref
          .read(apiProvider)
          .setSetting(scope: 'calls', key: 'headOfficeName', value: value);
      if (mounted) setState(() => _headOfficeName = value);
    } catch (e) {
      if (mounted)
        bestieToast(context, 'Could not update head office',
            body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  Future<void> _toggleBuzzer() async {
    final next = !_buzzerEnabled;
    try {
      await ref.read(apiProvider).setSetting(
            scope: 'calls',
            key: 'emergencyBuzzerEnabled',
            value: next,
          );
      if (mounted) setState(() => _buzzerEnabled = next);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not update buzzer setting',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  static const _shellRoutes = {
    '/chat',
    '/dashboard',
    '/tasks',
    '/attendance',
    '/meetings',
    '/notifications',
    '/profile',
  };

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/chat');
  }

  void _openRoute(BuildContext context, String route) {
    if (_shellRoutes.contains(route)) {
      context.go(route);
      return;
    }
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final user = ref.watch(authStoreProvider).user;
    final canPop = context.canPop();

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _goBack(context);
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
            onPressed: () => _goBack(context),
          ),
          title: const Text('Settings'),
        ),
        body: ListView(
          children: [
            if (user != null) _Identity(user: user, colors: c),
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
            if (user?.role == 'SUPER_ADMIN')
              _SettingTile(
                colors: c,
                icon: Icons.apartment_rounded,
                label: 'Organisations',
                onTap: () => _openRoute(context, '/organizations'),
              ),
            if (user?.role == 'ADMIN' || user?.role == 'SUPER_ADMIN')
              _SettingTile(
                colors: c,
                icon: Icons.download_for_offline_outlined,
                label: 'Call recordings',
                onTap: () => _openRoute(context, '/recordings'),
              ),
            if (user?.role == 'ADMIN' || user?.role == 'SUPER_ADMIN')
              _SettingTile(
                colors: c,
                icon: Icons.campaign_rounded,
                label:
                    'Emergency buzzer: ${_buzzerEnabled ? 'enabled' : 'disabled'}',
                onTap: _toggleBuzzer,
              ),
            if (user?.role == 'ADMIN' || user?.role == 'SUPER_ADMIN')
              _SettingTile(
                colors: c,
                icon: Icons.warning_amber_rounded,
                label: _uploadingSound == 'emergencyBuzzerSoundUrl'
                    ? 'Uploading emergency buzzer MP3...'
                    : 'Emergency buzzer sound: ${_buzzerSoundUrl == null ? 'default alarm' : 'custom MP3'}',
                onTap: () => _uploadCallSound(
                  key: 'emergencyBuzzerSoundUrl',
                  label: 'emergency buzzer sound',
                ),
              ),
            if (user?.role == 'ADMIN' || user?.role == 'SUPER_ADMIN')
              _SettingTile(
                colors: c,
                icon: Icons.music_note_rounded,
                label: _uploadingSound == 'ringingSoundUrl'
                    ? 'Uploading ringing MP3...'
                    : 'Ringing sound: ${_ringingSoundUrl == null ? 'device default' : 'custom MP3'}',
                onTap: () => _uploadCallSound(
                  key: 'ringingSoundUrl',
                  label: 'ringing sound',
                ),
              ),
            if (user?.role == 'ADMIN' || user?.role == 'SUPER_ADMIN')
              _SettingTile(
                colors: c,
                icon: Icons.business_rounded,
                label: 'Head office: $_headOfficeName',
                onTap: _editHeadOffice,
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
                await ref.read(apiProvider).logout();
                if (context.mounted) context.go('/login');
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
