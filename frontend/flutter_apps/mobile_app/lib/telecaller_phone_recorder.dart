import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Android-only mic capture while the telecaller is in the system phone app.
/// Records ambient/speaker audio — not guaranteed full call-line capture.
class TelecallerPhoneRecorder {
  TelecallerPhoneRecorder._();

  static final TelecallerPhoneRecorder instance = TelecallerPhoneRecorder._();
  static const _channel = MethodChannel('mytaskking/telecaller_recording');

  final AudioRecorder _recorder = AudioRecorder();
  String? _path;
  bool _active = false;

  static bool get supported => Platform.isAndroid;

  bool get isActive => _active;

  Future<bool> start(String callId) async {
    if (!supported || _active) return false;
    if (!await _recorder.hasPermission()) return false;

    final dir = await getApplicationDocumentsDirectory();
    _path =
        '${dir.path}/tc_${callId}_${DateTime.now().millisecondsSinceEpoch}.m4a';

    var serviceStarted = false;
    try {
      await _channel.invokeMethod<void>('start', {'callId': callId});
      serviceStarted = true;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _path!,
      );
      _active = true;
      return true;
    } catch (_) {
      _path = null;
      if (serviceStarted) {
        try {
          await _channel.invokeMethod<void>('stop');
        } catch (_) {}
      }
      return false;
    }
  }

  Future<String?> stop() async {
    if (!supported) return null;
    if (!_active) return null;

    _active = false;
    try {
      await _recorder.stop();
    } catch (_) {
      // Best-effort stop if the OS already tore down the recorder.
    }
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}

    final path = _path;
    _path = null;
    return path;
  }

  Future<void> dispose() async {
    if (_active) await stop();
    await _recorder.dispose();
  }
}
