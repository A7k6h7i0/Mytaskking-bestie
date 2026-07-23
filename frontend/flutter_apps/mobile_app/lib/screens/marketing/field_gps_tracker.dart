import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:mytaskking_core/mytaskking_core.dart';

import 'field_offline_queue.dart';

/// Logs GPS pings to `/marketing/gps` while a field visit is active.
class FieldGpsTracker {
  FieldGpsTracker._();
  static final FieldGpsTracker instance = FieldGpsTracker._();

  Timer? _timer;
  BestieApi? _api;

  bool get isRunning => _timer != null;

  void start(BestieApi api, {int intervalSeconds = 120}) {
    stop();
    _api = api;
    unawaited(_tick());
    _timer = Timer.periodic(
      Duration(seconds: intervalSeconds.clamp(30, 600)),
      (_) => _tick(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _api = null;
  }

  Future<void> _tick() async {
    final api = _api;
    if (api == null) return;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final payload = {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
        'offlineId': 'gps-${DateTime.now().millisecondsSinceEpoch}',
      };
      try {
        await api.logFieldGps(payload);
      } catch (_) {
        await FieldOfflineQueue.enqueueGps({
          ...payload,
          'logged_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (_) {}
  }
}
