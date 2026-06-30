import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_mobile/screens.dart';

class DesktopWorkActivityAgent {
  Timer? _timer;
  bool _running = false;

  void start(BuildContext context, WidgetRef ref) {
    if (!Platform.isWindows && !Platform.isLinux) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) {
      _tick(context, ref);
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick(BuildContext context, WidgetRef ref) async {
    if (_running) return;
    _running = true;
    try {
      final api = ref.read(apiProvider);
      final state = await api.workActivityState();
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
        final bytes = await clip.readAsBytes();
        final asset = await api.uploadFile(
          bytes: bytes,
          filename: clip.uri.pathSegments.last,
          mimeType: 'video/mp4',
        );
        fileId = asset['id']?.toString();
        clipUrl = asset['url']?.toString();
        try {
          await clip.delete();
        } catch (_) {}
      } catch (e) {
        captureError = e.toString();
        status = 'CAPTURE_FAILED';
      }

      if (!context.mounted) return;
      final promptShownAt = DateTime.now();
      final note = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => WorkActivityPrompt(seconds: promptSeconds),
      );
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
    }
  }

  String _noteWithCaptureState(String? note, String? captureError) {
    final clean = (note ?? '').trim();
    if (captureError == null) return clean.isEmpty ? 'working' : clean;
    const suffix = 'Capture unavailable: ffmpeg desktop recording failed.';
    return clean.isEmpty ? suffix : '$clean\n$suffix';
  }

  Future<File> _recordClip(int seconds) async {
    final safeSeconds = seconds.clamp(1, 30);
    final dir = Directory.systemTemp;
    final path =
        '${dir.path}${Platform.pathSeparator}mytaskking-work-${DateTime.now().millisecondsSinceEpoch}.mp4';
    final args = Platform.isWindows
        ? [
            '-y',
            '-f',
            'gdigrab',
            '-draw_mouse',
            '1',
            '-framerate',
            '8',
            '-t',
            '$safeSeconds',
            '-i',
            'desktop',
            '-an',
            '-vf',
            'scale=1280:-2',
            '-vcodec',
            'libx264',
            '-preset',
            'ultrafast',
            '-pix_fmt',
            'yuv420p',
            path,
          ]
        : [
            '-y',
            '-f',
            'x11grab',
            '-draw_mouse',
            '1',
            '-framerate',
            '8',
            '-t',
            '$safeSeconds',
            '-i',
            Platform.environment['DISPLAY'] ?? ':0.0',
            '-an',
            '-vf',
            'scale=1280:-2',
            '-vcodec',
            'libx264',
            '-preset',
            'ultrafast',
            '-pix_fmt',
            'yuv420p',
            path,
          ];
    final result = await Process.run('ffmpeg', args);
    final file = File(path);
    if (result.exitCode != 0 ||
        !await file.exists() ||
        await file.length() == 0) {
      throw StateError('ffmpeg failed with exit code ${result.exitCode}');
    }
    return file;
  }
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
