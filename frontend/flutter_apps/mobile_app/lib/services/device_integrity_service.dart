import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safe_device/safe_device.dart';

/// Outcome of a device integrity check (mock GPS, root, emulator).
class DeviceIntegrityResult {
  const DeviceIntegrityResult({
    required this.passed,
    required this.reasons,
    this.developerModeEnabled = false,
  });

  const DeviceIntegrityResult.ok()
      : passed = true,
        reasons = const [],
        developerModeEnabled = false;

  final bool passed;
  final List<String> reasons;
  final bool developerModeEnabled;
}

/// Detects fake GPS, rooted devices, and emulators on Android field devices.
class DeviceIntegrityService {
  DeviceIntegrityService._();

  static const mockLocationReason = 'Fake GPS / mock location app detected';
  static const rootedReason = 'Rooted or modified device detected';
  static const emulatorReason = 'Emulator or virtual device detected';

  static Future<DeviceIntegrityResult> check() async {
    if (!Platform.isAndroid) {
      return const DeviceIntegrityResult.ok();
    }

    final reasons = <String>{};

    await Future.wait<void>([
      _checkDeviceSecurity(reasons),
      _checkLocationTrust(reasons),
    ]);

    final devMode =
        await _safeCall(() => SafeDevice.isDevelopmentModeEnable) ?? false;

    return DeviceIntegrityResult(
      passed: reasons.isEmpty,
      reasons: reasons.toList(),
      developerModeEnabled: devMode,
    );
  }

  /// Run before every field visit check-in / GPS ping.
  static Future<void> assertLocationTrust() async {
    if (!Platform.isAndroid) return;
    final reasons = <String>{};
    await _checkLocationTrust(reasons);
    if (reasons.isNotEmpty) {
      throw reasons.first;
    }
  }

  static Future<void> _checkDeviceSecurity(Set<String> reasons) async {
    final rooted = await _safeCall(() => SafeDevice.isJailBroken) ?? false;
    if (rooted) reasons.add(rootedReason);

    final isRealDevice = await _safeCall(() => SafeDevice.isRealDevice) ?? true;
    if (!isRealDevice) reasons.add(emulatorReason);

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (!androidInfo.isPhysicalDevice) {
        reasons.add(emulatorReason);
      }
    } catch (_) {}
  }

  static Future<void> _checkLocationTrust(Set<String> reasons) async {
    final safeDeviceMock =
        await _safeCall(() => SafeDevice.isMockLocation) ?? false;
    if (safeDeviceMock) {
      reasons.add(mockLocationReason);
      return;
    }

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && lastKnown.isMocked) {
        reasons.add(mockLocationReason);
      }
    } catch (_) {}
  }

  static Future<T?> _safeCall<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }
}

/// Returns [position] or throws if the OS marks it as mocked.
Future<Position> assertRealPosition(Position position) async {
  if (position.isMocked) {
    throw DeviceIntegrityService.mockLocationReason;
  }
  return position;
}
