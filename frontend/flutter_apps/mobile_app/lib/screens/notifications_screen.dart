import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state.dart';

const _categoryLabels = {
  'chat': 'Messages',
  'task': 'Tasks',
  'call': 'Calls',
  'lead': 'Telecaller',
  'system': 'System',
};
const _categoryIcons = {
  'chat': Icons.chat_bubble_outline,
  'task': Icons.task_alt_outlined,
  'call': Icons.call_outlined,
  'lead': Icons.headset_mic_outlined,
  'system': Icons.campaign_outlined,
};

/// Local-only quiet-hours preference. Persisted in SharedPreferences so it
/// survives restarts. Used by the notifications header banner to indicate
/// the window during which the user wants the app to stay calm. (Server-
/// side suppression for push notifications will follow once the backend
/// settings endpoint takes a `quietHours` payload.)
final _quietHoursProvider =
    FutureProvider.autoDispose<_QuietHours>((_) async => _QuietHours.read());

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final stream = ref.watch(notificationsProvider);
    final quiet = ref.watch(_quietHoursProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bedtime_outlined),
            tooltip: 'Quiet hours',
            onPressed: () => _openQuietHoursSheet(quiet),
          ),
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark all read',
            onPressed: () async {
              try {
                await ref.read(apiProvider).markAllNotificationsRead();
                ref.invalidate(notificationsProvider);
              } catch (e) {
                if (context.mounted) {
                  bestieToast(context, 'Could not update',
                      body: formatApiError(e), kind: BestieToastKind.error);
                }
              }
            },
          ),
        ],
      ),
      body: stream.when(
        loading: () => const Center(child: BestieSpinner()),
        error: (e, _) => bestieEmptyScrollable(
          context,
          BestieEmptyState(
            icon: Icons.error_outline,
            iconColor: BestieTokens.cDanger,
            title: 'Couldn\'t load',
            description: formatApiError(e),
          ),
        ),
        data: (data) {
          final groups =
              (data['groups'] as Map?)?.cast<String, dynamic>() ?? const {};
          final unread = data['unread'] ?? 0;
          final children = <Widget>[
            if (quiet != null && quiet.enabled) _quietBanner(quiet),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                Text('$unread unread',
                    style: TextStyle(color: colors.textMuted)),
                const Spacer(),
                const BestieBadge(
                    tone: BestieTone.success, dot: true, child: Text('Live')),
              ]),
            ),
          ];

          if (groups.isEmpty) {
            return Column(children: [
              ...children,
              const Expanded(
                child: BestieEmptyState(
                  icon: Icons.notifications_none,
                  title: 'You\'re all caught up',
                  description:
                      'New notifications will appear here in realtime.',
                ),
              ),
            ]);
          }

          for (final entry in groups.entries) {
            children.add(Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                Icon(_categoryIcons[entry.key] ?? Icons.bolt,
                    size: 14, color: colors.textMuted),
                const SizedBox(width: 6),
                Text(
                  (_categoryLabels[entry.key] ?? entry.key).toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ]),
            ));
            children.addAll(
                ((entry.value as List).cast<Map<String, dynamic>>().map((n) {
              final unreadItem = n['readAt'] == null;
              final unreadBg = colors.isDark
                  ? colors.brand.withValues(alpha: 0.18)
                  : colors.brandSoft;
              return Container(
                color: unreadItem ? unreadBg : Colors.transparent,
                child: ListTile(
                  onTap: () => _onTapNotification(context, ref, n),
                  title: Text(n['title'] ?? '—',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(n['body'] ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textMuted, fontSize: 12)),
                  trailing: Text(_fmtTime(n['createdAt']),
                      style: TextStyle(color: colors.textFaint, fontSize: 11)),
                ),
              );
            })));
          }

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: children,
          );
        },
      ),
    );
  }

  Future<void> _onTapNotification(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> n,
  ) async {
    final id = n['id']?.toString();
    if (id != null && n['readAt'] == null) {
      try {
        await ref.read(apiProvider).markNotificationRead(id);
        ref.invalidate(notificationsProvider);
      } catch (_) {}
    }
    if (!context.mounted) return;
    final route = _routeForNotification(n);
    if (route != null) {
      context.push(route);
    }
  }

  Widget _quietBanner(_QuietHours q) {
    final colors = BestieColors.of(context);
    final inWindow = q.isActiveNow();
    final color = inWindow ? colors.brand : BestieTokens.cTextMuted;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.brandSoft,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(children: [
        Icon(Icons.bedtime_rounded, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                inWindow ? 'Quiet hours · active now' : 'Quiet hours scheduled',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Pause: ${q.fmtStart()} → ${q.fmtEnd()}',
                style: const TextStyle(
                  fontSize: 11,
                  color: BestieTokens.cTextMuted,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => _openQuietHoursSheet(q),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 28),
          ),
          child: const Text('Edit'),
        ),
      ]),
    );
  }

  Future<void> _openQuietHoursSheet(_QuietHours? current) async {
    var q =
        current ?? const _QuietHours(enabled: false, startHour: 22, endHour: 7);
    bool enabled = q.enabled;
    int startHour = q.startHour;
    int endHour = q.endHour;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          final colors = BestieColors.of(ctx);
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: BestieTokens.cBorderStrong,
                    borderRadius: BorderRadius.circular(BestieTokens.rPill),
                  ),
                ),
                Row(children: [
                  Icon(Icons.bedtime_rounded, color: colors.brand),
                  const SizedBox(width: 8),
                  const Text('Quiet hours',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Switch(
                    value: enabled,
                    onChanged: (v) => setSt(() => enabled = v),
                  ),
                ]),
                const SizedBox(height: 6),
                const Text(
                  'Pause in-app toasts during the chosen window. Push notifications still surface — silence them in your OS settings.',
                  style: TextStyle(
                      fontSize: 12,
                      color: BestieTokens.cTextMuted,
                      height: 1.4),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: _hourPicker(
                      label: 'From',
                      hour: startHour,
                      onChanged: (h) => setSt(() => startHour = h),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _hourPicker(
                      label: 'Until',
                      hour: endHour,
                      onChanged: (h) => setSt(() => endHour = h),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final saved = _QuietHours(
                        enabled: enabled,
                        startHour: startHour,
                        endHour: endHour,
                      );
                      await saved.write();
                      ref.invalidate(_quietHoursProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ]),
            ),
          );
        });
      },
    );
  }

  Widget _hourPicker({
    required String label,
    required int hour,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: BestieTokens.cTextMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(BestieTokens.rMd),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: hour, minute: 0),
            );
            if (picked != null) onChanged(picked.hour);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BestieTokens.rMd),
              border: Border.all(color: BestieTokens.cBorder),
            ),
            child: Row(children: [
              const Icon(Icons.schedule_rounded,
                  size: 16, color: BestieTokens.cTextMuted),
              const SizedBox(width: 8),
              Text(
                '${hour.toString().padLeft(2, '0')}:00',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  String _fmtTime(dynamic v) {
    final d = DateTime.tryParse('$v')?.toLocal();
    if (d == null) return '';
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Local-only persisted preference for the quiet-hours window. Stored as
/// three keys in SharedPreferences so legacy installs (where the preference
/// didn't exist yet) read defaults cleanly.
class _QuietHours {
  final bool enabled;
  final int startHour;
  final int endHour;
  const _QuietHours({
    required this.enabled,
    required this.startHour,
    required this.endHour,
  });

  static const _kEnabled = 'notif.quietHours.enabled';
  static const _kStart = 'notif.quietHours.startHour';
  static const _kEnd = 'notif.quietHours.endHour';

  static Future<_QuietHours> read() async {
    try {
      final p = await SharedPreferences.getInstance();
      return _QuietHours(
        enabled: p.getBool(_kEnabled) ?? false,
        startHour: p.getInt(_kStart) ?? 22,
        endHour: p.getInt(_kEnd) ?? 7,
      );
    } catch (_) {
      return const _QuietHours(enabled: false, startHour: 22, endHour: 7);
    }
  }

  Future<void> write() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, enabled);
    await p.setInt(_kStart, startHour);
    await p.setInt(_kEnd, endHour);
  }

  bool isActiveNow() {
    if (!enabled) return false;
    final h = DateTime.now().hour;
    // Window may wrap past midnight (e.g. 22 → 7).
    if (startHour == endHour) return false;
    if (startHour < endHour) {
      return h >= startHour && h < endHour;
    }
    return h >= startHour || h < endHour;
  }

  String fmtStart() => '${startHour.toString().padLeft(2, '0')}:00';
  String fmtEnd() => '${endHour.toString().padLeft(2, '0')}:00';
}

String? _routeForNotification(Map<String, dynamic> n) {
  final data = (n['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  final taskId = data['taskId']?.toString();
  if (taskId != null && taskId.isNotEmpty) return '/tasks/$taskId';

  final channelId = data['channelId']?.toString();
  if (channelId != null && channelId.isNotEmpty) return '/chat/$channelId';

  final callId = data['callId']?.toString();
  if (callId != null && callId.isNotEmpty) {
    final mode =
        data['mode']?.toString().toLowerCase() == 'voice' ? 'voice' : 'video';
    return '/call/$callId?mode=$mode';
  }

  final meetingSlug = data['meetingSlug']?.toString();
  if (meetingSlug != null && meetingSlug.isNotEmpty) {
    final mode =
        data['mode']?.toString().toLowerCase() == 'voice' ? 'voice' : 'video';
    return '/meeting/$meetingSlug?mode=$mode';
  }

  if ((n['kind'] ?? '').toString().toUpperCase() == 'LEAD_FOLLOWUP') {
    return '/telecaller';
  }

  return '/calendar';
}
