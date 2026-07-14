import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

bool _isOrgAdmin(BestieUser? user) {
  final role = user?.role;
  return role == 'ADMIN' || role == 'SUPER_ADMIN';
}

bool _isAcked(Map<String, dynamic> announcement, String? userId) {
  if (userId == null) return false;
  final acked = announcement['acknowledgedBy'];
  if (acked is List) return acked.map((e) => e.toString()).contains(userId);
  return announcement['ackedAt'] != null;
}

/// Announcements feed — workspace-wide messages with one-tap acknowledge.
class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  Future<void> _showCreateSheet() async {
    final created = await bestieBottomSheet<bool>(
      context,
      title: 'New announcement',
      builder: (_) => _CreateAnnouncementSheet(ref: ref),
    );
    if (created == true) {
      ref.invalidate(announcementsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final me = ref.watch(authStoreProvider).user;
    final canAnnounce = _isOrgAdmin(me);
    final announcements = ref.watch(announcementsProvider);

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.text,
        title: const Text('Announcements'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/chat');
            }
          },
        ),
        actions: [
          if (canAnnounce)
            TextButton.icon(
              onPressed: _showCreateSheet,
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: const Text('Announce'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(announcementsProvider.future),
        child: announcements.when(
          loading: () => const Center(child: BestieSpinner()),
          error: (e, _) => bestieEmptyScrollable(
            context,
            BestieEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load announcements',
              description: formatApiError(e),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return bestieEmptyScrollable(
                context,
                BestieEmptyState(
                  icon: Icons.campaign_outlined,
                  title: 'No announcements yet',
                  description: canAnnounce
                      ? 'Tap Announce above to publish a workspace update.'
                      : 'Workspace-wide updates from admins will show here.',
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final a = items[i];
                final priority =
                    (a['priority'] ?? a['tone'] ?? 'info').toString().toLowerCase();
                final accent = switch (priority) {
                  'important' => c.warning,
                  'urgent' => c.danger,
                  _ => c.brand,
                };
                final acked = _isAcked(a, me?.id);
                return Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(BestieTokens.rLg),
                    border: Border(
                      left: BorderSide(color: accent, width: 4),
                      top: BorderSide(color: c.border),
                      right: BorderSide(color: c.border),
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
                              if (ctx.mounted) {
                                bestieToast(ctx, 'Could not acknowledge',
                                    body: formatApiError(e), kind: BestieToastKind.error);
                              }
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

class _CreateAnnouncementSheet extends ConsumerStatefulWidget {
  const _CreateAnnouncementSheet({required this.ref});

  final WidgetRef ref;

  @override
  ConsumerState<_CreateAnnouncementSheet> createState() =>
      _CreateAnnouncementSheetState();
}

class _CreateAnnouncementSheetState extends ConsumerState<_CreateAnnouncementSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _scope = 'GLOBAL';
  String _priority = 'INFO';
  String? _channelId;
  bool _notify = true;
  bool _saving = false;

  static const _scopes = <String, String>{
    'GLOBAL': 'Everyone',
    'EMPLOYEES_ONLY': 'Employees only',
    'CLIENTS_ONLY': 'Clients only',
    'CHANNEL': 'Specific channel',
  };

  static const _priorities = <String, String>{
    'INFO': 'Info',
    'IMPORTANT': 'Important',
    'URGENT': 'Urgent',
  };

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      bestieToast(context, 'Fill required fields',
          body: 'Title and message are required.',
          kind: BestieToastKind.warning);
      return;
    }
    if (_scope == 'CHANNEL' && (_channelId == null || _channelId!.isEmpty)) {
      bestieToast(context, 'Pick a channel',
          body: 'Choose which channel should receive this announcement.',
          kind: BestieToastKind.warning);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.ref.read(apiProvider).createAnnouncement(
            title: title,
            body: body,
            scope: _scope,
            priority: _priority,
            channelId: _scope == 'CHANNEL' ? _channelId : null,
            notify: _notify,
          );
      if (!mounted) return;
      bestieToast(context, 'Announcement published', kind: BestieToastKind.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not publish',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final channels = ref.watch(channelsProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                enabled: !_saving,
                maxLength: 240,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _body,
                enabled: !_saving,
                minLines: 4,
                maxLines: 8,
                maxLength: 8000,
                decoration: const InputDecoration(
                  labelText: 'Message *',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _scope,
                decoration: const InputDecoration(labelText: 'Audience'),
                items: _scopes.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _scope = v ?? 'GLOBAL';
                          if (_scope != 'CHANNEL') _channelId = null;
                        }),
              ),
              if (_scope == 'CHANNEL') ...[
                const SizedBox(height: 10),
                channels.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: BestieSpinner(size: 20)),
                  ),
                  error: (_, __) => Text(
                    'Could not load channels',
                    style: TextStyle(color: c.danger, fontSize: 13),
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return Text(
                        'No channels available',
                        style: TextStyle(color: c.textMuted, fontSize: 13),
                      );
                    }
                    return DropdownButtonFormField<String>(
                      value: _channelId,
                      decoration: const InputDecoration(labelText: 'Channel *'),
                      items: items
                          .map(
                            (ch) => DropdownMenuItem(
                              value: ch['id']?.toString(),
                              child: Text((ch['name'] ?? 'Channel').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _channelId = v),
                    );
                  },
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: _priorities.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: _saving ? null : (v) => setState(() => _priority = v ?? 'INFO'),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Send push notification'),
                subtitle: Text(
                  'Notify matching users when published',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
                value: _notify,
                onChanged: _saving ? null : (v) => setState(() => _notify = v),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _publish,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_saving ? 'Publishing…' : 'Publish'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
