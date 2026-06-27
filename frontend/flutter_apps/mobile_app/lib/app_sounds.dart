import 'dart:io';

import 'package:flutter/services.dart';

/// WhatsApp-style UI sounds — call end tone + chat key taps.
class AppSounds {
  static const _channel = MethodChannel('mytaskking/sounds');

  static Future<void> playCallEnded() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('playCallEnded');
      } else {
        await SystemSound.play(SystemSoundType.alert);
      }
    } catch (_) {}
  }

  /// Fire-and-forget — must NOT block the UI thread / keyboard.
  static void playKeyTap() {
    try {
      if (Platform.isAndroid) {
        _channel.invokeMethod<void>('playKeyTap');
      } else {
        SystemSound.play(SystemSoundType.click);
      }
    } catch (_) {}
  }
}
