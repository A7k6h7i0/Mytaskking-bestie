import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'screens/call_screen.dart';

/// Ends an active MyTaskKing call when WhatsApp, cellular, or other telecom
/// calls take over the device audio session.
class ExternalCallGuard {
  ExternalCallGuard._();

  static const _channel = MethodChannel('mytaskking/external_call');
  static const _events = EventChannel('mytaskking/external_call_events');

  static StreamSubscription<dynamic>? _eventSub;
  static VoidCallback? _onExternalRinging;
  static Future<void> Function()? _onExternalAccepted;

  /// Optional UI hook (CallScreen) for "another call is ringing" warnings.
  static VoidCallback? onRingingUi;
  static bool _monitoring = false;
  static bool _externalRinging = false;
  static bool _ending = false;

  static bool get externalRinging => _externalRinging;

  static void init({
    VoidCallback? onExternalRinging,
    required Future<void> Function() onExternalAccepted,
  }) {
    _onExternalRinging = onExternalRinging;
    _onExternalAccepted = onExternalAccepted;
    _eventSub ??= _events.receiveBroadcastStream().listen(_onNativeEvent);
    CallSession.revision.addListener(_syncMonitoring);
    _syncMonitoring();
  }

  static void dispose() {
    CallSession.revision.removeListener(_syncMonitoring);
    unawaited(_eventSub?.cancel());
    _eventSub = null;
    unawaited(_setMonitoring(false));
  }

  static void _syncMonitoring() {
    final shouldMonitor = CallSession.isActive;
    if (shouldMonitor == _monitoring) return;
    unawaited(_setMonitoring(shouldMonitor));
  }

  static Future<void> _setMonitoring(bool enabled) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _monitoring = enabled;
    if (!enabled) {
      _externalRinging = false;
    }
    try {
      await _channel.invokeMethod<void>(enabled ? 'startMonitoring' : 'stopMonitoring');
    } catch (_) {}
  }

  static void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type']?.toString();
    if (type == 'ringing') {
      if (!CallSession.isActive || _ending) return;
      _externalRinging = true;
      _onExternalRinging?.call();
      onRingingUi?.call();
      return;
    }
    if (type == 'accepted') {
      unawaited(_handleAccepted());
    }
  }

  /// When another call is ringing and the user switches to answer it, end MTK.
  static void notifyAppBackgroundedDuringCall() {
    if (!CallSession.isActive || !_externalRinging || _ending) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      _channel.invokeMethod<void>('notifyAppBackgrounded');
    } catch (_) {}
    unawaited(_handleAccepted());
  }

  static Future<void> _handleAccepted() async {
    if (!CallSession.isActive || _ending) return;
    _ending = true;
    _externalRinging = false;
    try {
      await _onExternalAccepted?.call();
    } finally {
      _ending = false;
      await _setMonitoring(false);
    }
  }
}
