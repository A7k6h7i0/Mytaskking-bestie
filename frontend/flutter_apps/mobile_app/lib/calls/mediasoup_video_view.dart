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
class MediasoupVideoView extends StatefulWidget {
  const MediasoupVideoView({
    super.key,
    required this.stream,
    this.mirror = false,
    this.objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  });

  final MediaStream stream;
  final bool mirror;
  final RTCVideoViewObjectFit objectFit;

  @override
  State<MediasoupVideoView> createState() => _MediasoupVideoViewState();
}

class _MediasoupVideoViewState extends State<MediasoupVideoView> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _ready = false;
  int _audioTracks = 0;
  int _videoTracks = 0;
  String? _streamId;

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
    await _bindStream();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _bindStream() async {
    _streamId = widget.stream.id;
    _audioTracks = widget.stream.getAudioTracks().length;
    _videoTracks = widget.stream.getVideoTracks().length;
    for (final track in widget.stream.getAudioTracks()) {
      track.enabled = true;
      try {
        await Helper.setVolume(1.0, track);
      } catch (_) {}
    }
    for (final track in widget.stream.getVideoTracks()) {
      track.enabled = true;
    }
    _renderer.srcObject = widget.stream;
    try {
      await _renderer.setVolume(1.0);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant MediasoupVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final audioCount = widget.stream.getAudioTracks().length;
    final videoCount = widget.stream.getVideoTracks().length;
    if (oldWidget.stream.id != widget.stream.id ||
        widget.stream.id != _streamId ||
        audioCount != _audioTracks ||
        videoCount != _videoTracks) {
      unawaited(_bindStream());
    }
  }

  @override
  void dispose() {
    _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const SizedBox(width: 4, height: 4);
    }
    return RTCVideoView(
      _renderer,
      mirror: widget.mirror,
      objectFit: widget.objectFit,
    );
  }
}
