import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;

import 'desktop_local_settings.dart';
import 'desktop_runtime.dart';
import 'package:mytaskking_mobile/state.dart' hide ThemeMode;
import 'package:mytaskking_mobile/widgets/profile_avatar_viewer.dart';
import 'package:mytaskking_mobile/screens/leaderboard_card.dart';

class DesktopProfileScreen extends ConsumerStatefulWidget {
  const DesktopProfileScreen({super.key});

  @override
  ConsumerState<DesktopProfileScreen> createState() =>
      _DesktopProfileScreenState();
}

class _DesktopProfileScreenState extends ConsumerState<DesktopProfileScreen> {
  bool _uploadingAvatar = false;
  bool _savingLogout = false;
  String _availability = 'ACTIVE';

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await DesktopLocalSettings.load();
      await _loadAvailability();
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadAvailability() async {
    final user = ref.read(authStoreProvider).user;
    if (user == null) return;
    try {
      final rows = await ref.read(apiProvider).presenceFor([user.id]);
      if (rows.isEmpty || !mounted) return;
      final status = (rows.first['status'] ?? 'ACTIVE').toString();
      final custom =
          (rows.first['customStatus'] ?? '').toString().toLowerCase();
      final value = custom.contains('lunch')
          ? 'LUNCH'
          : custom.contains('leave')
              ? 'LEAVE'
              : status == 'BUSY'
                  ? 'BUSY'
                  : 'ACTIVE';
      setState(() => _availability = value);
    } catch (_) {}
  }

