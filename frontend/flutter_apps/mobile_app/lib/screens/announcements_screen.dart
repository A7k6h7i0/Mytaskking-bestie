import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Announcements feed — workspace-wide messages with one-tap acknowledge.
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = BestieColors.of(context);
    final announcements = ref.watch(announcementsProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Announcements'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(announcementsProvider.future),
        child: announcements.when(
          loading: () => const Center(child: BestieSpinner()),
          error: (e, _) => BestieEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load announcements',
            description: formatApiError(e),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const BestieEmptyState(
                icon: Icons.campaign_outlined,
                title: 'No announcements yet',
                description: 'Workspace-wide updates from admins will show here.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final a = items[i];
                final tone = (a['tone'] ?? 'info').toString().toLowerCase();
                final accent = switch (tone) {
                  'important' => c.warning,
                  'urgent'    => c.danger,
                  _           => c.brand,
                };
                final acked = a['ackedAt'] != null;
                return Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(BestieTokens.rLg),
                    border: Border(
                      left: BorderSide(color: accent, width: 4),
                      top:    BorderSide(color: c.border),
                      right:  BorderSide(color: c.border),
                      bottom: BorderSide(color: c.border),
                    ),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.campaign_outlined, size: 16, color: accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          (a['title'] ?? '—').toString(),
                          style: TextStyle(
                            color: c.text,
                            fontWeight: BestieTokens.fwBold,
                            fontSize: 14.5,
                            letterSpacing: BestieTokens.lsSnug,
                          ),
                        ),
                      ),
                      if (acked)
                        Icon(Icons.check_circle_rounded, color: c.success, size: 18),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      (a['body'] ?? '').toString(),
                      style: TextStyle(color: c.textSoft, fontSize: 13, height: 1.4),
                    ),
                    if (!acked) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            try {
                              await ref.read(apiProvider).ackAnnouncement(a['id'] as String);
                              ref.invalidate(announcementsProvider);
                            } catch (e) {
                              if (ctx.mounted) bestieToast(ctx, 'Could not acknowledge',
                                  body: formatApiError(e), kind: BestieToastKind.error);
                            }
                          },
                          icon: const Icon(Icons.check_rounded, size: 14),
                          label: const Text('Got it'),
                        ),
                      ),
                    ],
                  ]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
