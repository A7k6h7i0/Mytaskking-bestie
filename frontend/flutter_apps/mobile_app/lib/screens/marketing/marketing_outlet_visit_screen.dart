import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../../state.dart';
import '../blink_selfie_capture.dart';
import '../front_selfie_capture.dart';
import 'field_gps_tracker.dart';
import 'field_offline_queue.dart';
import 'field_helpers.dart';
import 'field_route_helpers.dart';

/// Outlet visit — check in with live selfie + GPS, check out when done.
class MarketingOutletVisitScreen extends ConsumerStatefulWidget {
  final String outletId;
  const MarketingOutletVisitScreen({super.key, required this.outletId});

  @override
  ConsumerState<MarketingOutletVisitScreen> createState() =>
      _MarketingOutletVisitScreenState();
}

class _MarketingOutletVisitScreenState
    extends ConsumerState<MarketingOutletVisitScreen> {
  Map<String, dynamic>? _outlet;
  Map<String, dynamic>? _activeVisit;
  Map<String, dynamic>? _settings;
  Timer? _autoCompleteTimer;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _isManager {
    final role = ref.read(authStoreProvider).user?.role ?? '';
    return role == 'ADMIN' ||
        role == 'SUPER_ADMIN' ||
        role == 'MANAGER' ||
        role == 'PROJECT_COORDINATOR_MANAGER';
  }

  bool get _visitSelfieRequired => _settings?['visitSelfieRequired'] != false;
  bool get _blinkSelfieRequired => _settings?['blinkSelfieRequired'] != false;

  bool get _isDesktop =>
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.linux ||
        TargetPlatform.macOS =>
          true,
        _ => false,
      };

  @override
  void dispose() {
    _autoCompleteTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final results = await Future.wait([
        api.getMarketingOutlet(widget.outletId),
        resolveActiveFieldVisit(api),
        api.marketingFieldSettings(),
      ]);
      if (!mounted) return;
      final active = results[1];
      setState(() {
        _outlet = Map<String, dynamic>.from(results[0] as Map);
        _activeVisit = active;
        _settings = Map<String, dynamic>.from(results[2] as Map);
        _loading = false;
      });
      if (_visitActiveHere) {
        _startGpsTracking();
        _scheduleAutoComplete();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = formatApiError(e);
        _loading = false;
      });
    }
  }

  Future<Position> _currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) throw 'Turn on location to start a field visit.';
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw 'Location permission is required for field visits.';
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  Future<String> _uploadSelfie(Uint8List bytes) async {
    final asset = await ref.read(apiProvider).uploadFile(
          bytes: bytes,
          filename: 'visit-selfie-${DateTime.now().millisecondsSinceEpoch}.jpg',
          mimeType: 'image/jpeg',
        );
    final url = asset['url']?.toString();
    if (url == null || url.isEmpty) {
      throw 'Selfie upload failed — no URL returned.';
    }
    return url;
  }

  void _startGpsTracking() {
    final interval =
        (_settings?['gpsIntervalMovingSeconds'] as num?)?.toInt() ?? 120;
    FieldGpsTracker.instance.start(ref.read(apiProvider), intervalSeconds: interval);
  }

  void _scheduleAutoComplete() {
    _autoCompleteTimer?.cancel();
    final mins = (_settings?['autoVisitDurationMinutes'] as num?)?.toInt() ?? 0;
    if (mins <= 0 || !_visitActiveHere) return;
    final checkIn = _activeVisit?['checkInAt']?.toString();
    final started = checkIn != null ? DateTime.tryParse(checkIn) : null;
    final delay = started == null
        ? Duration(minutes: mins)
        : started.add(Duration(minutes: mins)).difference(DateTime.now());
    if (delay.isNegative) {
      unawaited(_endVisit(auto: true));
      return;
    }
    _autoCompleteTimer = Timer(delay, () {
      if (mounted && _visitActiveHere) unawaited(_endVisit(auto: true));
    });
  }

  Future<void> _assignExecutive() async {
    final employees = await ref
        .read(apiProvider)
        .listEmployees(role: 'EXECUTIVE', pageSize: 100);
    if (!mounted || employees.isEmpty) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('Assign executive')),
            for (final e in employees)
              ListTile(
                title: Text(e['name']?.toString() ?? ''),
                onTap: () => Navigator.pop(ctx, e),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    try {
      await ref.read(apiProvider).updateMarketingOutlet(widget.outletId, {
        'assignedToId': picked['id'],
      });
      await _load();
      if (mounted) {
        bestieToast(context, 'Outlet assigned', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Assign failed',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _approveOutlet() async {
    try {
      await ref.read(apiProvider).approveMarketingOutlet(widget.outletId);
      await _load();
      if (mounted) {
        bestieToast(context, 'Outlet approved', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Approve failed',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _deactivateOutlet() async {
    final ok = await bestieConfirm(context,
        title: 'Deactivate outlet?', confirmLabel: 'Deactivate');
    if (!ok) return;
    try {
      await ref.read(apiProvider).deactivateMarketingOutlet(widget.outletId);
      if (mounted) {
        bestieToast(context, 'Outlet deactivated', kind: BestieToastKind.success);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not deactivate',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _startVisit() async {
    if (_busy) return;
    if (_isDesktop) {
      bestieToast(context, 'Field visits require the mobile app',
          body: 'Use your phone to capture a live selfie at the outlet.',
          kind: BestieToastKind.info);
      return;
    }
    if (_activeVisit != null &&
        _activeVisit!['outletId']?.toString() != widget.outletId) {
      final name =
          (_activeVisit!['outlet'] as Map?)?['name']?.toString() ?? 'another outlet';
      bestieToast(context, 'Finish your current visit first',
          body: 'You have an open visit at $name.', kind: BestieToastKind.warning);
      return;
    }

    setState(() => _busy = true);
    try {
      String selfieUrl = 'auto-detected';
      if (_visitSelfieRequired) {
        Uint8List? selfieBytes;
        if (_blinkSelfieRequired) {
          selfieBytes = await BlinkSelfieCaptureScreen.captureBytes(
            context,
            title: 'Blink to check in',
          );
        } else {
          selfieBytes = await Navigator.of(context).push<Uint8List>(
            MaterialPageRoute(
              builder: (_) => const FrontSelfieCapture(
                title: 'Check-in selfie',
                hint:
                    'Take a clear live selfie at the outlet. Front camera only.',
              ),
            ),
          );
        }
        if (selfieBytes == null) return;
        selfieUrl = await _uploadSelfie(selfieBytes);
      }

      final position = await _currentPosition();
      final offlineId = 'visit-${DateTime.now().millisecondsSinceEpoch}';

      try {
        final visit = await ref.read(apiProvider).startFieldVisit({
          'outletId': widget.outletId,
          'selfieUrl': selfieUrl,
          'latitude': position.latitude,
          'longitude': position.longitude,
        });

        if (!mounted) return;
        setState(() => _activeVisit = Map<String, dynamic>.from(visit as Map));
      } catch (_) {
        await FieldOfflineQueue.enqueueVisit({
          'offlineId': offlineId,
          'outletId': widget.outletId,
          'selfieUrl': selfieUrl,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'check_in_at': DateTime.now().toIso8601String(),
          'status': 'in_progress',
        });
        if (!mounted) return;
        setState(() => _activeVisit = {
              'id': offlineId,
              'outletId': widget.outletId,
              'offline': true,
              'checkInAt': DateTime.now().toIso8601String(),
            });
        bestieToast(context, 'Saved offline',
            body: 'Visit will sync when you are back online.',
            kind: BestieToastKind.info);
      }

      _startGpsTracking();
      _scheduleAutoComplete();
      if (_activeVisit?['offline'] != true) {
        bestieToast(context, 'Visit started',
            body: _visitSelfieRequired
                ? 'Checked in with selfie and GPS.'
                : 'Checked in with GPS.',
            kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not start visit',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _endVisit({bool auto = false}) async {
    if (_busy || _activeVisit == null) return;
    final notesCtrl = TextEditingController();
    final c = BestieColors.of(context);
    if (!auto) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('End visit'),
          content: TextField(
            controller: notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'Order taken, stock checked, follow-up…',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: c.brand),
              child: const Text('Complete visit'),
            ),
          ],
        ),
      );
      if (ok != true) {
        notesCtrl.dispose();
        return;
      }
    } else {
      notesCtrl.text = 'Auto-completed after minimum dwell time.';
    }

    setState(() => _busy = true);
    try {
      final visitId = _activeVisit!['id'].toString();
      final isOffline = _activeVisit!['offline'] == true;
      if (isOffline) {
        await FieldOfflineQueue.completeQueuedVisit(
          visitId,
          notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
        );
      } else {
        await ref.read(apiProvider).endFieldVisit(
              visitId,
              {
                if (notesCtrl.text.trim().isNotEmpty) 'notes': notesCtrl.text.trim(),
              },
            );
      }
      if (!mounted) return;
      FieldGpsTracker.instance.stop();
      _autoCompleteTimer?.cancel();
      setState(() => _activeVisit = null);
      bestieToast(context, auto ? 'Visit auto-completed' : 'Visit completed',
          kind: BestieToastKind.success);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not end visit',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    } finally {
      notesCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _visitActiveHere =>
      _activeVisit != null &&
      _activeVisit!['outletId']?.toString() == widget.outletId;

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final outlet = _outlet;
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        title: Text(outlet?['name']?.toString() ?? 'Outlet visit'),
        backgroundColor: c.surface,
        foregroundColor: c.text,
        actions: [
          if (_isManager && outlet?['approvalStatus'] == 'pending')
            IconButton(
              tooltip: 'Approve outlet',
              onPressed: _approveOutlet,
              icon: const Icon(Icons.check_circle_outline),
            ),
          if (_isManager)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'assign') _assignExecutive();
                if (v == 'deactivate') _deactivateOutlet();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'assign', child: Text('Assign executive')),
                PopupMenuItem(value: 'deactivate', child: Text('Deactivate')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: BestieSpinner())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: TextStyle(color: c.danger)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    if (_visitActiveHere) _activeBanner(c),
                    _infoCard(c, outlet ?? const {}),
                    const SizedBox(height: 20),
                    if (_visitActiveHere) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : () => _endVisit(),
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.check_circle_outline_rounded),
                          label: const Text('Complete visit'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(
                              '/marketing/orders?outletId=${widget.outletId}'),
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('Place order'),
                        ),
                      ),
                    ] else if (_activeVisit != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: c.warningSoft,
                          borderRadius: BorderRadius.circular(BestieTokens.rLg),
                          border: Border.all(color: c.warning.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'You have an open visit at '
                          '${(_activeVisit!['outlet'] as Map?)?['name'] ?? 'another outlet'}. '
                          'Complete it before starting here.',
                          style: TextStyle(color: c.text, fontSize: 13),
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Check in',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _visitSelfieRequired
                            ? 'A live selfie and GPS location are required to start the visit.'
                            : 'GPS location is required. Selfie is optional for your org.',
                        style: TextStyle(color: c.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      if (outlet?['approvalStatus'] == 'pending')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'This outlet is pending manager approval.',
                            style: TextStyle(color: c.warning, fontSize: 13),
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: _busy ||
                                (!_isManager && outlet?['approvalStatus'] == 'pending')
                            ? null
                            : _startVisit,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(_visitSelfieRequired
                                ? Icons.camera_alt_rounded
                                : Icons.play_arrow_rounded),
                        label: Text(_visitSelfieRequired
                            ? 'Start visit with selfie'
                            : 'Start visit'),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _activeBanner(BestieColors c) {
    final checkIn = _activeVisit?['checkInAt']?.toString();
    DateTime? started;
    if (checkIn != null) {
      started = DateTime.tryParse(checkIn)?.toLocal();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.successSoft,
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        border: Border.all(color: c.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.timelapse_rounded, color: c.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Visit in progress',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: c.text)),
                if (started != null)
                  Text(
                    'Started ${_formatTime(started)}',
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
          BestieBadge(tone: BestieTone.success, child: Text('Active')),
        ],
      ),
    );
  }

  Widget _infoCard(BestieColors c, Map<String, dynamic> outlet) {
    final lines = [
      if (outlet['address'] != null) outlet['address'].toString(),
      if (outlet['city'] != null) outlet['city'].toString(),
      if (outlet['phone'] != null) outlet['phone'].toString(),
    ].where((s) => s.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(BestieTokens.rLg),
        border: Border.all(color: c.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: c.brandSoft,
                child: Icon(Icons.store, color: c.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  outlet['name']?.toString() ?? 'Outlet',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: c.text,
                  ),
                ),
              ),
            ],
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, style: TextStyle(color: c.textMuted, fontSize: 13)),
              ),
          ],
          if (FieldRouteHelpers.outletLatLng(outlet) != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final pt = FieldRouteHelpers.outletLatLng(outlet)!;
                final pos = await FieldRouteHelpers.resolveCurrentPosition();
                if (!context.mounted) return;
                if (pos != null) {
                  await FieldRouteHelpers.openMapsDirections(pos, pt);
                } else {
                  await FieldRouteHelpers.openMapsNavigation(
                    pt,
                    label: outlet['name']?.toString(),
                  );
                }
              },
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('Open in Google Maps'),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
