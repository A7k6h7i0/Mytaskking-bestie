import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:mytaskking_core/mytaskking_core.dart';

import '../services/device_integrity_service.dart';

/// Org-wide GPS pings while logged in (pauses on approved leave).
class EmployeeGpsTracker {
  EmployeeGpsTracker._();
  static final EmployeeGpsTracker instance = EmployeeGpsTracker._();

  Timer? _timer;
  BestieApi? _api;
  int _intervalSeconds = 300;

  bool get isRunning => _timer != null;

  Future<void> sync(BestieApi api) async {
    _api = api;
    try {
      final state = await api.employeeTrackingState();
      if (state['shouldTrack'] == true) {
        final interval = (state['intervalSeconds'] as num?)?.toInt() ?? 300;
        start(api, intervalSeconds: interval);
      } else {
        stop();
      }
    } catch (_) {}
  }

  void start(BestieApi api, {int intervalSeconds = 300}) {
    _api = api;
    _intervalSeconds = intervalSeconds.clamp(60, 3600);
    if (_timer != null) {
      _timer!.cancel();
    }
    unawaited(_tick());
    _timer = Timer.periodic(
      Duration(seconds: _intervalSeconds),
      (_) => _tick(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    final api = _api;
    if (api == null) return;
    try {
      final state = await api.employeeTrackingState();
      if (state['shouldTrack'] != true) {
        stop();
        return;
      }
      final interval = (state['intervalSeconds'] as num?)?.toInt();
      if (interval != null &&
          interval != _intervalSeconds &&
          _timer != null) {
        start(api, intervalSeconds: interval);
        return;
      }
      await DeviceIntegrityService.assertLocationTrust();
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await assertRealPosition(
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 12),
          ),
        ),
      );
      await api.logEmployeeGps({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
      });
    } catch (_) {}
  }
}
