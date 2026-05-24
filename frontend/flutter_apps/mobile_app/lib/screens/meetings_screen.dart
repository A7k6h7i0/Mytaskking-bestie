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
      ),
      bottomNavigationBar: SizedBox(
        // Reserve the floating nav footprint so the body stops above it.
        height: 70.0 + 16 + MediaQuery.of(context).padding.bottom + 12,
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
              return BestieEmptyState(
                icon: Icons.videocam_outlined,
                title: 'No live rooms',
                description: 'Create a room to start a voice or video meeting.',
                action: FilledButton.icon(
                  onPressed: () => _create(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('New meeting'),
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
    String mode = 'VIDEO';
    await bestieBottomSheet(context, title: 'New meeting', builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        return Padding(
          padding: EdgeInsets.fromLTRB(BestieTokens.s4, 0, BestieTokens.s4,
              MediaQuery.of(ctx).viewInsets.bottom + BestieTokens.s4),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BestieTextField(label: 'Name', controller: name, hint: 'Design review'),
            const SizedBox(height: BestieTokens.s3),
            const Text('Mode', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BestieTokens.cTextSoft)),
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
            BestiePrimaryButton(
              label: 'Create room',
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                try {
                  await ref.read(apiProvider).createMeeting(name: name.text.trim(), mode: mode);
                  if (ctx.mounted) Navigator.pop(ctx);
                  ref.invalidate(meetingsProvider);
                  if (context.mounted) bestieToast(context, 'Room ready', kind: BestieToastKind.success);
                } catch (e) {
                  if (context.mounted) bestieToast(context, 'Could not create', body: formatApiError(e), kind: BestieToastKind.error);
                }
              },
            ),
          ]),
        );
      });
    });
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
