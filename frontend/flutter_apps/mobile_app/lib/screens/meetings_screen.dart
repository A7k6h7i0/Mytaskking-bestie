import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';
import '../widgets/bestie_picker_theme.dart';
import '../windows_workspace.dart';

class MeetingsScreen extends ConsumerWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BestieColors.of(context);
    final meetings = ref.watch(meetingsProvider);
    // Clear shell nav without an empty Scaffold bottom bar (white strip).
    final readOnly = kWindowsWorkspaceNoCalls;

    final shellNavClearance =
        70.0 + 24 + MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.text,
        title: Text(readOnly ? 'Meeting history' : 'Meetings'),
        actions: [
          if (!readOnly)
            IconButton(
              icon: const Icon(Icons.input_rounded),
              tooltip: 'Join by meeting ID',
              onPressed: () => _joinById(context, ref),
            ),
        ],
      ),
      bottomNavigationBar: null,
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(meetingsProvider.future),
        child: meetings.when(
          loading: () => const Center(child: BestieSpinner()),
          error: (e, _) => bestieEmptyScrollable(
            context,
            BestieEmptyState(
              icon: Icons.error_outline,
              iconColor: BestieTokens.cDanger,
              title: 'Couldn\'t load meetings',
              description: formatApiError(e),
            ),
          ),
          data: (items) {
            final sorted = _sortedMeetings(items);
            if (sorted.isEmpty) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 24, 24, shellNavClearance),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_outlined,
                          size: 64, color: colors.textFaint),
                      const SizedBox(height: 16),
                      Text(readOnly ? 'No meeting history yet' : 'No meetings yet',
                          style: TextStyle(
                              color: colors.text,
                              fontSize: 18,
                              fontWeight: BestieTokens.fwBold)),
                      const SizedBox(height: 6),
                      Text(
                          readOnly
                              ? 'Past and live meetings appear here for reference. Join meetings from your phone.'
                              : 'Live rooms and recent ended meetings show here. Create one or join by ID.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: colors.textMuted, fontSize: 13)),
                      if (!readOnly) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.input_rounded, size: 16),
                          label: const Text('Join by meeting ID'),
                          onPressed: () => _joinById(context, ref),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }
            final me = ref.read(authStoreProvider).user;
            return ListView.separated(
              padding: EdgeInsets.fromLTRB(
                BestieTokens.s3,
                BestieTokens.s3,
                BestieTokens.s3,
                shellNavClearance,
              ),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final m = sorted[i];
                final mode = (m['mode'] as String? ?? 'VIDEO').toLowerCase();
                final ended = m['endedAt'] != null;
                final isHost = m['hostId']?.toString() == me?.id ||
                    (m['host'] as Map?)?['id']?.toString() == me?.id;
                final canEnd = !ended &&
                    (isHost ||
                        me?.role == 'ADMIN' ||
                        me?.role == 'SUPER_ADMIN');
                final accentColor = ended
                    ? colors.textMuted
                    : switch (mode) {
                        'voice' => BestieTokens.cInfo,
                        'webinar' => BestieTokens.cAccent,
                        'livestream' => BestieTokens.cDanger,
                        _ => colors.brand,
                      };
                return Card(
                  child: ListTile(
                    leading: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          backgroundColor: accentColor.withOpacity(0.12),
                          child: Icon(
                            ended
                                ? Icons.history_rounded
                                : mode == 'voice'
                                    ? Icons.call_outlined
                                    : Icons.videocam_outlined,
                            color: accentColor,
                          ),
                        ),
                        if (!ended)
                          Positioned(
                            right: -1,
                            bottom: -1,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors.surface,
                                  width: 2,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x6622C55E),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(m['name'] ?? '—',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Wrap(spacing: 6, runSpacing: 4, children: [
                      BestieBadge(
                          child: Text(ended ? 'ENDED' : 'LIVE')),
                      if (!ended)
                        BestieBadge(child: Text(mode.toUpperCase())),
                      Text(m['slug'] ?? '',
                          style: const TextStyle(
                              color: BestieTokens.cTextMuted, fontSize: 11)),
                      if ((_participantCount(m)) > 0)
                        Text(
                          '${_participantCount(m)} people',
                          style: TextStyle(
                              color: colors.textMuted, fontSize: 11),
                        ),
                    ]),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!readOnly && !ended)
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios_rounded,
                              size: 18),
                          onPressed: () => _join(context, ref, m),
                          tooltip: 'Join meeting',
                        )
                      else
                        IconButton(
                          icon: Icon(Icons.info_outline,
                              color: colors.textMuted),
                          onPressed: () =>
                              _showMeetingDetails(context, m, colors),
                          tooltip: 'Meeting details',
                        ),
                      if (!readOnly && canEnd)
                        IconButton(
                          icon: const Icon(Icons.stop_circle_outlined),
                          onPressed: () =>
                              _end(context, ref, m['slug']?.toString() ?? ''),
                          tooltip: 'End for everyone',
                        ),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: readOnly
          ? null
          : Padding(
        padding: EdgeInsets.only(bottom: shellNavClearance - 24),
        child: FloatingActionButton.extended(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('New meeting'),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    if (kWindowsWorkspaceNoCalls) return;
    final name = TextEditingController();
    final search = TextEditingController();
    String mode = 'VIDEO';
    final picked = <Map<String, dynamic>>[];
    List<Map<String, dynamic>> employees = const [];
    DateTime? scheduledAt;
    final api = ref.read(apiProvider);
    final me = ref.read(authStoreProvider).user;

    Future<void> loadPeople(StateSetter set, [String? q]) async {
      try {
        final res = await api.listEmployees(
            q: q?.trim().isEmpty ?? true ? null : q!.trim());
        // Filter out the host themselves.
        set(() => employees = res.where((e) => e['id'] != me?.id).toList());
      } catch (_) {/* leave empty */}
    }

    await bestieBottomSheet(context, title: 'New meeting', builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        if (employees.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => loadPeople(set));
        }
        final sheetColors = BestieColors.of(ctx);
        // Two-zone layout: the form scrolls in the top zone, the Create
        // button is pinned in the bottom zone. Earlier the button sat at
        // the end of a long ListView and a long invitee list pushed it
        // off-screen.
        final candidates = employees
            .where((e) => !picked.any((p) => p['id'] == e['id']))
            .take(20)
            .toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    BestieTokens.s4, 0, BestieTokens.s4, BestieTokens.s2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BestieTextField(
                        label: 'Name', controller: name, hint: 'Design review'),
                    const SizedBox(height: BestieTokens.s3),
                    Text('Mode',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: sheetColors.textSoft)),
                    const SizedBox(height: 6),
                    BestieSegmentedControl<String>(
                      value: mode,
                      onChanged: (v) => set(() => mode = v),
                      options: const [
                        BestieSegmentOption(value: 'VOICE', label: 'Voice'),
                        BestieSegmentOption(value: 'VIDEO', label: 'Video'),
                        BestieSegmentOption(value: 'WEBINAR', label: 'Webinar'),
                        BestieSegmentOption(value: 'LIVESTREAM', label: 'Live'),
                      ],
                    ),
                    const SizedBox(height: BestieTokens.s3),
                    Text('Schedule (optional)',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: sheetColors.textSoft)),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      icon: Icon(
                        scheduledAt == null
                            ? Icons.calendar_today_outlined
                            : Icons.event_available_rounded,
                        size: 16,
                      ),
                      label: Text(
                        scheduledAt == null
                            ? 'Starts now (tap to schedule)'
                            : _fmtScheduled(scheduledAt!),
                      ),
                      onPressed: () async {
                        final initial = scheduledAt ??
                            DateTime.now().add(const Duration(hours: 1));
                        final now = DateTime.now();
                        final pickedResult = await bestiePickScheduledDateTime(
                          ctx,
                          initial: initial.isBefore(now) ? now : initial,
                          firstDate: DateTime(now.year, now.month, now.day),
                          lastDate: now.add(const Duration(days: 365 * 2)),
                        );
                        if (pickedResult.cancelled) return;
                        if (pickedResult.value == null) {
                          if (ctx.mounted) {
                            bestieToast(
                              ctx,
                              'Pick a future time',
                              kind: BestieToastKind.warning,
                            );
                          }
                          return;
                        }
                        set(() => scheduledAt = pickedResult.value);
                      },
                    ),
                    if (scheduledAt != null)
                      TextButton.icon(
                        icon: const Icon(Icons.close_rounded, size: 14),
                        label: const Text('Clear schedule'),
                        onPressed: () => set(() => scheduledAt = null),
                      ),
                    const SizedBox(height: BestieTokens.s3),
                    const Text('Invite from organization',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: BestieTokens.cTextSoft)),
                    if (picked.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final p in picked)
                              InputChip(
                                avatar: BestieAvatar(
                                  name: p['name'] ?? '?',
                                  imageUrl: p['avatarUrl']?.toString(),
                                  isClient: p['isClient'] ?? false,
                                  size: 18,
                                ),
                                label: Text(
                                  p['name']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                                onDeleted: () => set(() => picked
                                    .removeWhere((x) => x['id'] == p['id'])),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    BestieTextField(
                      label: 'Search people',
                      controller: search,
                      icon: Icons.search,
                      onChanged: (v) => loadPeople(set, v),
                    ),
                    const SizedBox(height: 6),
                    // Inline list — no inner scroll, the outer
                    // SingleChildScrollView owns scrolling so the Create
                    // button stays pinned no matter how many people show.
                    for (var i = 0; i < candidates.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        leading: BestieAvatar(
                          name: candidates[i]['name'] ?? '?',
                          imageUrl: candidates[i]['avatarUrl']?.toString(),
                          isClient: candidates[i]['isClient'] ?? false,
                          size: 28,
                        ),
                        title: BestieUserName(
                          name: candidates[i]['name'] ?? '',
                          isClient: candidates[i]['isClient'] ?? false,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${candidates[i]['userId'] ?? ''} · ${(candidates[i]['role'] ?? '').toString().replaceAll('_', ' ')}',
                          style: const TextStyle(
                              color: BestieTokens.cTextMuted, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.add, size: 16),
                        onTap: () => set(() => picked.add(candidates[i])),
                      ),
                    ],
                    const SizedBox(height: BestieTokens.s3),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                BestieTokens.s4,
                8,
                BestieTokens.s4,
                MediaQuery.of(ctx).viewInsets.bottom + BestieTokens.s4,
              ),
              child: BestiePrimaryButton(
                label: picked.isEmpty
                    ? 'Create room'
                    : 'Create + invite ${picked.length}',
                onPressed: () async {
                  if (name.text.trim().isEmpty) return;
                  if (scheduledAt != null &&
                      scheduledAt!.isBefore(DateTime.now())) {
                    bestieToast(
                      ctx,
                      'Meeting cannot be scheduled in the past',
                      kind: BestieToastKind.warning,
                    );
                    return;
                  }
                  try {
                    // The backend now handles invite fan-out (socket
                    // ringer + FCM push) when we pass participantIds.
                    await api.createMeeting(
                      name: name.text.trim(),
                      mode: mode,
                      participantIds:
                          picked.map((p) => p['id'] as String).toList(),
                      scheduledAt: scheduledAt,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    ref.invalidate(meetingsProvider);
                    if (context.mounted) {
                      bestieToast(
                        context,
                        picked.isEmpty
                            ? 'Room ready'
                            : 'Room ready — invited ${picked.length}',
                        kind: BestieToastKind.success,
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      bestieToast(context, 'Could not create',
                          body: formatApiError(e), kind: BestieToastKind.error);
                    }
                  }
                },
              ),
            ),
          ],
        );
      });
    });
  }

  /// Bottom sheet that takes an existing meeting slug / URL and jumps
  /// straight into the call screen. Users who get a meeting link via email
  /// or another app paste it here.
  /// Formats a scheduled-meeting start time — "Today 4:00 PM", "Tomorrow
  /// 10:30 AM", or "Mon 12 Mar · 9:00 AM" depending on how far out it is.
  String _fmtScheduled(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    const dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final when = DateTime(dt.year, dt.month, dt.day);
    final daysAway = when.difference(today).inDays;
    final h12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final mm = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final clock = '$h12:$mm $ampm';
    if (daysAway == 0) return 'Today $clock';
    if (daysAway == 1) return 'Tomorrow $clock';
    if (daysAway > 0 && daysAway < 7) {
      return '${dow[dt.weekday - 1]} $clock';
    }
    return '${dt.day} ${months[dt.month - 1]} · $clock';
  }

  Future<void> _joinById(BuildContext context, WidgetRef ref) async {
    if (kWindowsWorkspaceNoCalls) return;
    final slugCtl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            BestieTokens.s4,
            BestieTokens.s4,
            BestieTokens.s4,
            MediaQuery.of(ctx).viewInsets.bottom + BestieTokens.s4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Join by meeting ID',
                  style:
                      TextStyle(fontSize: 17, fontWeight: BestieTokens.fwBold)),
              const SizedBox(height: 4),
              const Text(
                'Paste the meeting ID (or the full join URL) shared with you.',
                style: TextStyle(color: BestieTokens.cTextMuted, fontSize: 13),
              ),
              const SizedBox(height: BestieTokens.s3),
              BestieTextField(
                label: 'Meeting ID or URL',
                controller: slugCtl,
                hint: 'e.g. b4QcZ8oN1V or https://mytaskking.com/…/abc123',
              ),
              const SizedBox(height: BestieTokens.s3),
              BestiePrimaryButton(
                label: 'Join',
                icon: Icons.login_rounded,
                onPressed: () async {
                  final raw = slugCtl.text.trim();
                  if (raw.isEmpty) return;
                  String slug = raw;
                  if (slug.contains('/')) {
                    slug = slug.split('?').first;
                    slug = slug.split('/').where((s) => s.isNotEmpty).last;
                  }
                  try {
                    final room =
                        await ref.read(apiProvider).get('/meetings/$slug');
                    if (!context.mounted) return;
                    if (room['endedAt'] != null) {
                      bestieToast(context, 'Meeting already ended',
                          kind: BestieToastKind.info);
                      return;
                    }
                    final mode =
                        (room['mode'] ?? 'VIDEO').toString().toLowerCase() ==
                                'voice'
                            ? 'voice'
                            : 'video';
                    Navigator.pop(ctx);
                    context.go('/meeting/$slug?mode=$mode');
                  } catch (e) {
                    if (!context.mounted) return;
                    bestieToast(
                      context,
                      'Couldn\'t join',
                      body: formatApiError(e),
                      kind: BestieToastKind.error,
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _join(
      BuildContext context, WidgetRef ref, Map<String, dynamic> m) async {
    if (kWindowsWorkspaceNoCalls) return;
    final slug = m['slug']?.toString();
    if (slug == null) return;
    if (m['endedAt'] != null) {
      bestieToast(context, 'Meeting already ended',
          kind: BestieToastKind.info);
      return;
    }
    final mode = (m['mode'] ?? 'VIDEO').toString().toLowerCase() == 'voice'
        ? 'voice'
        : 'video';
    context.go('/meeting/$slug?mode=$mode');
  }

  Future<void> _end(BuildContext context, WidgetRef ref, String slug) async {
    if (slug.isEmpty) return;
    final ok = await bestieConfirm(context,
        title: 'End this meeting?',
        description: 'Participants will be disconnected.',
        confirmLabel: 'End meeting');
    if (!ok) return;
    try {
      await ref.read(apiProvider).endMeeting(slug);
      ref.invalidate(meetingsProvider);
    } catch (e) {
      if (context.mounted)
        bestieToast(context, 'Couldn\'t end',
            body: formatApiError(e), kind: BestieToastKind.error);
    }
  }

  /// Live rooms first, then newest `createdAt` at the top (API order varies).
  static List<Map<String, dynamic>> _sortedMeetings(
      List<Map<String, dynamic>> items) {
    final copy = List<Map<String, dynamic>>.from(items);
    copy.sort((a, b) {
      final aLive = a['endedAt'] == null;
      final bLive = b['endedAt'] == null;
      if (aLive != bLive) return aLive ? -1 : 1;

      DateTime when(Map<String, dynamic> m) =>
          DateTime.tryParse(m['createdAt']?.toString() ?? '') ??
          DateTime.tryParse(m['scheduledAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);

      return when(b).compareTo(when(a));
    });
    return copy;
  }

  static int _participantCount(Map<String, dynamic> m) {
    final count = m['_count'];
    if (count is Map) {
      final n = count['participants'];
      if (n is int) return n;
      return int.tryParse('$n') ?? 0;
    }
    final n = m['participantCount'];
    if (n is int) return n;
    return int.tryParse('$n') ?? 0;
  }

  static void _showMeetingDetails(
    BuildContext context,
    Map<String, dynamic> m,
    BestieColors colors,
  ) {
    final ended = m['endedAt']?.toString() ?? '';
    final created = m['createdAt']?.toString() ?? '';
    final isLive = m['endedAt'] == null;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                m['name']?.toString() ?? 'Meeting',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: BestieTokens.fwBold,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 10),
              Text('Status: ${isLive ? 'Live' : 'Ended'}',
                  style: TextStyle(color: colors.textMuted, fontSize: 13)),
              Text('Mode: ${m['mode'] ?? 'VIDEO'}',
                  style: TextStyle(color: colors.textMuted, fontSize: 13)),
              if ((m['slug'] ?? '').toString().isNotEmpty)
                Text('ID: ${m['slug']}',
                    style: TextStyle(color: colors.textMuted, fontSize: 13)),
              if (created.isNotEmpty)
                Text('Started: ${created.replaceFirst('T', ' ')}',
                    style: TextStyle(color: colors.textMuted, fontSize: 13)),
              if (ended.isNotEmpty)
                Text('Ended: ${ended.replaceFirst('T', ' ')}',
                    style: TextStyle(color: colors.textMuted, fontSize: 13)),
              Text(
                'People: ${_participantCount(m)}',
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