  Future<void> _pickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null ||
          result.files.isEmpty ||
          result.files.first.bytes == null) {
        return;
      }
      final image = result.files.first;
      if (!mounted) return;
      final cropped = await showAvatarCropSheet(
        context,
        imageBytes: image.bytes!,
      );
      if (cropped == null || !mounted) return;

      setState(() => _uploadingAvatar = true);
      final asset = await ref.read(apiProvider).uploadFile(
            bytes: cropped,
            filename: _croppedFilename(image.name),
            mimeType: 'image/jpeg',
          );
      final url = asset['url']?.toString();
      if (url == null || url.isEmpty) {
        throw StateError('Upload returned no image URL');
      }
      final response = await ref.read(apiProvider).updateMyAvatar(url);
      await ref.read(authStoreProvider).updateUser(
            Map<String, dynamic>.from(response['user'] as Map),
          );
      if (mounted) {
        bestieToast(
          context,
          'Profile photo updated',
          kind: BestieToastKind.success,
        );
      }
    } catch (e) {
      if (mounted) {
        bestieToast(
          context,
          'Could not update profile photo',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _setAvailability(String value) async {
    final (status, customStatus) = switch (value) {
      'BUSY' => ('BUSY', 'Busy'),
      'LUNCH' => ('AWAY', 'Lunch time'),
      'LEAVE' => ('AWAY', 'On leave'),
      _ => ('ACTIVE', null),
    };
    setState(() => _availability = value);
    ref.read(presenceStatusProvider.notifier).state = status;
    try {
      await ref
          .read(apiProvider)
          .setPresence(status: status, customStatus: customStatus);
      ref
          .read(realtimeProvider)
          .updatePresence(status: status, customStatus: customStatus);
    } catch (e) {
      if (mounted) {
        bestieToast(
          context,
          'Could not update status',
          body: formatApiError(e),
          kind: BestieToastKind.error,
        );
      }
    }
  }

  Future<void> _pickAutoLogoutTime() async {
    final current = DesktopLocalSettings.autoLogout.value;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: const Color(0xFF0A4AA6),
              ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    setState(() => _savingLogout = true);
    try {
      await DesktopLocalSettings.saveAutoLogout(
        current.copyWith(
          minutesSinceMidnight: picked.hour * 60 + picked.minute,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingLogout = false);
    }
  }

  Future<void> _toggleAutoLogout(bool enabled) async {
    setState(() => _savingLogout = true);
    try {
      await DesktopLocalSettings.saveAutoLogout(
        DesktopLocalSettings.autoLogout.value.copyWith(enabled: enabled),
      );
    } finally {
      if (mounted) setState(() => _savingLogout = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await ref.read(apiProvider).logout();
    } finally {
      await DesktopRuntime.setSessionActive(false);
      if (mounted) context.go('/login');
    }
  }

  String _croppedFilename(String original) {
    final base = original.contains('.')
        ? original.substring(0, original.lastIndexOf('.'))
        : original;
    return '$base-cropped.jpg';
  }

  String _imageMimeType(String? extension) =>
      switch (extension?.toLowerCase()) {
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStoreProvider).user;
    final sessions = ref.watch(mySessionsProvider);
    final autoLogout = DesktopLocalSettings.autoLogout.value;
    final autoLogoutExempt = user?.role == 'ADMIN' ||
        user?.role == 'SUPER_ADMIN' ||
        user?.isPlatformSuperAdmin == true;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(BestieTokens.s4),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: BestieTokens.s4),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    ProfileAvatarViewer.show(
                      context,
                      name: user?.name ?? '--',
                      imageUrl: user?.avatarUrl,
                      isClient: user?.isClient ?? false,
                    );
                  },
                  child: BestieAvatar(
                    name: user?.name ?? '--',
                    imageUrl: user?.avatarUrl,
                    isClient: user?.isClient ?? false,
                    size: 68,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BestieUserName(
                        name: user?.name ?? '--',
                        isClient: user?.isClient ?? false,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.userId ?? '',
                        style: const TextStyle(
                          color: BestieTokens.cTextMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      BestieBadge(
                        tone: user?.isClient == true
                            ? BestieTone.client
                            : BestieTone.brand,
                        child: Text((user?.role ?? '').replaceAll('_', ' ')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: _uploadingAvatar
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_a_photo_outlined),
            title: const Text('Change profile photo'),
            subtitle: const Text('Choose an image from your computer'),
            onTap: _uploadingAvatar ? null : _pickAvatar,
          ),
          const MyScoreCard(),
          _section(context, 'Status', [
            ListTile(
              leading: Icon(
                Icons.radio_button_checked_rounded,
                color: _availabilityColor(_availability),
              ),
              title: const Text('Availability'),
              subtitle: const Text(
                'Callers will hear this status before calling.',
              ),
              trailing: DropdownButton<String>(
                value: _availability,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Available')),
                  DropdownMenuItem(value: 'BUSY', child: Text('Busy')),
                  DropdownMenuItem(value: 'LUNCH', child: Text('Lunch time')),
                  DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
                ],
                onChanged: (value) {
                  if (value != null) _setAvailability(value);
                },
              ),
            ),
          ]),
          _section(context, 'Appearance', [
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
                style: const TextStyle(
                  color: BestieTokens.cTextMuted,
                  fontSize: 12,
                ),
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
                style: TextStyle(
                  color: BestieTokens.cTextMuted,
                  fontSize: 12,
                ),
              ),
              value: ref.watch(reduceMotionProvider),
              onChanged: (v) =>
                  ref.read(reduceMotionProvider.notifier).state = v,
            ),
          ]),
          _section(context, 'Desktop safety', [
            if (autoLogoutExempt)
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Auto logout'),
                subtitle: const Text(
                  'Admin accounts stay signed in — no automatic sign-out at 6 PM.',
                  style: TextStyle(
                    color: BestieTokens.cTextMuted,
                    fontSize: 12,
                  ),
                ),
              )
            else ...[
              SwitchListTile(
                secondary: const Icon(Icons.schedule_rounded),
                title: const Text('Auto logout'),
                subtitle: Text(
                  autoLogout.enabled
                      ? 'Automatically signs out and closes the desktop app at ${autoLogout.label}.'
                      : 'Disabled. The desktop app stays signed in until you log out manually.',
                  style: const TextStyle(
                    color: BestieTokens.cTextMuted,
                    fontSize: 12,
                  ),
                ),
                value: autoLogout.enabled,
                onChanged: _savingLogout ? null : _toggleAutoLogout,
              ),
              ListTile(
                leading: _savingLogout
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.access_time_rounded),
                title: const Text('Auto logout time'),
                subtitle: Text(
                  autoLogout.label,
                  style: const TextStyle(
                    color: BestieTokens.cTextMuted,
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _savingLogout ? null : _pickAutoLogoutTime,
              ),
            ],
          ]),
          _section(context, 'Active sessions', [
            sessions.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: BestieSpinner(),
              ),
              error: (e, _) => ListTile(
                title: Text(
                  'Could not load: ${formatApiError(e)}',
                  style: const TextStyle(color: BestieTokens.cDanger),
                ),
              ),
              data: (items) => Column(
                children: [
                  for (final s in items.take(5))
                    ListTile(
                      leading: Icon(
                        _isMobile(s) ? Icons.smartphone : Icons.computer,
                        color: BestieTokens.cTextSoft,
                      ),
                      title: Text(
                        s['device'] ??
                            s['userAgent']?.toString().split(' ').last ??
                            'Unknown device',
                      ),
                      subtitle: Text(
                        '${s['platform'] ?? 'web'} · ${s['ip'] ?? 'unknown ip'}',
                      ),
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
                              child: Text(s['status'] ?? ''),
                            ),
                    ),
                  if (items.length > 1)
                    ListTile(
                      leading: const Icon(
                        Icons.logout,
                        color: BestieTokens.cDanger,
                      ),
                      title: const Text('Sign out everywhere else'),
                      onTap: () async {
                        final ok = await bestieConfirm(
                          context,
                          title: 'Sign out of all other devices?',
                          description: 'This desktop will stay signed in.',
                          confirmLabel: 'Sign out',
                        );
                        if (!ok) return;
                        try {
                          await ref.read(apiProvider).signOutEverywhere(
                            exceptSessionId: ref.read(authStoreProvider).sessionId,
                          );
                          if (context.mounted) {
                            bestieToast(
                              context,
                              'Done',
                              kind: BestieToastKind.success,
                            );
                          }
                          ref.invalidate(mySessionsProvider);
                        } catch (e) {
                          if (context.mounted) {
                            bestieToast(
                              context,
                              'Failed',
                              body: formatApiError(e),
                              kind: BestieToastKind.error,
                            );
                          }
                        }
                      },
                    ),
                ],
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: BestieTokens.s4),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: BestieTokens.cDanger,
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
              onPressed: _signOut,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BestieTokens.s4),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(BestieTokens.rMd),
          border: Border.all(color: BestieTokens.cBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: BestieTokens.cTextMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ...children,
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Color _availabilityColor(String s) => switch (s) {
        'ACTIVE' => BestieTokens.cSuccess,
        'BUSY' => BestieTokens.cDanger,
        'LUNCH' => BestieTokens.cWarning,
        'LEAVE' => BestieTokens.cAccent,
        _ => BestieTokens.cTextMuted,
      };

  bool _isMobile(Map<String, dynamic> s) {
    final platform = (s['platform'] ?? '').toString().toLowerCase();
    return platform == 'ios' || platform == 'android';
  }
}
