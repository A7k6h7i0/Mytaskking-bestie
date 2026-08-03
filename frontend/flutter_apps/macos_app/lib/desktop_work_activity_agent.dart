import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_mobile/screens.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_native.dart';
import 'desktop_runtime.dart';

/// Registers today's desktop work session (login time + location).
Future<void> registerDesktopWorkSession(WidgetRef ref, {
  double? latitude,
  double? longitude,
  String? address,
}) async {
  if (!Platform.isMacOS) return;
  try {
    final auth = ref.read(authStoreProvider);
    await ref.read(apiProvider).registerDesktopWorkSession(
          sessionId: auth.sessionId,
          latitude: latitude,
          longitude: longitude,
          address: address,
        );
  } catch (_) {
    // Best-effort — tracking must not block sign-in.
  }
}

class DesktopWorkActivityAgent {
  static const _settingsPollInterval = Duration(seconds: 60);
  static const _allowedTrackIntervals = <int>{120, 300, 900, 1800, 3600};

  Timer? _timer;
  int? _intervalSeconds;
  bool _running = false;
  bool _disposed = false;
  BestieApi? _api;
  BuildContext? _context;

  void start(BuildContext context, WidgetRef ref) {
    if (!Platform.isMacOS) return;
    _disposed = false;
    _context = context;
    _api = ref.read(apiProvider);
    _timer?.cancel();
    unawaited(_bootstrapSchedule());
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _api = null;
    _context = null;
    _intervalSeconds = null;
  }

  Future<void> _bootstrapSchedule() async {
    final seconds = await _fetchIntervalSeconds();
    if (_disposed) return;
    if (seconds == null) {
      await _log('settings.interval_missing');
      _scheduleNext(_settingsPollInterval);
      return;
    }
    _intervalSeconds = seconds;
    _scheduleNext(Duration(seconds: seconds));
  }

  void _scheduleNext(Duration delay) {
    if (_disposed) return;
    _timer?.cancel();
    _log('timer.scheduled', {'seconds': delay.inSeconds});
    _timer = Timer(delay, _tick);
  }

  Future<int?> _fetchIntervalSeconds() async {
    final api = _api;
    if (api == null) return null;
    try {
      final state = await api.workActivityState();
      final configured = (state['intervalSeconds'] as num?)?.toInt();
      if (configured != null && _allowedTrackIntervals.contains(configured)) {
        return configured;
      }
    } catch (e) {
      await _log('settings.interval_failed', {'error': e.toString()});
    }
    return null;
  }

  Future<void> _tick() async {
    if (_disposed) return;
    final api = _api;
    if (api == null) return;
    if (_running) {
      _scheduleNext(_intervalDelay());
      return;
    }
    _running = true;
    try {
      await _log('timer.fired');

      final idleSeconds = await DesktopNative.getIdleSeconds();

      final beat = await api.workActivityHeartbeat(
        idleSeconds: idleSeconds,
        platform: 'macos',
        deviceLabel: Platform.localHostname,
      );

      final interval = (beat['intervalSeconds'] as num?)?.toInt();
      if (interval != null && _allowedTrackIntervals.contains(interval)) {
        _intervalSeconds = interval;
      } else if (beat['trackingConfigured'] != true) {
        await _log('tracking.not_configured');
        _scheduleNext(_settingsPollInterval);
        return;
      }

      final shouldTrack = beat['shouldTrack'] == true;
      final shouldCapture = beat['shouldCapture'] == true;
      await _log('heartbeat', {
        'shouldTrack': shouldTrack,
        'shouldCapture': shouldCapture,
        'idleSeconds': idleSeconds,
        'intervalSeconds': _intervalSeconds,
        'workingSeconds': beat['workingSeconds'],
      });

      if (!shouldTrack) {
        return;
      }

      if (shouldCapture) {
        await _runCaptureCycle(
          api,
          captureSeconds: (beat['captureSeconds'] as num?)?.toInt() ?? 5,
          promptSeconds: (beat['promptSeconds'] as num?)?.toInt() ?? 30,
        );
      }
    } catch (e) {
      await _log('tick.failed', {'error': e.toString()});
    } finally {
      _running = false;
      if (!_disposed && _api != null) {
        _scheduleNext(_intervalDelay());
      }
    }
  }

  Duration _intervalDelay() {
    final seconds = _intervalSeconds;
    if (seconds != null && _allowedTrackIntervals.contains(seconds)) {
      return Duration(seconds: seconds);
    }
    return _settingsPollInterval;
  }

