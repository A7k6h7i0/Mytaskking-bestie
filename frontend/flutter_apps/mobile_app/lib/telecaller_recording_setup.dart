import 'package:shared_preferences/shared_preferences.dart';

/// Persists telecaller call-recording onboarding + linked storage folder.
class TelecallerRecordingSetup {
  TelecallerRecordingSetup._();

  static const _completeKey = 'telecaller_recording_setup_v1';
  static const _folderUriKey = 'telecaller_recording_folder_uri';
  static const _treeUriKey = 'telecaller_recording_tree_uri';
  static const _folderLabelKey = 'telecaller_recording_folder_label';
  static const _audioCountKey = 'telecaller_recording_audio_count';
  static const _lastUploadedPathKey = 'telecaller_recording_last_path';
  static const _lastUploadedMsKey = 'telecaller_recording_last_ms';

  static bool _complete = false;
  static String? _folderUri;
  static String? _treeUri;
  static String? _folderLabel;
  static int _audioCount = 0;
  static String? _lastUploadedPath;
  static int? _lastUploadedModifiedMs;
  static bool _loaded = false;

  static bool get isLoaded => _loaded;
  static bool get isComplete => _complete;
  static String? get folderUri => _folderUri;
  static String? get treeUri => _treeUri;
  static String? get folderLabel => _folderLabel;
  static int get audioCount => _audioCount;
  static String? get lastUploadedPath => _lastUploadedPath;
  static int? get lastUploadedModifiedMs => _lastUploadedModifiedMs;

  static bool get hasLinkedStorage =>
      (_treeUri != null && _treeUri!.isNotEmpty) ||
      (_folderUri != null && _folderUri!.isNotEmpty);

  /// True when a folder (not a one-off test file) is linked for auto-scan.
  static bool get hasLinkedFolder =>
      (_treeUri != null && _treeUri!.isNotEmpty) ||
      (_folderUri != null &&
          _folderUri!.isNotEmpty &&
          !_folderUri!.startsWith('content://'));

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _complete = prefs.getBool(_completeKey) ?? false;
    _folderUri = prefs.getString(_folderUriKey);
    _treeUri = prefs.getString(_treeUriKey);
    _folderLabel = prefs.getString(_folderLabelKey);
    _audioCount = prefs.getInt(_audioCountKey) ?? 0;
    _lastUploadedPath = prefs.getString(_lastUploadedPathKey);
    _lastUploadedModifiedMs = prefs.getInt(_lastUploadedMsKey);
    _loaded = true;
  }

  /// Legacy path-only link (file_picker path).
  static Future<void> setFolderUri(String? uri) async {
    _folderUri = uri;
    final prefs = await SharedPreferences.getInstance();
    if (uri == null || uri.isEmpty) {
      await prefs.remove(_folderUriKey);
    } else {
      await prefs.setString(_folderUriKey, uri);
    }
  }

  /// SAF tree URI from native folder picker (preferred on Android).
  static Future<void> setLinkedFolder({
    required String treeUri,
    required String displayName,
    required int audioCount,
  }) async {
    _treeUri = treeUri;
    _folderLabel = displayName;
    _audioCount = audioCount;
    _folderUri = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_treeUriKey, treeUri);
    await prefs.setString(_folderLabelKey, displayName);
    await prefs.setInt(_audioCountKey, audioCount);
    await prefs.remove(_folderUriKey);
  }

  /// Single recording file URI from native or file picker.
  static Future<void> setLinkedFile({
    required String fileUri,
    required String displayName,
  }) async {
    _treeUri = null;
    _folderUri = fileUri;
    _folderLabel = displayName;
    _audioCount = 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderUriKey, fileUri);
    await prefs.setString(_folderLabelKey, displayName);
    await prefs.setInt(_audioCountKey, 1);
    await prefs.remove(_treeUriKey);
  }

  static Future<void> markLastUploaded(String uriOrPath, int modifiedMs) async {
    _lastUploadedPath = uriOrPath;
    _lastUploadedModifiedMs = modifiedMs;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUploadedPathKey, uriOrPath);
    await prefs.setInt(_lastUploadedMsKey, modifiedMs);
  }

  static Future<void> markComplete() async {
    _complete = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completeKey, true);
  }

  static Future<void> reset() async {
    _complete = false;
    _folderUri = null;
    _treeUri = null;
    _folderLabel = null;
    _audioCount = 0;
    _lastUploadedPath = null;
    _lastUploadedModifiedMs = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_completeKey);
    await prefs.remove(_folderUriKey);
    await prefs.remove(_treeUriKey);
    await prefs.remove(_folderLabelKey);
    await prefs.remove(_audioCountKey);
    await prefs.remove(_lastUploadedPathKey);
    await prefs.remove(_lastUploadedMsKey);
  }
}
