import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:mytaskking_core/mytaskking_core.dart';

/// Saves chat images/videos to the device gallery and documents to Downloads.
class ChatMediaSaver {
  ChatMediaSaver._();

  static final _dio = Dio();

  static Future<void> saveAttachment({
    required BestieApi api,
    required Map<String, dynamic> asset,
  }) async {
    final mime = (asset['mimeType'] ?? '').toString().toLowerCase();
    final name = _safeFilename((asset['originalName'] ?? 'file').toString());
    final bytes = await _downloadAttachmentBytes(api, asset);

    if (mime.startsWith('image/')) {
      await _ensureGalleryAccess();
      await Gal.putImageBytes(
        bytes,
        name: _withExtension(name, '.jpg'),
      );
      return;
    }

    if (mime.startsWith('video/')) {
      await _ensureGalleryAccess();
      final tmp = await _writeTemp(bytes, _withExtension(name, '.mp4'));
      try {
        await Gal.putVideo(tmp.path, album: 'MyTaskKing');
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
      return;
    }

    await _saveToDownloads(bytes, name);
  }

  static Future<void> saveAllAttachments({
    required BestieApi api,
    required List<Map<String, dynamic>> assets,
  }) async {
    for (final asset in assets) {
      await saveAttachment(api: api, asset: asset);
    }
  }

  /// Save a link-preview image or direct image URL to the gallery.
  static Future<void> saveImageUrl(String url, {String? name}) async {
    final bytes = await _downloadUrlBytes(url);
    await _ensureGalleryAccess();
    await Gal.putImageBytes(
      bytes,
      name: _safeFilename(name ?? 'mytaskking-link.jpg'),
    );
  }

  /// Download a URL when it looks like a file (pdf, zip, mp4, etc.).
  static Future<void> saveVideoUrl(String url, {String? name}) async {
    final bytes = await _downloadUrlBytes(url);
    await _ensureGalleryAccess();
    final tmp = await _writeTemp(
      bytes,
      _withExtension(_safeFilename(name ?? 'mytaskking-video.mp4'), '.mp4'),
    );
    try {
      await Gal.putVideo(tmp.path, album: 'MyTaskKing');
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  static Future<void> saveUrlAsFile(String url, {String? name}) async {
    final bytes = await _downloadUrlBytes(url);
    final filename = _safeFilename(
      name ?? p.basename(Uri.parse(url).path).ifEmpty('download'),
    );
    await _saveToDownloads(bytes, filename);
  }

  static bool looksLikeDownloadableFile(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return RegExp(
      r'\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|rar|7z|txt|csv|mp4|mov|mkv|mp3|wav|jpg|jpeg|png|gif|webp)$',
    ).hasMatch(path);
  }

  static Future<Uint8List> _downloadAttachmentBytes(
    BestieApi api,
    Map<String, dynamic> asset,
  ) async {
    final id = asset['id']?.toString();
    final direct = asset['url']?.toString() ?? '';
    if (id != null && id.isNotEmpty) {
      try {
        final url = await api.getFileDownloadUrl(id);
        return _downloadUrlBytes(url);
      } catch (_) {
        if (direct.isNotEmpty) return _downloadUrlBytes(direct);
        rethrow;
      }
    }
    if (direct.isEmpty) throw 'File has no URL';
    return _downloadUrlBytes(direct);
  }

  static Future<Uint8List> _downloadUrlBytes(String url) async {
    final r = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = r.data;
    if (data == null || data.isEmpty) throw 'Download returned empty file';
    return Uint8List.fromList(data);
  }

  static Future<void> _ensureGalleryAccess() async {
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return;
    }
    if (Platform.isIOS) {
      final addOnly = await Permission.photosAddOnly.request();
      if (addOnly.isGranted) return;
      final photos = await Permission.photos.request();
      if (!photos.isGranted && !photos.isLimited) {
        throw 'Photo library permission denied';
      }
      return;
    }
    if (Platform.isAndroid) {
      final photos = await Permission.photos.request();
      if (photos.isGranted || photos.isLimited) return;
      final storage = await Permission.storage.request();
      if (!storage.isGranted) {
        throw 'Storage permission denied';
      }
    }
  }

  static Future<File> _writeTemp(Uint8List bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, _safeFilename(name)));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> _saveToDownloads(Uint8List bytes, String name) async {
    Directory? dir;
    if (Platform.isAndroid || Platform.isIOS) {
      dir = await getDownloadsDirectory();
    }
    dir ??= await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, _safeFilename(name)));
    await file.writeAsBytes(bytes, flush: true);
  }

  static String _safeFilename(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'mytaskking-file' : cleaned;
  }

  static String _withExtension(String name, String ext) {
    final lower = name.toLowerCase();
    if (lower.endsWith(ext)) return name;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return '$base$ext';
  }
}

extension _IfEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
