import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_mobile/screens.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_runtime.dart';

class DesktopWorkActivityAgent {
  static const _defaultActivityInterval = Duration(minutes: 5);
  static const _minActivityInterval = Duration(minutes: 2);
  static const _maxActivityInterval = Duration(hours: 1);

  Timer? _timer;
  Duration _activityInterval = _defaultActivityInterval;
  bool _running = false;
  bool _disposed = false;

  void start(BuildContext context, WidgetRef ref) {
    if (!Platform.isWindows && !Platform.isLinux) return;
    _disposed = false;
    _timer?.cancel();
    _scheduleNext(context, ref, _activityInterval);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleNext(BuildContext context, WidgetRef ref, Duration delay) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(delay, () => _tick(context, ref));
  }

  Future<void> _tick(BuildContext context, WidgetRef ref) async {
    if (_disposed) return;
    if (_running) {
      _scheduleNext(context, ref, _activityInterval);
      return;
    }
    _running = true;
    try {
      final api = ref.read(apiProvider);
      final state = await api.workActivityState();
      _activityInterval = _normalizedInterval(
        (state['intervalSeconds'] as num?)?.toInt(),
      );
      if (state['shouldTrack'] != true) return;

      final captureSeconds = (state['captureSeconds'] as num?)?.toInt() ?? 5;
      final promptSeconds = (state['promptSeconds'] as num?)?.toInt() ?? 30;
      final startedAt = DateTime.now();
      String? fileId;
      String? clipUrl;
      String status = 'WORKING';
      String? captureError;

      try {
        final clip = await _recordClip(captureSeconds);
        final asset = await api.uploadFile(
          bytes: clip.bytes,
          filename: clip.filename,
          mimeType: clip.mimeType,
        );
        fileId = asset['id']?.toString();
        clipUrl = asset['url']?.toString();
      } catch (e) {
        captureError = e.toString();
        status = 'CAPTURE_FAILED';
      }

      if (!context.mounted) return;
      await _bringPromptToFront();
      if (!context.mounted) return;
      final promptShownAt = DateTime.now();
      String? note;
      try {
        note = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => WorkActivityPrompt(seconds: promptSeconds),
        );
      } finally {
        await _releasePromptFocus();
      }
      final promptRespondedAt = DateTime.now();

      await api.createWorkActivityClip(
        fileId: fileId,
        clipUrl: clipUrl,
        note: _noteWithCaptureState(note, captureError),
        status: status,
        platform: Platform.isWindows ? 'windows' : 'linux',
        deviceLabel: Platform.localHostname,
        durationSeconds: captureSeconds,
        captureStartedAt: startedAt,
        captureEndedAt: DateTime.now(),
        promptShownAt: promptShownAt,
        promptRespondedAt: promptRespondedAt,
      );
    } catch (_) {
      // Best effort: activity tracking must never block the employee's work.
    } finally {
      _running = false;
      if (!_disposed && context.mounted) {
        _scheduleNext(context, ref, _activityInterval);
      }
    }
  }

  Duration _normalizedInterval(int? seconds) {
    final value = seconds ?? _defaultActivityInterval.inSeconds;
    final duration = Duration(seconds: value);
    if (duration < _minActivityInterval) return _minActivityInterval;
    if (duration > _maxActivityInterval) return _maxActivityInterval;
    return duration;
  }

  Future<void> _bringPromptToFront() async {
    try {
      await DesktopRuntime.revealAgentWindow();
      await windowManager.setAlwaysOnTop(true);
    } catch (_) {
      // Best effort: tracking should still continue if the window manager fails.
    }
  }

  Future<void> _releasePromptFocus() async {
    try {
      await windowManager.setAlwaysOnTop(false);
      if (DesktopRuntime.hideOnClose) {
        await DesktopRuntime.hideWindowToBackground();
      }
    } catch (_) {}
  }

  String _noteWithCaptureState(String? note, String? captureError) {
    final clean = (note ?? '').trim();
    if (captureError == null) return clean.isEmpty ? 'working' : clean;
    const suffix = 'Capture unavailable: built-in desktop capture failed.';
    return clean.isEmpty ? suffix : '$clean\n$suffix';
  }

  Future<_ActivityCaptureAsset> _recordClip(int seconds) async {
    final safeSeconds = seconds.clamp(1, 30).toInt();
    if (Platform.isWindows) {
      return _recordWindowsReplay(safeSeconds);
    }
    throw UnsupportedError(
      'Built-in desktop capture is currently available on Windows only.',
    );
  }

  Future<_ActivityCaptureAsset> _recordWindowsReplay(int seconds) async {
    final frameCount = seconds.clamp(2, 8).toInt();
    final delayMs =
        ((seconds * 1000) / frameCount).round().clamp(450, 1400).toInt();
    final outputDir = await Directory.systemTemp.createTemp('mtk-work-');
    try {
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          _windowsCaptureScript(
            outputDir.path,
            frameCount: frameCount,
            delayMs: delayMs,
            maxWidth: 1280,
          ),
        ],
      );
      if (result.exitCode != 0) {
        throw StateError(
          'desktop capture failed with exit code ${result.exitCode}',
        );
      }
      final frames = await outputDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.png'))
          .cast<File>()
          .toList();
      frames.sort((a, b) => a.path.compareTo(b.path));
      if (frames.isEmpty) {
        throw StateError('desktop capture did not produce any frames');
      }
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

  String _windowsCaptureScript(
    String outputDir, {
    required int frameCount,
    required int delayMs,
    required int maxWidth,
  }) {
    final dir = _ps(outputDir);
    return r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$OutputDir = ''' +
        dir +
        r'''
$FrameCount = ''' +
        '$frameCount' +
        r'''
$DelayMs = ''' +
        '$delayMs' +
        r'''
$MaxWidth = ''' +
        '$maxWidth' +
        r'''
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$scale = if ($bounds.Width -gt $MaxWidth) { $MaxWidth / [double]$bounds.Width } else { 1.0 }
$targetWidth = [Math]::Max(1, [int][Math]::Round($bounds.Width * $scale))
$targetHeight = [Math]::Max(1, [int][Math]::Round($bounds.Height * $scale))
[System.IO.Directory]::CreateDirectory($OutputDir) | Out-Null
for ($i = 0; $i -lt $FrameCount; $i++) {
  $framePath = Join-Path $OutputDir ('frame-{0:D2}.png' -f $i)
  $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $graphics = [System.Drawing.Graphics]::FromImage($bmp)
  $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  if ($scale -lt 0.999) {
    $scaled = New-Object System.Drawing.Bitmap $targetWidth, $targetHeight
    $scaledGraphics = [System.Drawing.Graphics]::FromImage($scaled)
    $scaledGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $scaledGraphics.DrawImage($bmp, 0, 0, $targetWidth, $targetHeight)
    $scaled.Save($framePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $scaledGraphics.Dispose()
    $scaled.Dispose()
  } else {
    $bmp.Save($framePath, [System.Drawing.Imaging.ImageFormat]::Png)
  }
  $graphics.Dispose()
  $bmp.Dispose()
  if ($i -lt ($FrameCount - 1)) {
    Start-Sleep -Milliseconds $DelayMs
  }
}
''';
  }

  String _ps(String value) => "'${value.replaceAll("'", "''")}'";

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
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MyTaskKing Work Capture</title>
  <style>
    :root { color-scheme: dark; }
    body {
      margin: 0;
      font-family: "Segoe UI", sans-serif;
      background: radial-gradient(circle at top, #17345f 0%, #08111f 58%, #04070d 100%);
      color: #eef4ff;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
      box-sizing: border-box;
    }
    .shell {
      width: min(1100px, 100%);
      background: rgba(7, 15, 27, 0.84);
      border: 1px solid rgba(110, 164, 255, 0.26);
      border-radius: 22px;
      overflow: hidden;
      box-shadow: 0 30px 80px rgba(0, 0, 0, 0.45);
      backdrop-filter: blur(14px);
    }
    .topbar {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      align-items: center;
      padding: 18px 22px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.08);
      background: linear-gradient(180deg, rgba(23, 42, 74, 0.88), rgba(7, 15, 27, 0.7));
    }
    .title {
      font-size: 18px;
      font-weight: 700;
      letter-spacing: 0.2px;
    }
    .meta {
      color: #9db0d3;
      font-size: 13px;
    }
    .stage {
      padding: 18px;
      background: linear-gradient(180deg, rgba(17, 33, 60, 0.55), rgba(6, 12, 21, 0.94));
    }
    img {
      width: 100%;
      display: block;
      border-radius: 14px;
      background: #02060c;
    }
    .controls {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 16px 18px 18px;
      flex-wrap: wrap;
    }
    button {
      background: #0e6fff;
      color: white;
      border: 0;
      border-radius: 999px;
      padding: 10px 16px;
      font: inherit;
      font-weight: 600;
      cursor: pointer;
    }
    button.secondary {
      background: rgba(255, 255, 255, 0.08);
      color: #d7e4ff;
    }
    input[type="range"] {
      flex: 1 1 260px;
      accent-color: #54a3ff;
    }
    .frame-label {
      font-size: 13px;
      color: #aabbd8;
      min-width: 130px;
      text-align: right;
    }
  </style>
</head>
<body>
  <div class="shell">
    <div class="topbar">
      <div>
        <div class="title">MyTaskKing Work Capture</div>
        <div class="meta">${frameUrls.length} frames · about ${totalSeconds}s · requested ${seconds}s</div>
      </div>
      <div class="meta" id="clock"></div>
    </div>
    <div class="stage">
      <img id="frame" alt="Desktop capture frame">
    </div>
    <div class="controls">
      <button id="toggle">Pause</button>
      <button class="secondary" id="restart">Restart</button>
      <input id="scrubber" type="range" min="0" max="${frameUrls.length - 1}" value="0">
      <div class="frame-label" id="label">Frame 1 / ${frameUrls.length}</div>
    </div>
  </div>
  <script>
    const frames = $framesJson;
    const delayMs = $delayMs;
    const img = document.getElementById('frame');
    const scrubber = document.getElementById('scrubber');
    const label = document.getElementById('label');
    const toggle = document.getElementById('toggle');
    const restart = document.getElementById('restart');
    const clock = document.getElementById('clock');
    let index = 0;
    let timer = null;
    let playing = true;

    function render() {
      img.src = frames[index];
      scrubber.value = index;
      label.textContent = 'Frame ' + (index + 1) + ' / ' + frames.length;
      clock.textContent = new Date().toLocaleString();
    }

    function start() {
      stop();
      timer = setInterval(() => {
        index = (index + 1) % frames.length;
        render();
      }, delayMs);
      playing = true;
      toggle.textContent = 'Pause';
    }

    function stop() {
      if (timer) {
        clearInterval(timer);
        timer = null;
      }
      playing = false;
      toggle.textContent = 'Play';
    }

    toggle.addEventListener('click', () => {
      if (playing) {
        stop();
      } else {
        start();
      }
    });

    restart.addEventListener('click', () => {
      index = 0;
      render();
      start();
    });

    scrubber.addEventListener('input', (event) => {
      index = Number(event.target.value || 0);
      render();
      stop();
    });

    render();
    start();
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
    Navigator.of(context).pop((value ?? _controller.text).trim().isEmpty
        ? 'working'
        : (value ?? _controller.text).trim());
  }

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    return AlertDialog(
      title: Text(_needsNote ? 'What are you working on?' : 'Are you working?'),
      content: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _needsNote ? null : () => _submit('working'),
        child: SizedBox(
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
                      'Click anywhere in this window to confirm.',
                      style: TextStyle(color: colors.textSoft),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value:
                          widget.seconds <= 0 ? 0 : _remaining / widget.seconds,
                    ),
                    const SizedBox(height: 8),
                    Text('Message box opens in $_remaining seconds.'),
                  ],
                ),
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
