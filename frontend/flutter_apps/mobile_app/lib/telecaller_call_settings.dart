import 'dart:io';

import 'package:flutter/services.dart';

/// Best-effort OEM shortcuts to Phone / call-recording settings (Android).
class TelecallerCallSettings {
  TelecallerCallSettings._();

  static const _channel = MethodChannel('mytaskking/call_settings');

  static Future<bool> openCallRecordingSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok =
          await _channel.invokeMethod<bool>('openCallRecordingSettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
