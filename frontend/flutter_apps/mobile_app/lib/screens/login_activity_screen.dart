import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';
import 'live_locations_map_screen.dart';
import 'marketing/gps_map_view_screen.dart';

final loginActivityProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, _LoginActivityQuery>((ref, query) async {
  final api = ref.watch(apiProvider);
  return api.sessionActivity(
    from: query.from,
    to: query.to,
    pageSize: 100,
  );
});

final employeeTrackingSettingsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(apiProvider).employeeTrackingSettings();
});

final employeeLiveLocationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final resp = await ref.watch(apiProvider).employeeLiveLocations();
  return List<Map<String, dynamic>>.from(resp['items'] ?? const []);
});

class _LoginActivityQuery {
  final DateTime from;
  final DateTime to;

  const _LoginActivityQuery({required this.from, required this.to});

  @override
  bool operator ==(Object other) =>
      other is _LoginActivityQuery && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class LoginActivityScreen extends ConsumerStatefulWidget {
  const LoginActivityScreen({super.key});

  @override
  ConsumerState<LoginActivityScreen> createState() => _LoginActivityScreenState();
}

class _LoginActivityScreenState extends ConsumerState<LoginActivityScreen> {
  late DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  late DateTime _to = DateTime.now();
  bool _savingSettings = false;

