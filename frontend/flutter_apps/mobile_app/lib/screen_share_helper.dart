import 'dart:io';

import 'package:flutter/services.dart';

/// Android 14+ needs a mediaProjection foreground service before Agora screen capture.
class ScreenShareHelper {
  ScreenShareHelper._();

  static const _channel = MethodChannel('mytaskking/screen_share');

  static Future<void> prepare() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {}
  }

  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
