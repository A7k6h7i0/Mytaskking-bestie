import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Renders a WebRTC [MediaStream] from a mediasoup session.
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

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
    _renderer.srcObject = widget.stream;
    if (mounted) setState(() => _ready = true);
  }

  @override
  void didUpdateWidget(covariant MediasoupVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream.id != widget.stream.id) {
      _renderer.srcObject = widget.stream;
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
      return const ColoredBox(color: Colors.black);
    }
    return RTCVideoView(
      _renderer,
      mirror: widget.mirror,
      objectFit: widget.objectFit,
    );
  }
}