  Future<void> _runCaptureCycle(
    BestieApi api, {
    required int captureSeconds,
    required int promptSeconds,
  }) async {
    final startedAt = DateTime.now();
    String? fileId;
    String? clipUrl;
    String status = 'WORKING';
    String? captureError;

    try {
      await _log('capture.clip.start', {'seconds': captureSeconds});
      final clip = await _recordClip(captureSeconds);
      final asset = await api.uploadFile(
        bytes: clip.bytes,
        filename: clip.filename,
        mimeType: clip.mimeType,
      );
      fileId = asset['id']?.toString();
      clipUrl = asset['url']?.toString();
      await _log('capture.clip.success', {'fileId': fileId});
    } catch (e) {
      captureError = e.toString();
      status = 'CAPTURE_FAILED';
      await _log('capture.clip.failed', {'error': captureError});
      try {
        final fallback = await _captureScreenshot();
        final asset = await api.uploadFile(
          bytes: fallback.bytes,
          filename: fallback.filename,
          mimeType: fallback.mimeType,
        );
        fileId = asset['id']?.toString();
        clipUrl = asset['url']?.toString();
        status = 'SCREENSHOT_FALLBACK';
      } catch (fallbackError) {
        await _log('capture.screenshot.failed', {
          'error': fallbackError.toString(),
        });
      }
    }

    final hostContext = _context;
    if (hostContext != null && !hostContext.mounted) return;
    final promptShownAt = DateTime.now();
    String? note;
    try {
      await _log('prompt.show', {'seconds': promptSeconds});
      note = await DesktopNative.showWorkActivityPrompt(
        seconds: promptSeconds,
      );
    } catch (_) {}

    if (note == null || note.trim().isEmpty) {
      await _log('prompt.dismissed_without_response');
      return;
    }

    final promptRespondedAt = DateTime.now();
    await api.createWorkActivityClip(
      fileId: fileId,
      clipUrl: clipUrl,
      note: _noteWithCaptureState(note, captureError, status),
      status: status,
      platform: 'macos',
      deviceLabel: Platform.localHostname,
      durationSeconds: captureSeconds,
      captureStartedAt: startedAt,
      captureEndedAt: DateTime.now(),
      promptShownAt: promptShownAt,
      promptRespondedAt: promptRespondedAt,
    );
    await _log('clip.created', {'status': status, 'fileId': fileId});
  }

  Future<void> _releasePromptFocus() async {
    try {
      await windowManager.setAlwaysOnTop(false);
      if (DesktopRuntime.hideOnClose) {
        await DesktopRuntime.hideWindowToBackground();
      }
    } catch (_) {}
  }

  Future<String?> _showActivityPrompt(BuildContext context, int seconds) async {
    if (Platform.isWindows) {
      return DesktopNative.showWorkActivityPrompt(seconds: seconds);
    }
    if (!context.mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkActivityPrompt(seconds: seconds),
    );
  }

