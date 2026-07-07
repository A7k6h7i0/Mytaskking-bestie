import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android SAF / MediaStore access for OEM call recordings.
class TelecallerRecordingStorage {
  TelecallerRecordingStorage._();

  static const _channel = MethodChannel('mytaskking/call_recording_storage');

  static bool get supported => Platform.isAndroid;

  /// READ_MEDIA_AUDIO (13+) or READ_EXTERNAL_STORAGE (older).
  static Future<bool> ensureAudioAccess() async {
    if (!supported) return true;
    if (await Permission.audio.isGranted) return true;
    if (await Permission.storage.isGranted) return true;

    var status = await Permission.audio.request();
    if (status.isGranted) return true;
    status = await Permission.storage.request();
    return status.isGranted;
  }

  /// Opens system folder picker (SAF) — persists read access for later scans.
  static Future<Map<String, dynamic>?> pickFolder() async {
    if (!supported) return null;
    try {
      final raw = await _channel.invokeMethod<Map>('pickFolder');
      if (raw == null) return null;
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> pickRecordingFile() async {
    if (!supported) return null;
    try {
      final raw = await _channel.invokeMethod<Map>('pickFile');
      if (raw == null) return null;
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<int> countAudioInTree(String treeUri) async {
    if (!supported) return 0;
    try {
      final n = await _channel.invokeMethod<int>('countAudioInTree', {
        'treeUri': treeUri,
      });
      return n ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> verifyTreeAccess(String treeUri) async {
    if (!supported || treeUri.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('verifyTreeAccess', {
        'treeUri': treeUri,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<OemRecordingHit?> findNewestRecording({
    String? treeUri,
    DateTime? modifiedAfter,
    String? skipUri,
    int? skipModifiedMs,
  }) async {
    if (!supported) return null;
    try {
      final raw = await _channel.invokeMethod<Map>('findNewestRecording', {
        if (treeUri != null) 'treeUri': treeUri,
        'modifiedAfterMs': modifiedAfter?.millisecondsSinceEpoch ?? 0,
        if (skipUri != null) 'skipUri': skipUri,
        if (skipModifiedMs != null) 'skipModifiedMs': skipModifiedMs,
      });
      if (raw == null) return null;
      final map = Map<String, dynamic>.from(raw);
      return OemRecordingHit(
        uri: map['uri'] as String,
        displayName: map['displayName'] as String? ?? 'recording',
        modifiedMs: (map['modifiedMs'] as num?)?.toInt() ?? 0,
        size: (map['size'] as num?)?.toInt() ?? 0,
        source: map['source'] as String? ?? 'unknown',
        mimeType: map['mimeType'] as String? ??
            _mimeForName(map['displayName'] as String? ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>?> readBytes(String uri) async {
    if (!supported) return null;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('readBytes', {
        'uri': uri,
      });
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static String _mimeForName(String name) {
    final ext = name.toLowerCase().split('.').last;
    switch (ext) {
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'aac':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      case 'amr':
        return 'audio/amr';
      case '3gp':
        return 'video/3gpp';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      default:
        return 'application/octet-stream';
    }
  }
}

class OemRecordingHit {
  const OemRecordingHit({
    required this.uri,
    required this.displayName,
    required this.modifiedMs,
    required this.size,
    required this.source,
    required this.mimeType,
  });

  final String uri;
  final String displayName;
  final int modifiedMs;
  final int size;
  final String source;
  final String mimeType;
}
