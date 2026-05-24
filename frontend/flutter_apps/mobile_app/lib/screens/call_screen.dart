import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:permission_handler/permission_handler.dart';

import '../state.dart';

/// Live audio/video call view powered by Agora RTC.
///
/// Two ways to enter:
///   • `/call/:id?mode=voice|video`  — joins an existing call via `GET /calls/:id/token`
///   • `/meeting/:slug?mode=voice|video` — joins a meeting room via `POST /meetings/:slug/token`
class CallScreen extends ConsumerStatefulWidget {
  final String? callId;
  final String? meetingSlug;
  final String mode; // 'voice' or 'video'

  const CallScreen({
    super.key,
    this.callId,
    this.meetingSlug,
    this.mode = 'video',
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  RtcEngine? _engine;
  String _status = 'Preparing…';
  String? _channelName;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  bool _joined = false;
  final Set<int> _remoteUids = {};
  String? _error;

  bool get _isVideo => widget.mode == 'video';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _leaveAndDispose();
    super.dispose();
  }

  Future<void> _leaveAndDispose() async {
    try {
      await _engine?.leaveChannel();
      await _engine?.release();
    } catch (_) { /* engine may already be torn down */ }
    if (widget.callId != null) {
      // Best-effort notify backend we left.
      try { await ref.read(apiProvider).post('/calls/${widget.callId}/leave'); } catch (_) {}
    }
  }

  Future<void> _bootstrap() async {
    try {
      await _requestPermissions();
      final tokenResp = await _fetchToken();
      final appId = tokenResp['appId']?.toString();
      final token = tokenResp['token']?.toString();
      final channel = tokenResp['channelName']?.toString();
      final uidRaw = tokenResp['uid'];

      if (appId == null || token == null || channel == null) {
        throw Exception('Server did not return an Agora token');
      }
      if (appId.isEmpty) {
        throw Exception('Agora is not configured on the server (missing AGORA_APP_ID).');
      }
      setState(() => _channelName = channel);

      final engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(appId: appId));
      _engine = engine;

      engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (conn, elapsed) {
          if (!mounted) return;
          setState(() { _joined = true; _status = 'Connected'; });
        },
        onUserJoined: (conn, remoteUid, elapsed) {
          if (!mounted) return;
          setState(() => _remoteUids.add(remoteUid));
        },
        onUserOffline: (conn, remoteUid, reason) {
          if (!mounted) return;
          setState(() => _remoteUids.remove(remoteUid));
        },
        onError: (err, msg) {
          if (!mounted) return;
          setState(() => _error = 'Agora error: $msg');
        },
      ));

      await engine.enableAudio();
      if (_isVideo) {
        await engine.enableVideo();
        await engine.startPreview();
      }
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await engine.setEnableSpeakerphone(_speakerOn);

      final uid = uidRaw is int ? uidRaw : int.tryParse('$uidRaw') ?? 0;
      await engine.joinChannel(
        token: token,
        channelId: channel,
        uid: uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      // Tell the backend we're in (best-effort).
      if (widget.callId != null) {
        try { await ref.read(apiProvider).post('/calls/${widget.callId}/join'); } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = formatApiError(e); _status = 'Failed'; });
    }
  }

  Future<Map<String, dynamic>> _fetchToken() async {
    final api = ref.read(apiProvider);
    if (widget.callId != null) {
      return api.get('/calls/${widget.callId}/token');
    }
    if (widget.meetingSlug != null) {
      return api.meetingToken(widget.meetingSlug!);
    }
    throw Exception('Missing callId or meetingSlug');
  }

  Future<void> _requestPermissions() async {
    final perms = <Permission>[
      Permission.microphone,
      if (_isVideo) Permission.camera,
    ];
    await perms.request();
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _engine?.muteLocalAudioStream(_muted);
  }

  Future<void> _toggleCamera() async {
    if (!_isVideo) return;
    setState(() => _cameraOff = !_cameraOff);
    await _engine?.muteLocalVideoStream(_cameraOff);
  }

  Future<void> _flipCamera() async {
    if (!_isVideo) return;
    await _engine?.switchCamera();
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speakerOn = !_speakerOn);
    await _engine?.setEnableSpeakerphone(_speakerOn);
  }

  Future<void> _hangup() async {
    await _leaveAndDispose();
    if (mounted) context.go('/chat');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          // remote tiles (or large "calling" placeholder)
          Positioned.fill(child: _remoteSurface()),

          // local preview pip (video mode only)
          if (_isVideo && _joined && !_cameraOff)
            Positioned(
              right: 16, top: 16,
              width: 110, height: 160,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24, width: 1),
                  borderRadius: BorderRadius.circular(BestieTokens.rMd),
                ),
                child: _engine != null
                    ? AgoraVideoView(controller: VideoViewController(
                        rtcEngine: _engine!,
                        canvas: const VideoCanvas(uid: 0),
                      ))
                    : const SizedBox.shrink(),
              ),
            ),

          // header
          Positioned(
            top: 8, left: 8, right: 8,
            child: _header(),
          ),

          // controls
          Positioned(
            bottom: 24, left: 0, right: 0,
            child: _controls(),
          ),
        ]),
      ),
    );
  }

  Widget _header() {
    return Row(children: [
      IconButton(
        icon: const Icon(Icons.expand_more_rounded, color: Colors.white, size: 28),
        onPressed: _hangup,
        tooltip: 'Minimize',
      ),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_channelName ?? 'Connecting…',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: BestieTokens.fwBold,
                letterSpacing: BestieTokens.lsSnug,
              )),
          Text(_status,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      ),
      if (_isVideo)
        IconButton(
          icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
          onPressed: _flipCamera,
          tooltip: 'Flip camera',
        ),
    ]);
  }

  Widget _remoteSurface() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 42),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
          ]),
        ),
      );
    }
    if (_remoteUids.isEmpty || !_isVideo) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_isVideo ? Icons.videocam_outlined : Icons.call_outlined,
              color: Colors.white24, size: 76),
          const SizedBox(height: 16),
          Text(_joined ? 'Waiting for others…' : 'Connecting…',
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ]),
      );
    }
    final firstRemote = _remoteUids.first;
    return AgoraVideoView(controller: VideoViewController.remote(
      rtcEngine: _engine!,
      canvas: VideoCanvas(uid: firstRemote),
      connection: RtcConnection(channelId: _channelName ?? ''),
    ));
  }

  Widget _controls() {
    Widget pill({required IconData icon, required VoidCallback onTap, bool active = false, Color? activeColor}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: active ? (activeColor ?? Colors.white) : Colors.white.withOpacity(0.16),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Icon(icon, color: active ? Colors.black : Colors.white, size: 24),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        pill(
          icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          onTap: _toggleMute,
          active: _muted,
        ),
        if (_isVideo)
          pill(
            icon: _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
            onTap: _toggleCamera,
            active: _cameraOff,
          ),
        pill(
          icon: _speakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
          onTap: _toggleSpeaker,
          active: !_speakerOn,
        ),
        GestureDetector(
          onTap: _hangup,
          child: Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(
              color: BestieTokens.cDanger,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
          ),
        ),
      ]),
    );
  }
}
