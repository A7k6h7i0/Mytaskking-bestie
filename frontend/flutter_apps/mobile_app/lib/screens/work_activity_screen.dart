import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state.dart';

final workActivitySummaryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, date) async {
  final api = ref.watch(apiProvider);
  return api.workActivitySummary(date: date, timezone: 'Asia/Kolkata');
});

final workActivityUserDayProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String userId, String date})>((ref, args) async {
  final api = ref.watch(apiProvider);
  return api.workActivityUserDay(
    userId: args.userId,
    date: args.date,
    timezone: 'Asia/Kolkata',
  );
});

final workActivityClipsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String userId, String date})>((ref, args) async {
  final api = ref.watch(apiProvider);
  return api.workActivityClips(
    userId: args.userId,
    date: args.date,
    pageSize: 100,
  );
});

class WorkActivityScreen extends ConsumerStatefulWidget {
  const WorkActivityScreen({super.key});

  @override
  ConsumerState<WorkActivityScreen> createState() => _WorkActivityScreenState();
}

class _WorkActivityScreenState extends ConsumerState<WorkActivityScreen> {
  late DateTime _date = DateTime.now();
  String? _selectedUserId;
  String? _selectedUserName;

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
    if (picked != null) {
      setState(() {
        _date = picked;
        _selectedUserId = null;
        _selectedUserName = null;
      });
    }
  }

  void _refresh() {
    ref.invalidate(workActivitySummaryProvider(_dateKey));
    if (_selectedUserId != null) {
      ref.invalidate(workActivityUserDayProvider(
        (userId: _selectedUserId!, date: _dateKey),
      ));
      ref.invalidate(workActivityClipsProvider(
        (userId: _selectedUserId!, date: _dateKey),
      ));
    }
  }

  Future<void> _openClip(String url) async {
    if (url.trim().isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      bestieToast(context, 'Could not open capture',
          kind: BestieToastKind.error);
    }
  }

  Future<void> _openMap(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      bestieToast(context, 'Could not open map', kind: BestieToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authStoreProvider).user;
    final isAdmin = me?.role == 'ADMIN' || me?.role == 'SUPER_ADMIN';
    final colors = BestieColors.of(context);
    final summary = ref.watch(workActivitySummaryProvider(_dateKey));
    final wide = MediaQuery.sizeOf(context).width >= 900;

    if (!isAdmin) {
      return const Scaffold(
        body: BestieEmptyState(
          icon: Icons.lock_outline,
          title: 'Admin access only',
          description: 'Work activity is available to admins and super admins.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        foregroundColor: colors.textMuted,
        title: Text('Work activity', style: TextStyle(color: colors.textMuted)),
        actions: [
          IconButton(
            tooltip: 'Pick date',
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
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
          final interval = (data['intervalSeconds'] as num?)?.toInt();
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 420,
                  child: _EmployeePanel(
                    dateKey: _dateKey,
                    intervalSeconds: interval,
                    items: items,
                    selectedUserId: _selectedUserId,
                    onSelect: (userId, userName) => setState(() {
                      _selectedUserId = userId;
                      _selectedUserName = userName;
                    }),
                  ),
                ),
                VerticalDivider(width: 1, color: colors.border),
                Expanded(
                  child: _selectedUserId == null
                      ? const BestieEmptyState(
                          icon: Icons.visibility_outlined,
                          title: 'Select an employee',
                          description:
                              'Choose someone who logged in on Windows today.',
                        )
                      : _EmployeeDetail(
                          userId: _selectedUserId!,
                          userName: _selectedUserName ?? 'Employee',
                          dateKey: _dateKey,
                          onOpenClip: _openClip,
                          onOpenMap: _openMap,
                        ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (interval != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Tracking interval: ${_intervalLabel(interval)}',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ),
              if (_selectedUserId != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedUserName ?? 'Employee',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _selectedUserId = null;
                          _selectedUserName = null;
                        }),
                        icon: const Icon(Icons.arrow_back_rounded, size: 16),
                        label: const Text('All employees'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _selectedUserId == null
                    ? _EmployeePanel(
                        dateKey: _dateKey,
                        intervalSeconds: interval,
                        items: items,
                        selectedUserId: _selectedUserId,
                        onSelect: (userId, userName) => setState(() {
                          _selectedUserId = userId;
                          _selectedUserName = userName;
                        }),
                      )
                    : _EmployeeDetail(
                        userId: _selectedUserId!,
                        userName: _selectedUserName ?? 'Employee',
                        dateKey: _dateKey,
                        onOpenClip: _openClip,
                        onOpenMap: _openMap,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmployeePanel extends StatelessWidget {
  final String dateKey;
  final int? intervalSeconds;
  final List<Map<String, dynamic>> items;
  final String? selectedUserId;
  final void Function(String userId, String userName) onSelect;

  const _EmployeePanel({
    required this.dateKey,
    required this.intervalSeconds,
    required this.items,
    required this.selectedUserId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.monitor_heart_outlined,
                      size: 18, color: colors.brandStrong),
                  const SizedBox(width: 8),
                  Text(dateKey,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ],
              ),
              if (intervalSeconds != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Check every ${_intervalLabel(intervalSeconds!)}',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  'Admin has not set a tracking interval yet.',
                  style: TextStyle(color: colors.warning, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const BestieEmptyState(
                  icon: Icons.people_outline,
                  title: 'No Windows logins today',
                  description:
                      'Employees appear here after they sign in on the Windows app.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = items[index];
                    final user =
                        (row['user'] as Map).cast<String, dynamic>();
                    final userId = user['id']?.toString() ?? '';
                    final selected = userId == selectedUserId;
                    return _EmployeeActivityTile(
                      row: row,
                      selected: selected,
                      onTap: () => onSelect(
                        userId,
                        user['name']?.toString() ?? 'Employee',
                      ),
                    );
                  },
                ),
        ),
      ],
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
    final status = row['status']?.toString() ?? 'Offline';
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
            border: Border.all(color: selected ? colors.brand : colors.border),
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
                      '${_hours(row['workingSeconds'])} worked · ${row['clipCount'] ?? 0} clips',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                    if (row['desktopLoginAt'] != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Login ${_formatDateTime(row['desktopLoginAt'])}',
                        style: TextStyle(color: colors.textSoft, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  BestieBadge(
                    tone: _statusTone(status),
                    child: Text(status),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('View track'),
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

class _EmployeeDetail extends ConsumerWidget {
  final String userId;
  final String userName;
  final String dateKey;
  final Future<void> Function(String url) onOpenClip;
  final Future<void> Function(double lat, double lng) onOpenMap;

  const _EmployeeDetail({
    required this.userId,
    required this.userName,
    required this.dateKey,
    required this.onOpenClip,
    required this.onOpenMap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BestieColors.of(context);
    final day = ref.watch(workActivityUserDayProvider((userId: userId, date: dateKey)));
    final clips = ref.watch(workActivityClipsProvider((userId: userId, date: dateKey)));

    return day.when(
      loading: () => const Center(child: BestieSpinner()),
      error: (e, _) => BestieEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load work day',
        description: formatApiError(e),
      ),
      data: (detail) {
        final lat = (detail['loginLatitude'] as num?)?.toDouble();
        final lng = (detail['loginLongitude'] as num?)?.toDouble();
        final address = detail['loginAddress']?.toString();
        final status = detail['status']?.toString() ?? 'Offline';

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(userName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            BestieBadge(tone: _statusTone(status), child: Text(status)),
            const SizedBox(height: 16),
            _InfoCard(
              title: 'Work day',
              children: [
                _InfoRow(
                  icon: Icons.login_rounded,
                  label: 'Login time',
                  value: _formatDateTime(detail['desktopLoginAt']),
                ),
                _InfoRow(
                  icon: Icons.timer_outlined,
                  label: 'Work time',
                  value: _hours(detail['workingSeconds']),
                ),
                _InfoRow(
                  icon: Icons.place_outlined,
                  label: 'Login location',
                  value: address?.isNotEmpty == true
                      ? address!
                      : (lat != null && lng != null
                          ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                          : 'Location not recorded'),
                ),
              ],
            ),
            if (lat != null && lng != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => onOpenMap(lat, lng),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open map view'),
              ),
            ],
            const SizedBox(height: 20),
            Text('Activity clips',
                style: TextStyle(
                  color: colors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                )),
            const SizedBox(height: 10),
            clips.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: BestieSpinner()),
              ),
              error: (e, _) => BestieEmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load clips',
                description: formatApiError(e),
              ),
              data: (clipData) {
                final items = (clipData['items'] as List? ?? const [])
                    .cast<Map<String, dynamic>>();
                if (items.isEmpty) {
                  return const BestieEmptyState(
                    icon: Icons.video_file_outlined,
                    title: 'No captures yet',
                    description:
                        'Clips appear when the desktop idle check runs.',
                  );
                }
                return Column(
                  children: [
                    for (final clip in items) ...[
                      _ClipTile(clip: clip, onOpenClip: onOpenClip),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.brandStrong),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClipTile extends StatelessWidget {
  final Map<String, dynamic> clip;
  final Future<void> Function(String url) onOpenClip;

  const _ClipTile({required this.clip, required this.onOpenClip});

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final url = clip['clipUrl']?.toString() ?? '';
    final failed = (clip['status'] ?? '').toString() == 'CAPTURE_FAILED';
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
          Icon(
            failed ? Icons.videocam_off_outlined : Icons.play_circle_outline,
            color: failed ? colors.danger : colors.brandStrong,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatDateTime(clip['captureStartedAt']),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text((clip['note'] ?? 'working').toString(),
                    style: TextStyle(color: colors.textSoft)),
                const SizedBox(height: 4),
                Text(
                  '${clip['platform'] ?? 'desktop'} · ${clip['durationSeconds'] ?? 5}s',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (url.isNotEmpty)
            IconButton.filledTonal(
              tooltip: 'Open capture',
              onPressed: () => onOpenClip(url),
              icon: const Icon(Icons.open_in_new_rounded),
            ),
        ],
      ),
    );
  }
}

BestieTone _statusTone(String status) {
  switch (status.toLowerCase()) {
    case 'working':
      return BestieTone.success;
    case 'idle':
    case 'paused':
      return BestieTone.warning;
    case 'lunch':
    case 'busy':
    case 'leave':
      return BestieTone.neutral;
    default:
      return BestieTone.neutral;
  }
}

String _intervalLabel(int seconds) {
  if (seconds % 3600 == 0) return '${seconds ~/ 3600} hour';
  if (seconds % 60 == 0) return '${seconds ~/ 60} minutes';
  return '$seconds seconds';
}

String _hours(dynamic raw) {
  final seconds = (raw as num?)?.toInt() ?? 0;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  return '${hours}h ${minutes}m';
}

String _formatDateTime(dynamic raw) {
  final parsed = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (parsed == null) return '—';
  final hour = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
  final ampm = parsed.hour >= 12 ? 'PM' : 'AM';
  return '${parsed.day.toString().padLeft(2, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.year} '
      '$hour:${parsed.minute.toString().padLeft(2, '0')} $ampm';
}
