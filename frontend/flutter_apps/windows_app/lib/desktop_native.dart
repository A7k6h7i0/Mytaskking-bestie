import 'dart:io';

import 'package:flutter/services.dart';

class DesktopNative {
  static const MethodChannel _channel = MethodChannel('mytaskking/desktop');

  static bool get isSupported => Platform.isWindows;

  static Future<String?> showWorkActivityPrompt({
    required int seconds,
  }) async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('showWorkActivityPrompt', {
      'seconds': seconds,
    });
  }

  static Future<List<File>> captureFrames({
    required int frameCount,
    required int delayMs,
    int maxWidth = 1280,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Native desktop capture is Windows-only.');
    }
    final paths = await _channel.invokeListMethod<String>('captureFrames', {
      'frameCount': frameCount,
      'delayMs': delayMs,
      'maxWidth': maxWidth,
    });
    final files = (paths ?? const <String>[]).map(File.new).toList();
    if (files.isEmpty) {
      throw StateError('Native desktop capture produced no files.');
    }
    return files;
  }
}
