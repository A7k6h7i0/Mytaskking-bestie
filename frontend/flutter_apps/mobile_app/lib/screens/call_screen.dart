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
/// Initialization order matters — Agora throws `AgoraRtcException(-3, ...)`
/// (ERR_NOT_READY) when:
///   • permissions aren't OS-granted before `joinChannel`,
///   • engine methods are called before `initialize()` completes,
///   • the channel profile isn't set on the context, or
///   • the App ID is missing.
/// The setup below avoids all four — request permissions → create engine →
/// initialize (with profile) → enable audio/video → register handlers → join.
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
  bool _sharing = false;
  bool _recording = false;
  final Set<int> _remoteUids = {};
  final Map<int, String> _remoteNames = {};
  String? _error;
  Map<String, dynamic>? _callMeta;

  bool get _isVideo => widget.mode == 'video';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  Future<void> _teardown() async {
    try {
      await _engine?.leaveChannel();
      await _engine?.release();
    } catch (_) { /* engine may already be torn down */ }
    if (widget.callId != null) {
      try { await ref.read(apiProvider).post('/calls/${widget.callId}/leave'); } catch (_) {}
    }
  }

  bool _booting = false;

  Future<void> _bootstrap() async {
    // Re-entrant guard — Riverpod rebuilds during permission prompts can
    // re-trigger initState's handlers. A second engine create while the first
    // is mid-init is one of the documented causes of Agora ERR_NOT_READY (-3).
    if (_booting) return;
    _booting = true;

    // Track which step is in flight so the error message can identify the
    // exact failing call (-3 with a null message is otherwise opaque).
    String step = 'start';
    try {
      // 1. OS-level permissions.
      step = 'permissions';
      final perms = <Permission>[Permission.microphone];
      if (_isVideo) perms.add(Permission.camera);
      final granted = await perms.request();
      final mic = granted[Permission.microphone];
      if (mic != PermissionStatus.granted && mic != PermissionStatus.limited) {
        throw 'Microphone permission denied. Open Settings → Apps → MyTaskKing → Permissions and enable it.';
      }
      if (_isVideo) {
        final cam = granted[Permission.camera];
        if (cam != PermissionStatus.granted && cam != PermissionStatus.limited) {
          throw 'Camera permission denied. Open Settings → Apps → MyTaskKing → Permissions and enable it.';
        }
      }

      // 2. Fetch token + appId from the backend.
      step = 'token-fetch';
      setState(() => _status = 'Connecting…');
      final tokenResp = await _fetchToken();
      _callMeta = tokenResp;
      final appId = tokenResp['appId']?.toString();
      final token = tokenResp['token']?.toString();
      final channel = tokenResp['channelName']?.toString();
      final uidRaw = tokenResp['uid'];
      final disabled = tokenResp['disabled'] == true;

      if (disabled || appId == null || appId.isEmpty) {
        throw 'Agora is not configured on the server. An admin must set AGORA_APP_ID and AGORA_APP_CERTIFICATE in the backend .env.';
      }
      if (token == null || token.isEmpty) {
        throw 'Server returned an empty Agora token. Check the backend logs for token-builder errors.';
      }
      if (channel == null || channel.isEmpty) {
        throw 'Server returned an empty channel name.';
      }
      // Agora App IDs are 32-char hex strings. Reject placeholder values that
      // would otherwise reach the SDK and trigger -3.
      if (appId.length < 16 || appId.toLowerCase().contains('replace-me')) {
        throw 'Server returned an invalid Agora App ID ("$appId"). Replace it with a real Agora project ID.';
      }
      setState(() => _channelName = channel);

      // 3. Create + initialize the engine. `channelProfile` belongs on the
      // engine context — supplying it only via joinChannel options is one of
      // the documented causes of -3 on certain Agora 6.5.x devices.
      step = 'create-engine';
      final engine = createAgoraRtcEngine();
      _engine = engine; // assign early so dispose can release on hot reload

      step = 'initialize';
      await engine.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      // 4. Wire event handlers BEFORE joining so we don't miss state.
      step = 'register-handlers';
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
          setState(() { _remoteUids.remove(remoteUid); _remoteNames.remove(remoteUid); });
        },
        onTokenPrivilegeWillExpire: (conn, t) async {
          try {
            final fresh = await _fetchToken();
            final newToken = fresh['token']?.toString();
            if (newToken != null) await engine.renewToken(newToken);
          } catch (_) {/* user can rejoin */}
        },
        onError: (err, msg) {
          if (!mounted) return;
          setState(() { _error = 'Agora native error ${err.value()}${msg.isNotEmpty ? ' — $msg' : ''}'; });
        },
        onLeaveChannel: (conn, stats) {
          if (!mounted) return;
          setState(() { _joined = false; _status = 'Ended'; });
        },
      ));

      // 5. Media setup — sequential awaits, audio always, video only on demand.
      step = 'enable-audio';
      await engine.enableAudio();

      if (_isVideo) {
        step = 'enable-video';
        await engine.enableVideo();

        step = 'start-preview';
        await engine.startPreview();
      }

      step = 'client-role';
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      // setEnableSpeakerphone before join sometimes throws on Android — try
      // it but don't fail the whole bootstrap on a non-critical setter.
      try {
        step = 'speakerphone';
        await engine.setEnableSpeakerphone(_speakerOn);
      } catch (_) {/* will retry post-join */}

      // 6. Join. Pass the same channel profile here too — belt-and-suspenders.
      step = 'join-channel';
      final uid = uidRaw is int ? uidRaw : int.tryParse('$uidRaw') ?? 0;
      await engine.joinChannel(
        token: token,
        channelId: channel,
        uid: uid,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: true,
          publishCameraTrack: _isVideo,
          autoSubscribeAudio: true,
          autoSubscribeVideo: _isVideo,
        ),
      );

      if (widget.callId != null) {
        try { await ref.read(apiProvider).post('/calls/${widget.callId}/join'); } catch (_) {}
      }
    } on AgoraRtcException catch (e) {
      if (!mounted) return;
      final code = e.code;
      final hint = _hintForAgoraCode(code, step);
      setState(() {
        _error = 'Agora error $code at "$step"${hint != null ? '\n\n$hint' : ''}';
        _status = 'Failed';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '${e.toString()} (during "$step")'; _status = 'Failed'; });
    } finally {
      _booting = false;
    }
  }

  /// Human-readable hint for the most common Agora error codes we hit during
  /// bootstrap. Shown alongside the raw code so the user knows what to do.
  String? _hintForAgoraCode(int code, String step) {
    switch (code) {
      case -2:  return 'Invalid argument passed to Agora. Likely a malformed App ID or channel name.';
      case -3:  return 'Agora SDK is not ready. Usually means the App ID is rejected by Agora, the device denied a permission, or the engine is being re-initialized while a previous instance is still alive. Try: 1) confirm AGORA_APP_ID matches an active Agora project, 2) grant mic/camera in system settings, 3) restart the app.';
      case -7:  return 'Engine not initialized — internal bug.';
      case -17: return 'Already joined this channel. Hangup first and try again.';
      case -101:return 'Invalid App ID — Agora rejected the credentials. Verify AGORA_APP_ID on the server.';
      case -109:return 'Token expired. Re-open the call to fetch a fresh token.';
      case -110:return 'Invalid token — the App Certificate on the server doesn\'t match the App ID, or the uid in the token doesn\'t match the uid passed to joinChannel.';
      default:  return null;
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
    throw 'Missing callId or meetingSlug';
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

  Future<void> _toggleShare() async {
    if (_engine == null) return;
    try {
      if (_sharing) {
        await _engine!.stopScreenCapture();
        setState(() => _sharing = false);
        if (mounted) bestieToast(context, 'Screen share stopped', kind: BestieToastKind.info);
      } else {
        await _engine!.startScreenCapture(const ScreenCaptureParameters2(
          captureVideo: true,
          captureAudio: false,
        ));
        setState(() => _sharing = true);
        if (mounted) bestieToast(context, 'Sharing your screen', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) bestieToast(context, 'Screen share not available',
          body: e.toString(), kind: BestieToastKind.error);
    }
  }

  Future<void> _toggleRecord() async {
    final slug = widget.meetingSlug ?? widget.callId;
    if (slug == null) return;
    setState(() => _recording = !_recording);
    try {
      if (_recording) {
        await ref.read(apiProvider).post('/meetings/$slug/recording/start').catchError((_) => <String, dynamic>{});
        if (mounted) {
          bestieToast(context, 'Recording started',
              body: 'A copy will be saved to Files when the call ends.',
              kind: BestieToastKind.success);
        }
      } else {
        await ref.read(apiProvider).post('/meetings/$slug/recording/stop').catchError((_) => <String, dynamic>{});
        if (mounted) bestieToast(context, 'Recording stopped', kind: BestieToastKind.info);
      }
    } catch (e) {
      setState(() => _recording = !_recording);
      if (mounted) bestieToast(context, 'Recording unavailable',
          body: e.toString(), kind: BestieToastKind.error);
    }
  }

  void _showParticipants() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = BestieColors.of(ctx);
        final participants = <_Participant>[];
        final me = ref.read(authStoreProvider).user;
        if (me != null) {
          participants.add(_Participant(name: me.name, role: 'You', muted: _muted, video: !_cameraOff));
        }
        for (final uid in _remoteUids) {
          participants.add(_Participant(name: _remoteNames[uid] ?? 'Participant', role: 'Remote', muted: false, video: true));
        }
        final invited = ((_callMeta?['call']?['participants'] as List?) ??
            (_callMeta?['participants'] as List?) ?? const []).cast<dynamic>();
        for (final p in invited) {
          if (p is Map) {
            final u = (p['user'] as Map?)?.cast<String, dynamic>();
            final n = (u?['name'] ?? '').toString();
            if (n.isEmpty || n == me?.name) continue;
            if (participants.any((pp) => pp.name == n)) continue;
            participants.add(_Participant(name: n, role: 'Invited', muted: true, video: false));
          }
        }
        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: c.borderStrong,
                borderRadius: BorderRadius.circular(BestieTokens.rPill),
              ),
            ),
            Row(children: [
              Text('Participants (${participants.length})',
                  style: TextStyle(
                    fontSize: 16, fontWeight: BestieTokens.fwBold, color: c.text,
                    letterSpacing: BestieTokens.lsTight,
                  )),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close_rounded, color: c.textMuted),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ]),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in participants)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        BestieAvatar(name: p.name, isClient: false, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(p.name,
                                  style: TextStyle(color: c.text, fontWeight: BestieTokens.fwSemibold)),
                              Text(p.role,
                                  style: TextStyle(color: c.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                        Icon(p.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            size: 16, color: p.muted ? c.danger : c.success),
                        const SizedBox(width: 12),
                        Icon(p.video ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                            size: 16, color: p.video ? c.success : c.textFaint),
                      ]),
                    ),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  Future<void> _hangup() async {
    await _teardown();
    if (mounted) context.go('/chat');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(child: _remoteSurface()),
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
          Positioned(top: 8, left: 8, right: 8, child: _header()),
          Positioned(bottom: 24, left: 0, right: 0, child: _controls()),
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
                color: Colors.white, fontSize: 15,
                fontWeight: BestieTokens.fwBold, letterSpacing: BestieTokens.lsSnug,
              )),
          Row(children: [
            if (_recording) Container(
              margin: const EdgeInsets.only(right: 6, top: 2),
              width: 8, height: 8,
              decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
            ),
            Text(_recording ? 'Recording · $_status' : _status,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ]),
      ),
      IconButton(
        icon: const Icon(Icons.people_alt_rounded, color: Colors.white),
        tooltip: 'Participants',
        onPressed: _showParticipants,
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
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () { setState(() { _error = null; }); _bootstrap(); },
              child: const Text('Retry'),
            ),
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
          Text(_joined ? 'Waiting for others…' : _status,
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
    Widget pill({
      required IconData icon, required VoidCallback onTap,
      bool active = false, String? label,
    }) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            child: Icon(icon, color: active ? Colors.black : Colors.white, size: 22),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: BestieTokens.fwSemibold)),
        ],
      ]);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          pill(
            icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            onTap: _toggleMute, active: _muted, label: 'Mute',
          ),
          if (_isVideo)
            pill(
              icon: _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
              onTap: _toggleCamera, active: _cameraOff, label: 'Camera',
            ),
          pill(
            icon: _speakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
            onTap: _toggleSpeaker, active: !_speakerOn, label: 'Speaker',
          ),
          pill(
            icon: _sharing ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
            onTap: _toggleShare, active: _sharing, label: _sharing ? 'Stop' : 'Share',
          ),
          pill(
            icon: _recording ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
            onTap: _toggleRecord, active: _recording, label: _recording ? 'Stop' : 'Record',
          ),
        ]),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: _hangup,
          child: Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(color: BestieTokens.cDanger, shape: BoxShape.circle),
            child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
          ),
        ),
      ]),
    );
  }
}

class _Participant {
  final String name;
  final String role;
  final bool muted;
  final bool video;
  const _Participant({required this.name, required this.role, required this.muted, required this.video});
}