  static const _intervalOptions = <int, String>{
    120: '2 min',
    300: '5 min',
    600: '10 min',
    900: '15 min',
    1800: '30 min',
    3600: '1 hour',
  };

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  _LoginActivityQuery get _query => _LoginActivityQuery(
        from: _startOfDay(_from).toUtc(),
        to: _endOfDay(_to).toUtc(),
      );

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2024),
      lastDate: _to,
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _to = picked);
  }

  String _formatDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _sessionDuration(Map<String, dynamic> row) {
    final loginAt = DateTime.tryParse(row['loginAt']?.toString() ?? '');
    if (loginAt == null) return '—';
    final logoutRaw = row['logoutAt'];
    final end = logoutRaw != null
        ? DateTime.tryParse(logoutRaw.toString()) ?? DateTime.now()
        : DateTime.now();
    final mins = end.difference(loginAt).inMinutes.clamp(0, 1 << 30);
    if (mins < 60) return '${mins}m';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  String _formatDateTime(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (parsed == null) return '—';
    return '${_month(parsed.month)} ${parsed.day}, ${_two(parsed.hour)}:${_two(parsed.minute)}';
  }

  String _month(int m) => const [
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
        'Dec',
      ][m - 1];

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _saveTrackingSettings({
    bool? gpsEnabled,
    int? gpsIntervalSeconds,
  }) async {
    setState(() => _savingSettings = true);
    try {
      await ref.read(apiProvider).updateEmployeeTrackingSettings({
        if (gpsEnabled != null) 'gpsEnabled': gpsEnabled,
        if (gpsIntervalSeconds != null)
          'gpsIntervalSeconds': gpsIntervalSeconds,
      });
      ref.invalidate(employeeTrackingSettingsProvider);
      if (mounted) {
        bestieToast(context, 'Tracking settings saved',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not save settings',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  void _openSessionMap(Map<String, dynamic> row, Map<String, dynamic> user) {
    final lat = row['latitude'];
    final lng = row['longitude'];
    if (lat == null || lng == null) return;
    GpsMapViewScreen.open(
      context,
      point: LatLng((lat as num).toDouble(), (lng as num).toDouble()),
      title: user['name']?.toString() ?? 'Login location',
      subtitle: row['address']?.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final role = ref.watch(authStoreProvider).user?.role ?? '';
    final canViewEvidence = role == 'SUPER_ADMIN' || role == 'ADMIN';
    final activity = ref.watch(loginActivityProvider(_query));
    final settings = canViewEvidence
        ? ref.watch(employeeTrackingSettingsProvider)
        : const AsyncValue<Map<String, dynamic>>.data({});
    final live = canViewEvidence
        ? ref.watch(employeeLiveLocationsProvider)
        : const AsyncValue<List<Map<String, dynamic>>>.data([]);

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Login activity'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(loginActivityProvider(_query)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Login and logout history across your organisation.',
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFrom,
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: Text('From ${_formatDay(_from)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTo,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text('To ${_formatDay(_to)}'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (canViewEvidence)
            settings.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (s) {
                final enabled = s['gpsEnabled'] != false;
                final interval =
                    (s['gpsIntervalSeconds'] as num?)?.toInt() ?? 300;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.bgSoft,
                      borderRadius: BorderRadius.circular(BestieTokens.rMd),
                      border: Border.all(color: colors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Employee GPS tracking',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, color: colors.text)),
                        const SizedBox(height: 4),
                        Text(
                          'All internal employees are tracked at this interval. Pauses during approved leave.',
                          style:
                              TextStyle(color: colors.textMuted, fontSize: 12),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enable tracking'),
                          value: enabled,
                          onChanged: _savingSettings
                              ? null
                              : (v) => _saveTrackingSettings(gpsEnabled: v),
                        ),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'GPS interval',
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              isExpanded: true,
                              value: _intervalOptions.containsKey(interval)
                                  ? interval
                                  : 300,
                              items: _intervalOptions.entries
                                  .map((e) => DropdownMenuItem(
                                        value: e.key,
                                        child: Text(e.value),
                                      ))
                                  .toList(),
                              onChanged: _savingSettings
                                  ? null
                                  : (v) {
                                      if (v != null) {
                                        _saveTrackingSettings(
                                            gpsIntervalSeconds: v);
                                      }
                                    },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (canViewEvidence)
            live.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: LinearProgressIndicator(),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (items) {
                if (items.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: OutlinedButton.icon(
                    onPressed: () => LiveLocationsMapScreen.open(
                      context,
                      items: items,
                    ),
                    icon: const Icon(Icons.map_outlined),
                    label: Text('View live map (${items.length})'),
                  ),
                );
              },
            ),
          Expanded(
            child: activity.when(
              loading: () => const Center(child: BestieSpinner()),
              error: (e, _) => BestieEmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load activity',
                description: formatApiError(e),
              ),
              data: (data) {
                final items = (data['items'] as List? ?? const [])
                    .cast<Map<String, dynamic>>();
                if (items.isEmpty) {
                  return const BestieEmptyState(
                    icon: Icons.login_rounded,
                    title: 'No login activity',
                    description: 'No sessions in this date range.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(loginActivityProvider(_query));
                    await ref.read(loginActivityProvider(_query).future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final row = items[index];
                      final user =
                          (row['user'] as Map?)?.cast<String, dynamic>() ?? {};
                      final hasSelfie =
                          (row['selfieUrl']?.toString() ?? '').isNotEmpty;
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
                            Row(
                              children: [
                                BestieAvatar(
                                  name: user['name']?.toString() ?? 'User',
                                  imageUrl: user['avatarUrl']?.toString(),
                                  isClient: user['isClient'] == true,
                                  size: 40,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      BestieUserName(
                                        name: user['name']?.toString() ?? 'User',
                                        isClient: user['isClient'] == true,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (user['customTitle'] != null ||
                                          user['role'] != null)
                                        Text(
                                          user['customTitle']?.toString() ??
                                              user['role']?.toString() ??
                                              '',
                                          style: TextStyle(
                                            color: colors.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _InfoRow(
                              label: 'Login',
                              value: _formatDateTime(row['loginAt']),
                            ),
                            _InfoRow(
                              label: 'Logout',
                              value: row['logoutAt'] != null
                                  ? _formatDateTime(row['logoutAt'])
                                  : 'Active now',
                              highlight: row['logoutAt'] == null,
                            ),
                            _InfoRow(
                              label: 'Duration',
                              value: _sessionDuration(row),
                            ),
                            _InfoRow(
                              label: 'Device',
                              value: row['device']?.toString() ??
                                  row['platform']?.toString() ??
                                  '—',
                            ),
                            _InfoRow(
                              label: 'IP',
                              value: row['ip']?.toString() ?? '—',
                            ),
                            if (canViewEvidence) ...[
                              _InfoRow(
                                label: 'Location',
                                value: row['address']?.toString() ??
                                    (row['latitude'] != null &&
                                            row['longitude'] != null
                                        ? '${row['latitude']}, ${row['longitude']}'
                                        : 'Not captured'),
                              ),
                              if (row['latitude'] != null &&
                                  row['longitude'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () =>
                                          _openSessionMap(row, user),
                                      icon: const Icon(Icons.map_outlined,
                                          size: 16),
                                      label: const Text('View on map'),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 72,
                                      child: Text(
                                        'Selfie',
                                        style: TextStyle(
                                          color: colors.textMuted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: hasSelfie
                                          ? _SessionSelfieThumb(
                                              sessionId:
                                                  row['id']?.toString() ?? '',
                                              userName: user['name']
                                                      ?.toString() ??
                                                  'User',
                                            )
                                          : Text(
                                              'Not captured',
                                              style: TextStyle(
                                                color: colors.textMuted,
                                                fontSize: 13,
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _InfoRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                color: highlight ? colors.brandStrong : colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionSelfieThumb extends ConsumerStatefulWidget {
  final String sessionId;
  final String userName;

  const _SessionSelfieThumb({
    required this.sessionId,
    required this.userName,
  });

  @override
  ConsumerState<_SessionSelfieThumb> createState() =>
      _SessionSelfieThumbState();
}

class _SessionSelfieThumbState extends ConsumerState<_SessionSelfieThumb> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await ref
          .read(apiProvider)
          .sessionSelfieBytes(widget.sessionId);
      if (!mounted) return;
      if (bytes.isEmpty) {
        setState(() => _failed = true);
        return;
      }
      setState(() {
        _bytes = bytes;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _openFull() {
    if (_bytes == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text('${widget.userName} — login selfie'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BestieTokens.rMd),
                child: Image.memory(_bytes!, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    if (_failed) {
      return Text(
        'Not captured',
        style: TextStyle(color: colors.textMuted, fontSize: 13),
      );
    }
    if (_bytes == null) {
      return Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading…',
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          ),
        ],
      );
    }
    return InkWell(
      onTap: _openFull,
      borderRadius: BorderRadius.circular(BestieTokens.rMd),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(BestieTokens.rMd),
            child: Image.memory(
              _bytes!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 56,
                height: 56,
                color: colors.bgSoft,
                child: Icon(Icons.broken_image_outlined,
                    color: colors.textMuted),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'View selfie',
            style: TextStyle(
              color: colors.brandStrong,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.visibility_outlined,
              size: 16, color: colors.brandStrong),
        ],
      ),
    );
  }
}
