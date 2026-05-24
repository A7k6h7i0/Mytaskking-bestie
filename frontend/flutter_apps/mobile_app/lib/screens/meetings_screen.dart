import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

class MeetingsScreen extends ConsumerWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BestieColors.of(context);
    final meetings = ref.watch(meetingsProvider);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.text,
        title: const Text('Meetings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.input_rounded),
            tooltip: 'Join by meeting ID',
            onPressed: () => _joinById(context),
          ),
        ],
      ),
      bottomNavigationBar: SizedBox(
        // Reserve the floating nav footprint so the body stops above it.
        height: 70.0 + MediaQuery.of(context).padding.bottom - 14,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(meetingsProvider.future),
        child: meetings.when(
          loading: () => const Center(child: BestieSpinner()),
          error: (e, _) => BestieEmptyState(
            icon: Icons.error_outline, iconColor: BestieTokens.cDanger,
            title: 'Couldn\'t load meetings', description: formatApiError(e),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_outlined, size: 64, color: colors.textFaint),
                      const SizedBox(height: 16),
                      Text('No live rooms',
                          style: TextStyle(
                              color: colors.text,
                              fontSize: 18,
                              fontWeight: BestieTokens.fwBold)),
                      const SizedBox(height: 6),
                      Text('Create a room or join one with its meeting ID.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textMuted, fontSize: 13)),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.input_rounded, size: 16),
                        label: const Text('Join by meeting ID'),
                        onPressed: () => _joinById(context),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(BestieTokens.s3),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final m = items[i];
                final mode = (m['mode'] as String? ?? 'VIDEO').toLowerCase();
                final accentColor = switch (mode) {
                  'voice'      => BestieTokens.cInfo,
                  'webinar'    => BestieTokens.cAccent,
                  'livestream' => BestieTokens.cDanger,
                  _            => BestieTokens.cBrand,
                };
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: accentColor.withOpacity(0.12),
                      child: Icon(
                        mode == 'voice' ? Icons.call_outlined : Icons.videocam_outlined,
                        color: accentColor,
                      ),
                    ),
                    title: Text(m['name'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Wrap(spacing: 6, children: [
                      BestieBadge(child: Text(mode.toUpperCase())),
                      Text(m['slug'] ?? '', style: const TextStyle(color: BestieTokens.cTextMuted, fontSize: 11)),
                    ]),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.login),
                        onPressed: () => _join(context, ref, m),
                        tooltip: 'Join',
                      ),
                      IconButton(
                        icon: const Icon(Icons.stop_circle_outlined),
                        onPressed: () => _end(context, ref, m['slug']),
                        tooltip: 'End',
                      ),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New meeting'),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final search = TextEditingController();
    String mode = 'VIDEO';
    final picked = <Map<String, dynamic>>[];
    List<Map<String, dynamic>> employees = const [];
    final api = ref.read(apiProvider);
    final me = ref.read(authStoreProvider).user;

    Future<void> loadPeople(StateSetter set, [String? q]) async {
      try {
        final res = await api.listEmployees(q: q?.trim().isEmpty ?? true ? null : q!.trim());
        // Filter out the host themselves.
        set(() => employees = res.where((e) => e['id'] != me?.id).toList());
      } catch (_) { /* leave empty */ }
    }

    await bestieBottomSheet(context, title: 'New meeting', builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        if (employees.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => loadPeople(set));
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(BestieTokens.s4, 0, BestieTokens.s4,
              MediaQuery.of(ctx).viewInsets.bottom + BestieTokens.s4),
          child: ListView(
            shrinkWrap: true,
            children: [
              BestieTextField(label: 'Name', controller: name, hint: 'Design review'),
              const SizedBox(height: BestieTokens.s3),
              const Text('Mode',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: BestieTokens.cTextSoft)),
              const SizedBox(height: 6),
              BestieSegmentedControl<String>(
                value: mode,
                onChanged: (v) => set(() => mode = v),
                options: const [
                  BestieSegmentOption(value: 'VOICE',      label: 'Voice'),
                  BestieSegmentOption(value: 'VIDEO',      label: 'Video'),
                  BestieSegmentOption(value: 'WEBINAR',    label: 'Webinar'),
                  BestieSegmentOption(value: 'LIVESTREAM', label: 'Live'),
                ],
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
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          onDeleted: () => set(() =>
                              picked.removeWhere((x) => x['id'] == p['id'])),
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: employees.where((e) => !picked.any((p) => p['id'] == e['id'])).take(20).length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final candidates = employees
                        .where((e) => !picked.any((p) => p['id'] == e['id']))
                        .take(20)
                        .toList();
                    final p = candidates[i];
                    return ListTile(
                      dense: true,
                      leading: BestieAvatar(
                        name: p['name'] ?? '?',
                        imageUrl: p['avatarUrl']?.toString(),
                        isClient: p['isClient'] ?? false,
                        size: 28,
                      ),
                      title: BestieUserName(
                        name: p['name'] ?? '',
                        isClient: p['isClient'] ?? false,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${p['userId'] ?? ''} · ${(p['role'] ?? '').toString().replaceAll('_', ' ')}',
                        style: const TextStyle(
                            color: BestieTokens.cTextMuted, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.add, size: 16),
                      onTap: () => set(() => picked.add(p)),
                    );
                  },
                ),
              ),
              const SizedBox(height: BestieTokens.s3),
              BestiePrimaryButton(
                label: picked.isEmpty
                    ? 'Create room'
                    : 'Create + invite ${picked.length}',
                onPressed: () async {
                  if (name.text.trim().isEmpty) return;
                  try {
                    final room = await api.createMeeting(
                      name: name.text.trim(),
                      mode: mode,
                    );
                    final slug = room['slug']?.toString();
                    // For each picked invitee, drop a DM with the join URL so
                    // they get a tap-to-join notification. Done sequentially
                    // to avoid the per-route rate limiter.
                    if (slug != null && picked.isNotEmpty) {
                      final link = 'https://mytaskking.com/meetings/join/$slug';
                      final body = 'You\'re invited to "${room['name']}" — $link';
                      for (final invitee in picked) {
                        try {
                          final ch = await api.createChannel(
                            kind: 'DM',
                            memberIds: [invitee['id'] as String],
                          );
                          final chId = ch['id']?.toString();
                          if (chId != null) {
                            await api.sendMessage(chId, body: body, kind: 'TEXT');
                          }
                        } catch (_) {/* keep going on individual failures */}
                      }
                    }
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
            ],
          ),
        );
      });
    });
  }

  /// Bottom sheet that takes an existing meeting slug / URL and jumps
  /// straight into the call screen. Users who get a meeting link via email
  /// or another app paste it here.
  Future<void> _joinById(BuildContext context) async {
    final slugCtl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            BestieTokens.s4, BestieTokens.s4, BestieTokens.s4,
            MediaQuery.of(ctx).viewInsets.bottom + BestieTokens.s4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Join by meeting ID',
                  style: TextStyle(
                      fontSize: 17, fontWeight: BestieTokens.fwBold)),
              const SizedBox(height: 4),
              const Text(
                'Paste the meeting ID (or the full join URL) shared with you.',
                style: TextStyle(
                    color: BestieTokens.cTextMuted, fontSize: 13),
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
                onPressed: () {
                  final raw = slugCtl.text.trim();
                  if (raw.isEmpty) return;
                  // Pull the slug out of a full URL if the user pasted one
                  // (mytaskking.com/meetings/join/<slug> or similar).
                  String slug = raw;
                  if (slug.contains('/')) {
                    slug = slug.split('?').first; // drop query string
                    slug = slug.split('/').where((s) => s.isNotEmpty).last;
                  }
                  Navigator.pop(ctx);
                  context.go('/meeting/$slug?mode=video');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _join(BuildContext context, WidgetRef ref, Map<String, dynamic> m) async {
    final slug = m['slug']?.toString();
    if (slug == null) return;
    final mode = (m['mode'] ?? 'VIDEO').toString().toLowerCase() == 'voice' ? 'voice' : 'video';
    context.go('/meeting/$slug?mode=$mode');
  }

  Future<void> _end(BuildContext context, WidgetRef ref, String slug) async {
    final ok = await bestieConfirm(context,
        title: 'End this meeting?',
        description: 'Participants will be disconnected.',
        confirmLabel: 'End meeting');
    if (!ok) return;
    try {
      await ref.read(apiProvider).endMeeting(slug);
      ref.invalidate(meetingsProvider);
    } catch (e) {
      if (context.mounted) bestieToast(context, 'Couldn\'t end', body: formatApiError(e), kind: BestieToastKind.error);
    }
  }
}