  Future<void> _log(String event, [Map<String, Object?>? details]) async {
    try {
      final base = Platform.environment['HOME'] != null
          ? '${Platform.environment['HOME']}/Library/Caches'
          : Directory.systemTemp.path;
      final dir = Directory('$base${Platform.pathSeparator}MyTaskKing');
      await dir.create(recursive: true);
      final payload = details == null ? '' : ' ${jsonEncode(details)}';
      final line = '${DateTime.now().toIso8601String()} $event$payload\n';
      await File('${dir.path}${Platform.pathSeparator}work_activity_agent.log')
          .writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  String _noteWithCaptureState(
    String? note,
    String? captureError,
    String status,
  ) {
    final clean = (note ?? '').trim();
    if (captureError == null || status != 'CAPTURE_FAILED') {
      return clean.isEmpty ? 'working' : clean;
    }
    const suffix = 'Capture unavailable: built-in desktop capture failed.';
    return clean.isEmpty ? suffix : '$clean\n$suffix';
  }

  Future<_ActivityCaptureAsset> _recordClip(int seconds) async {
    final safeSeconds = seconds.clamp(1, 30).toInt();
    return _recordDesktopReplay(safeSeconds);
  }

  Future<_ActivityCaptureAsset> _recordDesktopReplay(int seconds) async {
    final frameCount = seconds.clamp(2, 8).toInt();
    final delayMs =
        ((seconds * 1000) / frameCount).round().clamp(450, 1400).toInt();
    final frames = await DesktopNative.captureFrames(
      frameCount: frameCount,
      delayMs: delayMs,
      maxWidth: 1280,
    );
    final outputDir = frames.first.parent;
    try {
      frames.sort((a, b) => a.path.compareTo(b.path));
      final html = await _buildReplayHtml(
        frames,
        delayMs: delayMs,
        seconds: seconds,
      );
      return _ActivityCaptureAsset(
        bytes: utf8.encode(html),
        filename:
            'mytaskking-work-${DateTime.now().millisecondsSinceEpoch}.html',
        mimeType: 'text/html',
      );
    } finally {
      try {
        await outputDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<_ActivityCaptureAsset> _captureScreenshot() async {
    final frames = await DesktopNative.captureFrames(
      frameCount: 1,
      delayMs: 0,
      maxWidth: 1280,
    );
    final outputDir = frames.first.parent;
    try {
      final frame = frames.first;
      if (!await frame.exists()) {
        throw StateError('desktop screenshot did not produce a frame');
      }
      return _ActivityCaptureAsset(
        bytes: await frame.readAsBytes(),
        filename:
            'mytaskking-work-shot-${DateTime.now().millisecondsSinceEpoch}.png',
        mimeType: 'image/png',
      );
    } finally {
      try {
        await outputDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<String> _buildReplayHtml(
    List<File> frames, {
    required int delayMs,
    required int seconds,
  }) async {
    final frameUrls = <String>[];
    for (final frame in frames) {
      final bytes = await frame.readAsBytes();
      frameUrls.add('data:image/png;base64,${base64Encode(bytes)}');
    }
    final framesJson = jsonEncode(frameUrls);
    final totalSeconds = (frameUrls.length * delayMs / 1000).toStringAsFixed(1);
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>MyTaskKing Work Capture</title>
  <style>
    body { margin: 0; font-family: "Segoe UI", sans-serif; background: #08111f; color: #eef4ff; }
    .shell { max-width: 1100px; margin: 24px auto; padding: 18px; }
    img { width: 100%; border-radius: 14px; }
  </style>
</head>
<body>
  <div class="shell">
    <h2>MyTaskKing Work Capture</h2>
    <p>${frameUrls.length} frames · about ${totalSeconds}s · requested ${seconds}s</p>
    <img id="frame" alt="Desktop capture frame">
  </div>
  <script>
    const frames = $framesJson;
    const delayMs = $delayMs;
    let index = 0;
    const img = document.getElementById('frame');
    setInterval(() => { index = (index + 1) % frames.length; img.src = frames[index]; }, delayMs);
    img.src = frames[0];
  </script>
</body>
</html>
''';
  }
}

class _ActivityCaptureAsset {
  final List<int> bytes;
  final String filename;
  final String mimeType;

  const _ActivityCaptureAsset({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });
}

class WorkActivityPrompt extends StatefulWidget {
  final int seconds;
  const WorkActivityPrompt({super.key, required this.seconds});

  @override
  State<WorkActivityPrompt> createState() => _WorkActivityPromptState();
}

class _WorkActivityPromptState extends State<WorkActivityPrompt> {
  late int _remaining = widget.seconds;
  late final Timer _timer;
  bool _needsNote = false;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _needsNote) return;
      if (_remaining <= 1) {
        setState(() => _needsNote = true);
        return;
      }
      setState(() => _remaining -= 1);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? value]) {
    final text = (value ?? _controller.text).trim();
    if (_needsNote && text.isEmpty) return;
    Navigator.of(context).pop(text.isEmpty ? 'working' : text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    return AlertDialog(
      title: Text(_needsNote ? 'What are you working on?' : 'Are you working?'),
      content: SizedBox(
        width: 380,
        child: _needsNote
            ? TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  hintText: 'Type a short work update',
                  border: OutlineInputBorder(),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Click I am working or wait for the message box.',
                    style: TextStyle(color: colors.textSoft),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: widget.seconds <= 0 ? 0 : _remaining / widget.seconds,
                  ),
                  const SizedBox(height: 8),
                  Text('Message box opens in $_remaining seconds.'),
                ],
              ),
      ),
      actions: [
        if (!_needsNote)
          FilledButton.icon(
            onPressed: () => _submit('working'),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('I am working'),
          )
        else
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Submit'),
          ),
      ],
    );
  }
}
