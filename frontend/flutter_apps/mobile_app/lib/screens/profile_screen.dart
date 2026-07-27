import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;

import '../state.dart' hide ThemeMode;
import '../widgets/profile_avatar_viewer.dart';
import 'leaderboard_card.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploadingAvatar = false;
  bool _savingPhone = false;
  String _availability = 'ACTIVE';

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadAvailability);
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
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        imageQuality: 92,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final cropped = await showAvatarCropSheet(
        context,
        imageBytes: bytes,
      );
      if (cropped == null || !mounted) return;

      setState(() => _uploadingAvatar = true);
      final asset = await ref.read(apiProvider).uploadFile(
            bytes: cropped,
            filename: _croppedFilename(picked.name),
            mimeType: 'image/jpeg',
          );
      final url = asset['url']?.toString();
      if (url == null || url.isEmpty) throw 'Upload returned no image URL';
      final response = await ref.read(apiProvider).updateMyAvatar(url);
      await ref.read(authStoreProvider).updateUser(
            Map<String, dynamic>.from(response['user'] as Map),
          );
      if (mounted) {
        bestieToast(context, 'Profile photo updated',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not update profile photo',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    final user = ref.read(authStoreProvider).user;
    if (user?.avatarUrl == null || user!.avatarUrl!.isEmpty) return;

    final ok = await bestieConfirm(
      context,
      title: 'Remove profile photo?',
      description: 'Your account will use the default avatar again.',
      confirmLabel: 'Remove',
    );
    if (!ok) return;

    setState(() => _uploadingAvatar = true);
    try {
      final response = await ref.read(apiProvider).clearMyAvatar();
      await ref.read(authStoreProvider).updateUser(
            Map<String, dynamic>.from(response['user'] as Map),
          );
      if (mounted) {
        bestieToast(context, 'Profile photo removed',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not remove profile photo',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  String _imageMimeType(String? extension) =>
      switch (extension?.toLowerCase()) {
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };

  String _croppedFilename(String original) {
    final base = original.contains('.')
        ? original.substring(0, original.lastIndexOf('.'))
        : original;
    return '$base-cropped.jpg';
  }

  Future<void> _editPhone() async {
    final user = ref.read(authStoreProvider).user;
    final phone = await showDialog<String>(
      context: context,
      builder: (_) => _PhoneNumberDialog(initialPhone: user?.phone ?? ''),
    );
    if (phone == null) return;

    setState(() => _savingPhone = true);
    try {
      final response = await ref.read(apiProvider).updateMyProfile({
        'phone': phone.isEmpty ? null : phone,
      });
      await ref.read(authStoreProvider).updateUser(
            Map<String, dynamic>.from(response['user'] as Map),
          );
      if (mounted) {
        bestieToast(context, 'Phone number saved',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not save phone number',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _savingPhone = false);
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
        bestieToast(context, 'Could not update status',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final user = ref.watch(authStoreProvider).user;
    final sessions = ref.watch(mySessionsProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.textMuted,
        title: Text(
          'Profile',
          style: TextStyle(color: c.textMuted),
        ),
      ),
      body: ListView(children: [
        // ----- identity card -----
        Padding(
          padding: const EdgeInsets.all(BestieTokens.s4),
          child: Row(children: [
            GestureDetector(
              onTap: () {
                ProfileAvatarViewer.show(
                  context,
                  name: user?.name ?? '—',
                  imageUrl: user?.avatarUrl,
                  isClient: user?.isClient ?? false,
                );
              },
              child: BestieAvatar(
                name: user?.name ?? '—',
                imageUrl: user?.avatarUrl,
                isClient: user?.isClient ?? false,
                size: 64,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BestieUserName(
                      name: user?.name ?? '—',
                      isClient: user?.isClient ?? false,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: c.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(user?.userId ?? '',
                        style: TextStyle(
                            color: c.textMuted, fontSize: 12)),
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

        ListTile(
          leading: _uploadingAvatar
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.add_a_photo_outlined, color: c.textMuted),
          title: Text('Change profile photo',
              style: TextStyle(color: c.textMuted)),
          subtitle: Text('Choose an image and crop before upload',
              style: TextStyle(color: c.textFaint)),
          onTap: _uploadingAvatar ? null : _pickAvatar,
        ),
        if (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty)
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: c.danger),
            title: Text('Remove profile photo',
                style: TextStyle(color: c.danger)),
            subtitle: Text('Go back to the default avatar',
                style: TextStyle(color: c.textFaint)),
            onTap: _uploadingAvatar ? null : _removeAvatar,
          ),

        ListTile(
          leading: _savingPhone
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.phone_outlined, color: c.textMuted),
          title: Text('Calling phone number',
              style: TextStyle(color: c.textMuted)),
          subtitle: Text(
            (user?.phone?.isNotEmpty == true)
                ? user!.phone!
                : 'Add this to make telecaller calls work',
            style: TextStyle(color: c.textFaint),
          ),
          trailing: Icon(Icons.edit_outlined, color: c.textMuted),
          onTap: _savingPhone ? null : _editPhone,
        ),

        // ----- score summary -----
        const MyScoreCard(),

        // ----- presence picker -----
        _section(context, 'Status', [
          ListTile(
            leading: Icon(Icons.radio_button_checked_rounded,
                color: _availabilityColor(c, _availability)),
            title: Text('Availability',
                style: TextStyle(color: c.textMuted)),
            subtitle: Text('Callers will hear this status before calling.',
                style: TextStyle(color: c.textFaint)),
            trailing: DropdownButton<String>(
              value: _availability,
              underline: const SizedBox.shrink(),
              style: TextStyle(color: c.textMuted, fontSize: 14),
              dropdownColor: c.surface,
              iconEnabledColor: c.textMuted,
              items: [
                DropdownMenuItem(
                    value: 'ACTIVE',
                    child: Text('Available',
                        style: TextStyle(color: c.textMuted))),
                DropdownMenuItem(
                    value: 'BUSY',
                    child:
                        Text('Busy', style: TextStyle(color: c.textMuted))),
                DropdownMenuItem(
                    value: 'LUNCH',
                    child: Text('Lunch time',
                        style: TextStyle(color: c.textMuted))),
                DropdownMenuItem(
                    value: 'LEAVE',
                    child:
                        Text('Leave', style: TextStyle(color: c.textMuted))),
              ],
              onChanged: (value) {
                if (value != null) _setAvailability(value);
              },
            ),
          ),
        ]),

        // ----- appearance -----
        _section(context, 'Appearance', [
          // Font scale + reduce-motion give people with low vision or
          // vestibular sensitivities a more comfortable experience.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.text_fields_rounded, color: c.textMuted),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Text size',
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: c.textMuted)),
                      Text(
                        switch (ref.watch(fontScaleProvider)) {
                          <= 0.9 => 'Compact',
                          >= 1.3 => 'Largest',
                          >= 1.15 => 'Larger',
                          _ => 'Default',
                        },
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Slider(
                    min: 0.85,
                    max: 1.4,
                    divisions: 11,
                    activeColor: c.brand,
                    inactiveColor: c.brandSoft,
                    value: ref.watch(fontScaleProvider),
                    onChanged: (v) =>
                        ref.read(fontScaleProvider.notifier).state = v,
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: Icon(Icons.animation_rounded, color: c.textMuted),
            title: Text('Reduce motion',
                style: TextStyle(color: c.textMuted)),
            subtitle: Text(
              'Skip page-transition animations and decorative motion.',
              style: TextStyle(color: c.textFaint, fontSize: 12),
            ),
            activeThumbColor: Colors.white,
            activeTrackColor: c.brand,
            value: ref.watch(reduceMotionProvider),
            onChanged: (v) => ref.read(reduceMotionProvider.notifier).state = v,
          ),
        ]),

        // ----- sessions -----
        _section(context, 'Active sessions', [
          sessions.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(16), child: BestieSpinner()),
            error: (e, _) => ListTile(
                title: Text('Couldn\'t load: ${formatApiError(e)}',
                    style: TextStyle(color: c.danger))),
            data: (items) {
              final active = items
                  .where((s) =>
                      (s['status'] ?? 'ACTIVE').toString() == 'ACTIVE')
                  .toList();
              return Column(children: [
              for (final s in active.take(5))
                ListTile(
                  leading: Icon(
                    _isMobile(s) ? Icons.smartphone : Icons.computer,
                    color: c.textSoft,
                  ),
                  title: Text(
                    s['device'] ??
                        s['userAgent']?.toString().split(' ').last ??
                        'Unknown device',
                    style: TextStyle(color: c.textMuted),
                  ),
                  subtitle: Text(
                      '${s['platform'] ?? 'web'} · ${s['ip'] ?? 'unknown ip'}',
                      style: TextStyle(color: c.textFaint)),
                  trailing: (s['status'] == 'ACTIVE')
                      ? IconButton(
                          icon: Icon(Icons.close, color: c.textMuted),
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
              if (active.length > 1)
                ListTile(
                  leading: Icon(Icons.logout, color: c.danger),
                  title: Text('Sign out everywhere else',
                      style: TextStyle(color: c.danger)),
                  onTap: () async {
                    final ok = await bestieConfirm(context,
                        title: 'Sign out of all other devices?',
                        description: 'This device will stay signed in.',
                        confirmLabel: 'Sign out');
                    if (!ok) return;
                    try {
                      await ref.read(apiProvider).signOutEverywhere(
                            exceptSessionId: ref.read(authStoreProvider).sessionId,
                          );
                      if (context.mounted) {
                        bestieToast(context, 'Done',
                            kind: BestieToastKind.success);
                      }
                      ref.invalidate(mySessionsProvider);
                    } catch (e) {
                      if (context.mounted) {
                        bestieToast(context, 'Failed',
                            body: formatApiError(e),
                            kind: BestieToastKind.error);
                      }
                    }
                  },
                ),
              ]);
            },
          ),
        ]),

        // ----- sign out -----
        Padding(
          padding: const EdgeInsets.all(BestieTokens.s4),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.danger,
              side: BorderSide(color: c.danger),
            ),
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
    final c = BestieColors.of(context);
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: BestieTokens.s3, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(BestieTokens.rMd),
          border: Border.all(color: c.border),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: c.textMuted,
                  letterSpacing: 0.5),
            ),
          ),
          ...children,
          const SizedBox(height: 4),
        ]),
      ),
    );
  }

  Color _availabilityColor(BestieColors c, String s) => switch (s) {
        'ACTIVE' => c.success,
        'BUSY' => c.danger,
        'LUNCH' => c.warning,
        'LEAVE' => c.accent,
        _ => c.textMuted,
      };

  bool _isMobile(Map<String, dynamic> s) {
    final p = (s['platform'] ?? '').toString().toLowerCase();
    return p == 'ios' || p == 'android';
  }
}

class _PhoneNumberDialog extends StatefulWidget {
  const _PhoneNumberDialog({required this.initialPhone});

  final String initialPhone;

  @override
  State<_PhoneNumberDialog> createState() => _PhoneNumberDialogState();
}

class _PhoneNumberDialogState extends State<_PhoneNumberDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Calling phone number'),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.phone,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Phone number',
          hintText: '+91 98765 43210',
          helperText: 'Used as your agent number for telecaller calls.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
