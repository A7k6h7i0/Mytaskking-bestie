import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:proximity_sensor/proximity_sensor.dart';

/// WhatsApp-style ear proximity for voice calls.
///
/// Android uses a native [PROXIMITY_SCREEN_OFF_WAKE_LOCK] plus sensor events
/// (Vivo / virtual-sensor devices often ignore the plugin-only path).
/// iOS uses the [proximity_sensor] plugin with a black in-app overlay fallback.
class CallProximityController {
  CallProximityController({required void Function(bool isNear) onChanged})
      : _onChanged = onChanged;

  static const _method = MethodChannel('mytaskking/proximity');
  static const _events = EventChannel('mytaskking/proximity_events');

  final void Function(bool isNear) _onChanged;
  StreamSubscription<dynamic>? _nativeSub;
  StreamSubscription<dynamic>? _pluginSub;
  bool _running = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    if (Platform.isAndroid) {
      try {
        await _method.invokeMethod<void>('enable');
      } catch (_) {
        await ProximitySensor.setProximityScreenOff(true).catchError((_) {});
      }
      _nativeSub = _events.receiveBroadcastStream().listen((event) {
        _onChanged(_eventIsNear(event));
      });
      return;
    }

    await ProximitySensor.setProximityScreenOff(true).catchError((_) {});
    _pluginSub = ProximitySensor.events.listen((event) {
      _onChanged(_eventIsNear(event));
    });
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _nativeSub?.cancel();
    _nativeSub = null;
    await _pluginSub?.cancel();
    _pluginSub = null;
    if (Platform.isAndroid) {
      try {
        await _method.invokeMethod<void>('disable');
      } catch (_) {
        await ProximitySensor.setProximityScreenOff(false).catchError((_) {});
      }
    } else {
      await ProximitySensor.setProximityScreenOff(false).catchError((_) {});
    }
    _onChanged(false);
  }

  static bool _eventIsNear(dynamic event) {
    if (event is bool) return event;
    if (event is num) return event > 0;
    return event.toString() == 'true' || event.toString() == '1';
  }
}
