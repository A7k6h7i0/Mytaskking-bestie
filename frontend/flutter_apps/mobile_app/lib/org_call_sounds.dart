import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_sounds.dart';

/// Built-in + org-upload call sounds.
///
/// Ringback (caller): org URL → bundled ringing MP3 → desktop synth.
/// Incoming ring (receiver): device default ringtone only (see overlay).
/// Buzzer: org URL → bundled buzzer MP3.
class OrgCallSounds {
  OrgCallSounds._();

  static const ringingAsset = 'assets/sounds/Ringing.mp3.mpeg';
  static const buzzerAsset = 'assets/sounds/Buzzer.mp3.mpeg';

  /// audioplayers expects the path under the assets/ folder.
  static const ringingAssetKey = 'sounds/Ringing.mp3.mpeg';
  static const buzzerAssetKey = 'sounds/Buzzer.mp3.mpeg';

  static String? _buzzerFilePath;

  /// Copy bundled buzzer MP3 to app storage for native playback if needed.
  static Future<void> warmCache() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _buzzerFilePath =
        await _ensureAssetOnDisk(buzzerAsset, 'default_buzzer.mp3');
  }

  static String? get cachedBuzzerPath => _buzzerFilePath;

  static Future<String?> _ensureAssetOnDisk(String asset, String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      if (!await file.exists() || await file.length() == 0) {
        final blob = await rootBundle.load(asset);
        await file.writeAsBytes(blob.buffer.asUint8List(), flush: true);
      }
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> playRinging(
    AudioPlayer player, {
    String? orgUrl,
    ReleaseMode releaseMode = ReleaseMode.loop,
    double volume = 1.0,
  }) async {
    await player.stop();
    await player.setReleaseMode(releaseMode);
    final url = orgUrl?.trim();
    if (url != null && url.isNotEmpty) {
      await player.play(UrlSource(url), volume: volume);
      return;
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await player.play(
        BytesSource(AppSounds.desktopRingtoneBytes()),
        volume: volume,
      );
      return;
    }
    await player.play(AssetSource(ringingAssetKey), volume: volume);
  }

  static Future<void> playBuzzer(
    AudioPlayer player, {
    String? orgUrl,
    double volume = 1.0,
  }) async {
    await player.stop();
    await player.setReleaseMode(ReleaseMode.release);
    final url = orgUrl?.trim();
    if (url != null && url.isNotEmpty) {
      await player.play(UrlSource(url), volume: volume);
      return;
    }
    await player.play(AssetSource(buzzerAssetKey), volume: volume);
  }
}
