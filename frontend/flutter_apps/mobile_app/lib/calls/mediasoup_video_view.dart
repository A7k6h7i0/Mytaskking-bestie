import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Renders a WebRTC [MediaStream] from a mediasoup session.
///
/// On mobile, remote **audio** is played through [RTCVideoRenderer] even when
/// there is no video track — keep this widget mounted for voice calls (same
/// role as HTML `<video autoplay playsinline>`).
///
/// Only one [RTCVideoRenderer] may bind a given [MediaStream] at a time.
/// Dual-binding the same stream blanks remote video (Android).
///
/// Prefer binding mediasoup [Consumer.stream] directly — re-wrapping tracks
/// with [createLocalMediaStream] often leaves remote video black.
///
/// Android front-camera frames are often delivered landscape; when the UI is
/// portrait we auto-rotate 90° CCW so peers see upright video (not sideways
/// or upside-down). Local preview should keep [autoCorrectOrientation] false
/// and only use [mirror] for the front camera.
class MediasoupVideoView extends StatefulWidget {
  const MediasoupVideoView({
    super.key,
    required this.stream,
    this.mirror = false,
    this.objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    this.autoCorrectOrientation = true,
  });

  final MediaStream stream;
  final bool mirror;
  final RTCVideoViewObjectFit objectFit;
  /// When true (default for remotes), landscape buffers in a portrait layout
  /// are rotated 90° CCW. Local preview should pass false.
  final bool autoCorrectOrientation;

  @override
  State<MediasoupVideoView> createState() => _MediasoupVideoViewState();
}

class _MediasoupVideoViewState extends State<MediasoupVideoView> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _ready = false;
  int _audioTracks = 0;
  int _videoTracks = 0;
  String? _streamId;
  String? _trackFingerprint;
  int _bindGen = 0;
  int _quarterTurns = 0;

  String _fingerprint(MediaStream stream) {
    final ids = <String>[
      for (final t in stream.getVideoTracks()) t.id ?? 'v',
      for (final t in stream.getAudioTracks()) t.id ?? 'a',
    ];
    return ids.join('|');
  }

  void _onRendererUpdate() {
    if (!mounted || !widget.autoCorrectOrientation) return;
    final w = _renderer.videoWidth;
    final h = _renderer.videoHeight;
    if (w <= 0 || h <= 0) return;
    // Landscape buffer in a portrait call UI → straighten.
    // Android front-camera / WebRTC buffers need 90° CCW (quarterTurns: 3).
    // 90° CW (1) was leaving the peer upside-down / inverted.
    final needsRotate = w > h;
    final next = needsRotate ? 3 : 0;
    if (next != _quarterTurns) {
      setState(() => _quarterTurns = next);
    }
  }

  @override
  void initState() {
    super.initState();
    _renderer.onResize = _onRendererUpdate;
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
    await _bindStream();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _bindStream() async {
    final gen = ++_bindGen;
    final stream = widget.stream;
    _streamId = stream.id;
    _audioTracks = stream.getAudioTracks().length;
    _videoTracks = stream.getVideoTracks().length;
    _trackFingerprint = _fingerprint(stream);

    for (final track in stream.getAudioTracks()) {
      track.enabled = true;
      try {
        await Helper.setVolume(1.0, track);
      } catch (_) {}
    }
    for (final track in stream.getVideoTracks()) {
      track.enabled = true;
    }

    _renderer.srcObject = null;
    if (!mounted || gen != _bindGen) return;
    await Future<void>.delayed(const Duration(milliseconds: 32));
    if (!mounted || gen != _bindGen) return;
    _renderer.srcObject = stream;
    try {
      await _renderer.setVolume(1.0);
    } catch (_) {}

    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted || gen != _bindGen) return;
    if (_renderer.srcObject != stream) {
      _renderer.srcObject = stream;
    }
    _onRendererUpdate();
    if (mounted && gen == _bindGen) setState(() {});
  }

  @override
  void didUpdateWidget(covariant MediasoupVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final audioCount = widget.stream.getAudioTracks().length;
    final videoCount = widget.stream.getVideoTracks().length;
    final fp = _fingerprint(widget.stream);
    if (oldWidget.stream.id != widget.stream.id ||
        widget.stream.id != _streamId ||
        audioCount != _audioTracks ||
        videoCount != _videoTracks ||
        fp != _trackFingerprint) {
      unawaited(_bindStream());
    }
  }

  @override
  void dispose() {
    _bindGen++;
    _renderer.onResize = null;
    _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const SizedBox(width: 4, height: 4);
    }
    Widget video = RTCVideoView(
      _renderer,
      mirror: widget.mirror,
      objectFit: widget.objectFit,
    );
    if (_quarterTurns != 0) {
      video = RotatedBox(quarterTurns: _quarterTurns, child: video);
    }
    return video;
  }
}
