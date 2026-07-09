import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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

  /// Disabled — per-key sounds caused typing lag on Android.
  static void playKeyTap() {}

  static Uint8List desktopRingtoneBytes({
    int sampleRate = 22050,
    int seconds = 2,
  }) {
    final samples = sampleRate * seconds;
    final dataSize = samples * 2;
    final bytes = ByteData(44 + dataSize);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    bytes.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final pulse = (t % 1.0) < 0.58 ? 1.0 : 0.0;
      final envelope = pulse * (0.75 + 0.25 * math.sin(2 * math.pi * 4 * t));
      final tone = math.sin(2 * math.pi * 440 * t) * 0.55 +
          math.sin(2 * math.pi * 660 * t) * 0.35;
      bytes.setInt16(
        44 + i * 2,
        (tone * envelope * 32767).round().clamp(-32768, 32767),
        Endian.little,
      );
    }

    return bytes.buffer.asUint8List();
  }
}
