import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_mobile/screens.dart';

final workActivitySummaryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, date) async {
  final api = ref.watch(apiProvider);
  return api.workActivitySummary(date: date, timezone: 'Asia/Kolkata');
});

final workActivityClipsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, userId) async {
  final api = ref.watch(apiProvider);
  return api.workActivityClips(userId: userId, pageSize: 100);
});

class WorkActivityScreen extends ConsumerStatefulWidget {
  const WorkActivityScreen({super.key});

  @override
  ConsumerState<WorkActivityScreen> createState() => _WorkActivityScreenState();
}

class _WorkActivityScreenState extends ConsumerState<WorkActivityScreen> {
  late DateTime _date = DateTime.now();
  String? _selectedUserId;

  String get _dateKey {
    final local = _date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _openClip(String url) async {
    if (url.trim().isEmpty) return;
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
      return;
    }
    await Process.start('xdg-open', [url]);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authStoreProvider).user;
    final isAdmin = me?.role == 'ADMIN' || me?.role == 'SUPER_ADMIN';
    final colors = BestieColors.of(context);
    final summary = ref.watch(workActivitySummaryProvider(_dateKey));

    if (!isAdmin) {
      return const BestieEmptyState(
        icon: Icons.lock_outline,
        title: 'Admin access only',
        description: 'Work activity is available to admins and super admins.',
      );
    }

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('Work Activity'),
        actions: [
          IconButton(
            tooltip: 'Pick date',
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(workActivitySummaryProvider(_dateKey));
              if (_selectedUserId != null) {
                ref.invalidate(workActivityClipsProvider(_selectedUserId!));
              }
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: summary.when(
        loading: () => const Center(child: BestieSpinner()),
        error: (e, _) => BestieEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load activity',
          description: formatApiError(e),
        ),
        data: (data) {
          final items =
              (data['items'] as List? ?? const []).cast<Map<String, dynamic>>();
          return Row(
            children: [
              SizedBox(
                width: 430,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.monitor_heart_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _dateKey,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final row = items[index];
                          final user =
                              (row['user'] as Map).cast<String, dynamic>();
                          final selected = user['id'] == _selectedUserId;
                          return _EmployeeActivityTile(
                            row: row,
                            selected: selected,
                            onTap: () => setState(
                              () => _selectedUserId = user['id']?.toString(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              VerticalDivider(width: 1, color: colors.border),
              Expanded(
                child: _selectedUserId == null
                    ? const BestieEmptyState(
                        icon: Icons.visibility_outlined,
                        title: 'Select an employee',
                        description: 'Open View Track to see clips and notes.',
                      )
                    : _TrackHistory(
                        userId: _selectedUserId!,
                        onOpenClip: _openClip,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmployeeActivityTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool selected;
  final VoidCallback onTap;

  const _EmployeeActivityTile({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final user = (row['user'] as Map).cast<String, dynamic>();
    final status = row['status']?.toString() ?? 'Working';
    return Material(
      color: selected ? colors.brandSoft : colors.surface,
      borderRadius: BorderRadius.circular(BestieTokens.rMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestieTokens.rMd),
            border: Border.all(
              color: selected ? colors.brand : colors.border,
            ),
          ),
          child: Row(
            children: [
              BestieAvatar(
                name: user['name']?.toString() ?? 'Employee',
                imageUrl: user['avatarUrl']?.toString(),
                isClient: false,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BestieUserName(
                      name: user['name']?.toString() ?? 'Employee',
                      isClient: false,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_hours(row['workingSeconds'])} worked',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  BestieBadge(
                    tone: status == 'Working'
                        ? BestieTone.success
                        : BestieTone.neutral,
                    child: Text(status),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${row['clipCount'] ?? 0} clips',
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('View Track'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackHistory extends ConsumerWidget {
  final String userId;
  final Future<void> Function(String url) onOpenClip;

  const _TrackHistory({required this.userId, required this.onOpenClip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BestieColors.of(context);
    final clips = ref.watch(workActivityClipsProvider(userId));
    return clips.when(
      loading: () => const Center(child: BestieSpinner()),
      error: (e, _) => BestieEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load track history',
        description: formatApiError(e),
      ),
      data: (data) {
        final items =
            (data['items'] as List? ?? const []).cast<Map<String, dynamic>>();
        if (items.isEmpty) {
          return const BestieEmptyState(
            icon: Icons.video_file_outlined,
            title: 'No captures yet',
            description:
                'Activity captures will appear after the desktop cycle runs.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final clip = items[index];
            final url = clip['clipUrl']?.toString() ?? '';
            final failed =
                (clip['status'] ?? '').toString() == 'CAPTURE_FAILED';
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(BestieTokens.rMd),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: failed ? colors.dangerSoft : colors.brandSoft,
                      borderRadius: BorderRadius.circular(BestieTokens.rMd),
                    ),
                    child: Icon(
                      failed
                          ? Icons.videocam_off_outlined
                          : Icons.play_circle_outline,
                      color: failed ? colors.danger : colors.brandStrong,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDateTime(clip['captureStartedAt']),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          (clip['note'] ?? 'working').toString(),
                          style: TextStyle(
                            color: colors.textSoft,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${clip['platform'] ?? 'desktop'} - ${clip['durationSeconds'] ?? 5}s',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (url.isNotEmpty)
                    IconButton.filledTonal(
                      tooltip: 'Open capture',
                      onPressed: () => onOpenClip(url),
                      icon: const Icon(Icons.open_in_new_rounded),
                    )
                  else
                    BestieBadge(
                      tone: BestieTone.warning,
                      child: Text(failed ? 'No video' : 'Pending'),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

String _hours(dynamic raw) {
  final seconds = (raw as num?)?.toInt() ?? 0;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  return '${hours}h ${minutes}m';
}

String _formatDateTime(dynamic raw) {
  final parsed = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (parsed == null) return 'Unknown time';
  final hour = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
  final ampm = parsed.hour >= 12 ? 'PM' : 'AM';
  return '${parsed.day.toString().padLeft(2, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.year} '
      '$hour:${parsed.minute.toString().padLeft(2, '0')} $ampm';
}
