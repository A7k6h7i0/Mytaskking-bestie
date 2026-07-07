import 'dart:io';

import 'telecaller_recording_setup.dart';
import 'telecaller_recording_storage.dart';

/// Resolves the newest OEM / phone call recording for upload.
class TelecallerOemRecording {
  TelecallerOemRecording._();

  static const _audioExtensions = {
    '.m4a', '.mp3', '.aac', '.wav', '.amr', '.mp4', '.3gp', '.ogg', '.opus',
  };

  static String mimeForPath(String path) {
    final ext = path.toLowerCase().split('.').last;
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

  static Future<OemRecordingHit?> findNewestWithRetry({
    DateTime? modifiedAfter,
    int attempts = 5,
    Duration delay = const Duration(seconds: 1),
  }) async {
    await TelecallerRecordingSetup.load();

    for (var i = 0; i < attempts; i++) {
      final hit = await findNewest(modifiedAfter: modifiedAfter);
      if (hit != null) return hit;
      if (i < attempts - 1) await Future.delayed(delay);
    }
    return null;
  }

  static Future<OemRecordingHit?> findNewest({DateTime? modifiedAfter}) async {
    await TelecallerRecordingSetup.load();
    final skipUri = TelecallerRecordingSetup.lastUploadedPath;
    final skipMs = TelecallerRecordingSetup.lastUploadedModifiedMs;

    if (TelecallerRecordingStorage.supported) {
      final treeUri = TelecallerRecordingSetup.treeUri;

      if (treeUri != null && treeUri.isNotEmpty) {
        final accessible =
            await TelecallerRecordingStorage.verifyTreeAccess(treeUri);
        if (accessible) {
          final hit = await TelecallerRecordingStorage.findNewestRecording(
            treeUri: treeUri,
            modifiedAfter: modifiedAfter,
            skipUri: skipUri,
            skipModifiedMs: skipMs,
          );
          if (hit != null) return hit;
        }
      }

      // MediaStore fallback when no SAF tree linked or tree scan found nothing.
      if (treeUri == null || treeUri.isEmpty) {
        return TelecallerRecordingStorage.findNewestRecording(
          modifiedAfter: modifiedAfter,
          skipUri: skipUri,
          skipModifiedMs: skipMs,
        );
      }
    }

    final legacyPath = TelecallerRecordingSetup.folderUri;
    if (legacyPath != null &&
        legacyPath.isNotEmpty &&
        !legacyPath.startsWith('content://')) {
      return _findNewestOnDisk(
        legacyPath,
        modifiedAfter: modifiedAfter,
        skipUri: skipUri,
        skipMs: skipMs,
      );
    }

    return null;
  }

  static Future<OemRecordingHit?> _findNewestOnDisk(
    String folderOrFilePath, {
    DateTime? modifiedAfter,
    String? skipUri,
    int? skipMs,
  }) async {
    File? best;
    int bestMs = 0;
    String bestKey = '';

    void consider(File file) {
      final lower = file.path.toLowerCase();
      if (!_audioExtensions.any(lower.endsWith)) return;
      if (!file.existsSync()) return;
      final modified = file.lastModifiedSync();
      final ms = modified.millisecondsSinceEpoch;
      if (modifiedAfter != null && modified.isBefore(modifiedAfter)) return;
      final key = file.path;
      if (skipUri != null && skipMs != null && key == skipUri && ms == skipMs) {
        return;
      }
      if (ms > bestMs) {
        bestMs = ms;
        best = file;
        bestKey = key;
      }
    }

    try {
      final type = FileSystemEntity.typeSync(folderOrFilePath);
      if (type == FileSystemEntityType.file) {
        consider(File(folderOrFilePath));
      } else if (type == FileSystemEntityType.directory) {
        await for (final entity in Directory(folderOrFilePath)
            .list(recursive: true, followLinks: false)) {
          if (entity is File) consider(entity);
        }
      }
    } catch (_) {
      return null;
    }

    final file = best;
    if (file == null) return null;
    return OemRecordingHit(
      uri: bestKey,
      displayName: file.path.split(Platform.pathSeparator).last,
      modifiedMs: bestMs,
      size: file.lengthSync(),
      source: 'path',
      mimeType: mimeForPath(file.path),
    );
  }

  static Future<List<int>?> readHitBytes(OemRecordingHit hit) async {
    if (hit.uri.startsWith('content://')) {
      return TelecallerRecordingStorage.readBytes(hit.uri);
    }
    if (hit.source == 'path') {
      try {
        return await File(hit.uri).readAsBytes();
      } catch (_) {
        return null;
      }
    }
    return TelecallerRecordingStorage.readBytes(hit.uri);
  }
}
