import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:permission_handler/permission_handler.dart';

import '../active_call_state.dart';
import '../state.dart';

const _callNotificationChannel = MethodChannel('mytaskking/call_notification');

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

/// Static, app-wide call session. Living outside the widget lets the audio
/// keep playing when the user navigates away from /call/:id — only an
/// explicit Hang Up tears the engine down.
class CallSession {
  static RtcEngine? engine;
  static String? channelName;
  static String? activeCallId;
  static String? activeMeetingSlug;
  static bool joined = false;
  static bool videoEnabled = false;
  static final Set<int> remoteUids = {};
  static final Map<int, String> remoteNames = {};
  /// Bumps whenever the session activates or deactivates so widgets
  /// outside the call screen (e.g. the "ongoing call" return pill) can
  /// rebuild without polling.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static void _ping() { revision.value = revision.value + 1; }

  static bool get isActive => engine != null;
  static bool matches(String? callId, String? meetingSlug) {
    if (engine == null) return false;
    if (callId != null) return activeCallId == callId;
    if (meetingSlug != null) return activeMeetingSlug == meetingSlug;
    return false;
  }

  static Future<void> teardown() async {
    try {
      await engine?.leaveChannel();
    } catch (_) {}
    try {
      await engine?.release();
    } catch (_) {}
    engine = null;
    channelName = null;
    activeCallId = null;
    activeMeetingSlug = null;
    joined = false;
    videoEnabled = false;
    remoteUids.clear();
    remoteNames.clear();
    _ping();
  }
}

// Backwards-compat alias for existing private references in this file.
typedef _CallSession = CallSession;

class _CallScreenState extends ConsumerState<CallScreen> {
  RtcEngine? get _engine => _CallSession.engine;
  String? get _channelName => _CallSession.channelName;
  set _channelName(String? v) => _CallSession.channelName = v;
  bool get _joined => _CallSession.joined;
  set _joined(bool v) => _CallSession.joined = v;
  bool get _videoEnabled => _CallSession.videoEnabled;
  set _videoEnabled(bool v) => _CallSession.videoEnabled = v;
  Set<int> get _remoteUids => _CallSession.remoteUids;
  Map<int, String> get _remoteNames => _CallSession.remoteNames;

  String _status = 'Preparing…';
  bool _muted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  bool _sharing = false;
  bool _recording = false;
  String? _error;
  Map<String, dynamic>? _callMeta;
  final List<void Function()> _callUnsubs = [];
  bool _remoteClosed = false;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  DateTime? _connectedAt;

  bool get _isVideo => _videoEnabled;

  @override
  void initState() {
    super.initState();
    if (!_CallSession.matches(widget.callId, widget.meetingSlug)) {
      _videoEnabled = widget.mode == 'video';
    }
    _subscribeCallLifecycle();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final u in _callUnsubs) {
      u();
    }
    _callUnsubs.clear();
    _timer?.cancel();
    // Do NOT tear down on dispose — the user closing the call window
    // should keep the call running in the background. Only explicit
    // Hang Up (`_hangup`) ends the session.
    super.dispose();
  }

  void _subscribeCallLifecycle() {
    final callId = widget.callId;
    if (callId == null) return;
    final rt = ref.read(realtimeProvider);
    _callUnsubs.add(rt.onAny('call.declined', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      final me = ref.read(authStoreProvider).user;
      if (data['userId'] == me?.id) return;
      _endBecauseRemoteClosed();
    }));
    _callUnsubs.add(rt.onAny('call.ended', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      _endBecauseRemoteClosed();
    }));
    _callUnsubs.add(rt.onAny('call.participant.joined', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      final me = ref.read(authStoreProvider).user;
      if (data['userId'] == me?.id) return;
      final uidRaw = data['agoraUid'];
      final uid = uidRaw is int ? uidRaw : int.tryParse('$uidRaw');
      if (uid == null || uid <= 0) return;
      if (!mounted) return;
      setState(() {
        _remoteUids.add(uid);
        final name = data['userName']?.toString();
        if (name != null && name.isNotEmpty) _remoteNames[uid] = name;
      });
      _markRemoteConnected();
      _publishActiveCallState();
    }));
  }

  Future<void> _endBecauseRemoteClosed() async {
    if (_remoteClosed) return;
    _remoteClosed = true;
    await _teardown(notifyServer: false);
    if (!mounted) return;
    bestieToast(
      context,
      'Call ended',
      body: 'The other person declined or left the call.',
      kind: BestieToastKind.info,
    );
    context.go('/chat');
  }

  void _startTimer() {
    if (_connectedAt != null) return;
    _timer?.cancel();
    _connectedAt = DateTime.now();
    _elapsed = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = _elapsed + const Duration(seconds: 1));
    });
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _publishActiveCallState() {
    final title = widget.meetingSlug != null
        ? 'Meeting'
        : (_remoteNames.values.isNotEmpty ? _remoteNames.values.first : 'Call');
    ActiveCallState.update(
      title: title,
      participants: _remoteNames.values.toList(growable: false),
    );
  }

  void _markRemoteConnected() {
    _startTimer();
    if (mounted) setState(() => _status = 'Connected');
  }

  Future<void> _showOngoingCallNotification() async {
    try {
      await _callNotificationChannel.invokeMethod('show', {
        'title': widget.meetingSlug != null
            ? 'Meeting in progress'
            : 'Call in progress',
        'body': _remoteNames.values.isNotEmpty
            ? _remoteNames.values.join(', ')
            : 'Tap to return',
        'callId': widget.callId,
        'meetingSlug': widget.meetingSlug,
        'mode': widget.mode,
      });
    } catch (_) {}
  }

  Future<void> _hideOngoingCallNotification() async {
    try {
      await _callNotificationChannel.invokeMethod('hide');
    } catch (_) {}
  }

  void _applyJoinedParticipants(Map<String, dynamic>? payload) {
    final call = (payload?['call'] as Map?)?.cast<String, dynamic>();
    final participants = (call?['participants'] as List?) ?? const [];
    final me = ref.read(authStoreProvider).user;
    var changed = false;
    for (final raw in participants) {
      if (raw is! Map) continue;
      if (raw['userId'] == me?.id) continue;
      if (raw['joinedAt'] == null) continue;
      final uidRaw = raw['agoraUid'];
      final uid = uidRaw is int ? uidRaw : int.tryParse('$uidRaw');
      if (uid == null || uid <= 0) continue;
      changed = _remoteUids.add(uid) || changed;
      final user = (raw['user'] as Map?)?.cast<String, dynamic>();
      final name = user?['name']?.toString();
      if (name != null && name.isNotEmpty) _remoteNames[uid] = name;
    }
    if (changed && mounted) {
      setState(() {});
      _markRemoteConnected();
      _publishActiveCallState();
      _showOngoingCallNotification();
    }
  }

  Future<void> _teardown({bool notifyServer = true}) async {
    if (notifyServer && widget.callId != null) {
      try {
        await ref.read(apiProvider).post('/calls/${widget.callId}/leave');
      } catch (_) {}
    }
    await _CallSession.teardown();
    _connectedAt = null;
    ActiveCallState.clear();
    await _hideOngoingCallNotification();
  }

  bool _booting = false;

  /// (Re)wires Agora event handlers to *this* widget's setState. We call it
  /// fresh on every mount so the live engine drives the current instance's
  /// UI — the user may have backgrounded the call and returned later.
  void _registerHandlers(RtcEngine engine) {
    engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (conn, elapsed) {
        if (!mounted) return;
        setState(() {
          _joined = true;
          _status = _remoteUids.isEmpty ? 'Waiting for others…' : 'Connected';
        });
        _publishActiveCallState();
        _showOngoingCallNotification();
      },
      onUserJoined: (conn, remoteUid, elapsed) {
        if (!mounted) return;
        setState(() => _remoteUids.add(remoteUid));
        _markRemoteConnected();
        _publishActiveCallState();
        _showOngoingCallNotification();
      },
      onUserOffline: (conn, remoteUid, reason) {
        if (!mounted) return;
        setState(() => _status = 'Participant reconnecting…');
        // Do not remove the participant immediately. Agora also fires this
        // for temporary network drops; the backend call.ended event is the
        // source of truth for a real hang-up.
      },
      onConnectionLost: (conn) {
        if (!mounted) return;
        setState(() => _status = 'Network lost · reconnecting…');
      },
      onRejoinChannelSuccess: (conn, elapsed) {
        if (!mounted) return;
        setState(() => _status = 'Connected');
      },
      onConnectionStateChanged: (conn, state, reason) {
        if (!mounted) return;
        if (state == ConnectionStateType.connectionStateReconnecting) {
          setState(() => _status = 'Network issue · reconnecting…');
        } else if (state == ConnectionStateType.connectionStateConnected) {
          setState(() => _status = 'Connected');
        } else if (state == ConnectionStateType.connectionStateFailed) {
          setState(() => _status = 'Network failed · tap Retry');
        }
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
        setState(() {
          _error =
              'Agora native error ${err.value()}${msg.isNotEmpty ? ' — $msg' : ''}';
        });
      },
      onLeaveChannel: (conn, stats) {
        if (!mounted) return;
        setState(() {
          _joined = false;
          _status = 'Ended';
        });
        _timer?.cancel();
      },
    ));
  }

  Future<void> _bootstrap() async {
    // Re-entrant guard — Riverpod rebuilds during permission prompts can
    // re-trigger initState's handlers. A second engine create while the first
    // is mid-init is one of the documented causes of Agora ERR_NOT_READY (-3).
    if (_booting) return;
    _booting = true;

    // Re-entering an already-running call (user navigated back into /call/:id
    // after minimizing it): just rebind the UI to the live engine. Skip the
    // permission, token, and join dance entirely.
    if (_CallSession.matches(widget.callId, widget.meetingSlug)) {
      try {
        _registerHandlers(_CallSession.engine!);
        setState(() {
          _status = _joined ? 'Connected' : 'Connecting…';
        });
      } finally {
        _booting = false;
      }
      return;
    }
    // Different call already running — leave it cleanly before joining a new
    // one. Without this Agora throws -17 (already in channel).
    if (_CallSession.engine != null) {
      await _CallSession.teardown();
    }

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
        if (cam != PermissionStatus.granted &&
            cam != PermissionStatus.limited) {
          throw 'Camera permission denied. Open Settings → Apps → MyTaskKing → Permissions and enable it.';
        }
      }

      // 2. Fetch token + appId from the backend.
      step = 'token-fetch';
      setState(() => _status = 'Connecting…');
      final tokenResp = await _fetchToken();
      _callMeta = tokenResp;
      _applyJoinedParticipants(tokenResp);
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
      ActiveCallState.start(
        callId: widget.callId,
        meetingSlug: widget.meetingSlug,
        mode: widget.mode,
        title: widget.meetingSlug != null ? 'Meeting' : 'Call',
      );

      // 3. Create + initialize the engine. `channelProfile` belongs on the
      // engine context — supplying it only via joinChannel options is one of
      // the documented causes of -3 on certain Agora 6.5.x devices.
      step = 'create-engine';
      final engine = createAgoraRtcEngine();
      _CallSession.engine = engine;
      _CallSession.activeCallId = widget.callId;
      _CallSession.activeMeetingSlug = widget.meetingSlug;
      _CallSession.channelName = channel;
      _CallSession._ping();

      step = 'initialize';
      await engine.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      // 4. Wire event handlers BEFORE joining so we don't miss state.
      step = 'register-handlers';
      _registerHandlers(engine);

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
          autoSubscribeVideo: true,
        ),
      );

      if (widget.callId != null) {
        try {
          final joinedCall =
              await ref.read(apiProvider).post('/calls/${widget.callId}/join');
          _applyJoinedParticipants({'call': joinedCall});
        } catch (_) {}
      }
    } on AgoraRtcException catch (e) {
      if (!mounted) return;
      final code = e.code;
      final hint = _hintForAgoraCode(code, step);
      setState(() {
        _error =
            'Agora error $code at "$step"${hint != null ? '\n\n$hint' : ''}';
        _status = 'Failed';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.toString()} (during "$step")';
        _status = 'Failed';
      });
    } finally {
      _booting = false;
    }
  }

  /// Human-readable hint for the most common Agora error codes we hit during
  /// bootstrap. Shown alongside the raw code so the user knows what to do.
  String? _hintForAgoraCode(int code, String step) {
    switch (code) {
      case -2:
        return 'Invalid argument passed to Agora. Likely a malformed App ID or channel name.';
      case -3:
        return 'Agora SDK is not ready. Usually means the App ID is rejected by Agora, the device denied a permission, or the engine is being re-initialized while a previous instance is still alive. Try: 1) confirm AGORA_APP_ID matches an active Agora project, 2) grant mic/camera in system settings, 3) restart the app.';
      case -7:
        return 'Engine not initialized — internal bug.';
      case -17:
        return 'Already joined this channel. Hangup first and try again.';
      case -101:
        return 'Invalid App ID — Agora rejected the credentials. Verify AGORA_APP_ID on the server.';
      case -109:
        return 'Token expired. Re-open the call to fetch a fresh token.';
      case -110:
        return 'Invalid token — the App Certificate on the server doesn\'t match the App ID, or the uid in the token doesn\'t match the uid passed to joinChannel.';
      default:
        return null;
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
    final engine = _engine;
    if (engine == null) return;
    if (!_videoEnabled) {
      final status = await Permission.camera.request();
      if (status != PermissionStatus.granted &&
          status != PermissionStatus.limited) {
        if (mounted) {
          bestieToast(
            context,
            'Camera permission needed',
            body: 'Enable camera permission to turn on video.',
            kind: BestieToastKind.warning,
          );
        }
        return;
      }
      try {
        await engine.enableVideo();
        await engine.startPreview();
        await engine.updateChannelMediaOptions(const ChannelMediaOptions(
          publishCameraTrack: true,
          autoSubscribeVideo: true,
        ));
        setState(() {
          _videoEnabled = true;
          _cameraOff = false;
        });
      } catch (e) {
        if (mounted) {
          bestieToast(
            context,
            'Could not start video',
            body: e.toString(),
            kind: BestieToastKind.error,
          );
        }
      }
      return;
    }
    setState(() => _cameraOff = !_cameraOff);
    await engine.muteLocalVideoStream(_cameraOff);
    await engine.updateChannelMediaOptions(ChannelMediaOptions(
      publishCameraTrack: !_cameraOff,
      autoSubscribeVideo: true,
    ));
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
        if (mounted)
          bestieToast(context, 'Screen share stopped',
              kind: BestieToastKind.info);
      } else {
        await _engine!.startScreenCapture(const ScreenCaptureParameters2(
          captureVideo: true,
          captureAudio: false,
        ));
        setState(() => _sharing = true);
        if (mounted)
          bestieToast(context, 'Sharing your screen',
              kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted)
        bestieToast(context, 'Screen share not available',
            body: e.toString(), kind: BestieToastKind.error);
    }
  }

  Future<void> _toggleRecord() async {
    final slug = widget.meetingSlug ?? widget.callId;
    if (slug == null) return;
    setState(() => _recording = !_recording);
    try {
      if (_recording) {
        await ref
            .read(apiProvider)
            .post('/meetings/$slug/recording/start')
            .catchError((_) => <String, dynamic>{});
        if (mounted) {
          bestieToast(context, 'Recording started',
              body: 'A copy will be saved to Files when the call ends.',
              kind: BestieToastKind.success);
        }
      } else {
        await ref
            .read(apiProvider)
            .post('/meetings/$slug/recording/stop')
            .catchError((_) => <String, dynamic>{});
        if (mounted)
          bestieToast(context, 'Recording stopped', kind: BestieToastKind.info);
      }
    } catch (e) {
      setState(() => _recording = !_recording);
      if (mounted)
        bestieToast(context, 'Recording unavailable',
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
          participants.add(_Participant(
              name: me.name, role: 'You', muted: _muted, video: !_cameraOff));
        }
        for (final uid in _remoteUids) {
          participants.add(_Participant(
              name: _remoteNames[uid] ?? 'Participant',
              role: 'Remote',
              muted: false,
              video: true));
        }
        final invited = ((_callMeta?['call']?['participants'] as List?) ??
                (_callMeta?['participants'] as List?) ??
                const [])
            .cast<dynamic>();
        for (final p in invited) {
          if (p is Map) {
            final u = (p['user'] as Map?)?.cast<String, dynamic>();
            final n = (u?['name'] ?? '').toString();
            if (n.isEmpty || n == me?.name) continue;
            if (participants.any((pp) => pp.name == n)) continue;
            participants.add(_Participant(
                name: n, role: 'Invited', muted: true, video: false));
          }
        }
        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(BestieTokens.rXl)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: c.borderStrong,
                borderRadius: BorderRadius.circular(BestieTokens.rPill),
              ),
            ),
            Row(children: [
              Text('Participants (${participants.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: BestieTokens.fwBold,
                    color: c.text,
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
                                  style: TextStyle(
                                      color: c.text,
                                      fontWeight: BestieTokens.fwSemibold)),
                              Text(p.role,
                                  style: TextStyle(
                                      color: c.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                        Icon(
                            p.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            size: 16,
                            color: p.muted ? c.danger : c.success),
                        const SizedBox(width: 12),
                        Icon(
                            p.video
                                ? Icons.videocam_rounded
                                : Icons.videocam_off_rounded,
                            size: 16,
                            color: p.video ? c.success : c.textFaint),
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

  void _minimize() {
    context.go('/chat');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(child: _remoteSurface()),
          if (_isVideo && _joined && !_cameraOff)
            Positioned(
              right: 16,
              top: 16,
              width: 110,
              height: 160,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24, width: 1),
                  borderRadius: BorderRadius.circular(BestieTokens.rMd),
                ),
                child: _engine != null
                    ? AgoraVideoView(
                        controller: VideoViewController(
                        rtcEngine: _engine!,
                        canvas: const VideoCanvas(uid: 0),
                      ))
                    : const SizedBox.shrink(),
              ),
            ),
          Positioned(top: 8, left: 8, right: 8, child: _header()),
          Positioned(
              bottom: 22 + bottomInset, left: 0, right: 0, child: _controls()),
        ]),
      ),
    );
  }

  Widget _header() {
    return Row(children: [
      IconButton(
        icon: const Icon(Icons.expand_more_rounded,
            color: Colors.white, size: 28),
        onPressed: _minimize,
        tooltip: 'Minimize',
      ),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_channelName ?? 'Connecting…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: BestieTokens.fwBold,
                letterSpacing: BestieTokens.lsSnug,
              )),
          Row(children: [
            if (_recording)
              Container(
                margin: const EdgeInsets.only(right: 6, top: 2),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: Color(0xFFEF4444), shape: BoxShape.circle),
              ),
            Text(_connectedAt == null ? _status : _formatElapsed(_elapsed),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ]),
      ),
      IconButton(
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        tooltip: 'Invite',
        onPressed: _showInvite,
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

  /// In-call invite — search teammates + add them to the live call.
  /// For meetings (no callId), we surface a shareable link instead so users
  /// can invite teammates or external participants by URL.
  Future<void> _showInvite() async {
    if (widget.meetingSlug != null) {
      _showMeetingInvite();
      return;
    }
    final callId = widget.callId;
    if (callId == null) return;

    final selected = <String>{};
    final api = ref.read(apiProvider);
    final controller = TextEditingController();
    List<Map<String, dynamic>> employees = [];
    String? error;
    bool loading = true;

    Future<void> fetchPeople(StateSetter set, String q) async {
      try {
        final res = await api.listEmployees(q: q.isEmpty ? null : q);
        if (mounted)
          set(() {
            employees = res;
            loading = false;
            error = null;
          });
      } catch (e) {
        if (mounted)
          set(() {
            error = e.toString();
            loading = false;
          });
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, set) {
          if (employees.isEmpty && loading && error == null) {
            fetchPeople(set, '');
          }
          final c = BestieColors.of(ctx);
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, sc) => Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(BestieTokens.rXl)),
              ),
              child: Column(children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
                  decoration: BoxDecoration(
                    color: c.borderStrong,
                    borderRadius: BorderRadius.circular(BestieTokens.rPill),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 4),
                  child: Row(children: [
                    Expanded(
                        child: Text('Invite to call',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: BestieTokens.fwBold,
                              color: c.text,
                              letterSpacing: BestieTokens.lsTight,
                            ))),
                    IconButton(
                        icon: Icon(Icons.close_rounded, color: c.textMuted),
                        onPressed: () => Navigator.pop(ctx)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: controller,
                    onChanged: (v) {
                      set(() => loading = true);
                      fetchPeople(set, v.trim());
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded,
                          color: c.textMuted, size: 18),
                      hintText: 'Search teammates',
                      filled: true,
                      fillColor: c.surface2,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(BestieTokens.rSm),
                        borderSide: BorderSide(color: c.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(BestieTokens.rSm),
                        borderSide: const BorderSide(
                            color: BestieTokens.cBrand, width: 1.6),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: loading
                      ? const Center(child: BestieSpinner())
                      : error != null
                          ? BestieEmptyState(
                              icon: Icons.error_outline_rounded,
                              iconColor: c.danger,
                              title: 'Could not load',
                              description: error)
                          : ListView.builder(
                              controller: sc,
                              itemCount: employees.length,
                              itemBuilder: (ctx, i) {
                                final u = employees[i];
                                final id = u['id'] as String;
                                final picked = selected.contains(id);
                                return CheckboxListTile(
                                  value: picked,
                                  onChanged: (_) => set(() {
                                    picked
                                        ? selected.remove(id)
                                        : selected.add(id);
                                  }),
                                  controlAffinity:
                                      ListTileControlAffinity.trailing,
                                  secondary: BestieAvatar(
                                    name: (u['name'] ?? '—').toString(),
                                    imageUrl: u['avatarUrl']?.toString(),
                                    isClient: u['isClient'] == true,
                                    size: 36,
                                  ),
                                  title: Text((u['name'] ?? '—').toString(),
                                      style: TextStyle(
                                          color: c.text,
                                          fontWeight: BestieTokens.fwSemibold)),
                                  subtitle: Text(
                                      (u['customTitle'] ?? u['role'] ?? '')
                                          .toString()
                                          .replaceAll('_', ' ')
                                          .toLowerCase(),
                                      style: TextStyle(
                                          color: c.textMuted, fontSize: 12)),
                                  activeColor: BestieTokens.cBrand,
                                );
                              },
                            ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: selected.isEmpty
                            ? null
                            : () async {
                                try {
                                  await api.addCallParticipants(
                                      callId, selected.toList());
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted)
                                    bestieToast(
                                        context, 'Invited ${selected.length}',
                                        kind: BestieToastKind.success);
                                } catch (e) {
                                  if (ctx.mounted)
                                    bestieToast(ctx, 'Invite failed',
                                        body: formatApiError(e),
                                        kind: BestieToastKind.error);
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: BestieTokens.cBrand,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded,
                            size: 18),
                        label: Text(selected.isEmpty
                            ? 'Pick teammates to invite'
                            : 'Invite ${selected.length}'),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          );
        });
      },
    );
  }

  Future<void> _showMeetingInvite() async {
    final slug = widget.meetingSlug;
    if (slug == null) return;

    final selected = <String>{};
    final api = ref.read(apiProvider);
    final controller = TextEditingController();
    List<Map<String, dynamic>> employees = [];
    String? error;
    bool loading = true;

    Future<void> fetchPeople(StateSetter set, String q) async {
      try {
        final me = ref.read(authStoreProvider).user;
        final res = await api.listEmployees(q: q.isEmpty ? null : q);
        if (mounted) {
          set(() {
            employees = res.where((u) => u['id'] != me?.id).toList();
            loading = false;
            error = null;
          });
        }
      } catch (e) {
        if (mounted)
          set(() {
            error = e.toString();
            loading = false;
          });
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, set) {
          if (employees.isEmpty && loading && error == null) {
            fetchPeople(set, '');
          }
          final c = BestieColors.of(ctx);
          return DraggableScrollableSheet(
            initialChildSize: 0.72,
            minChildSize: 0.42,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, sc) => Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(BestieTokens.rXl)),
              ),
              child: Column(children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
                  decoration: BoxDecoration(
                    color: c.borderStrong,
                    borderRadius: BorderRadius.circular(BestieTokens.rPill),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 4),
                  child: Row(children: [
                    Expanded(
                        child: Text('Invite to meeting',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: BestieTokens.fwBold,
                              color: c.text,
                              letterSpacing: BestieTokens.lsTight,
                            ))),
                    IconButton(
                      icon: Icon(Icons.link_rounded, color: c.textMuted),
                      tooltip: 'Copy meeting link',
                      onPressed: _showMeetingShare,
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: c.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: controller,
                    onChanged: (v) {
                      set(() => loading = true);
                      fetchPeople(set, v.trim());
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded,
                          color: c.textMuted, size: 18),
                      hintText: 'Search organization people',
                      filled: true,
                      fillColor: c.surface2,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(BestieTokens.rSm),
                        borderSide: BorderSide(color: c.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(BestieTokens.rSm),
                        borderSide: const BorderSide(
                            color: BestieTokens.cBrand, width: 1.6),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: loading
                      ? const Center(child: BestieSpinner())
                      : error != null
                          ? BestieEmptyState(
                              icon: Icons.error_outline_rounded,
                              iconColor: c.danger,
                              title: 'Could not load people',
                              description: formatApiError(error!),
                            )
                          : ListView.builder(
                              controller: sc,
                              itemCount: employees.length,
                              itemBuilder: (ctx, i) {
                                final u = employees[i];
                                final id = u['id'] as String;
                                final picked = selected.contains(id);
                                return CheckboxListTile(
                                  value: picked,
                                  onChanged: (_) => set(() {
                                    picked
                                        ? selected.remove(id)
                                        : selected.add(id);
                                  }),
                                  controlAffinity:
                                      ListTileControlAffinity.trailing,
                                  secondary: BestieAvatar(
                                    name: (u['name'] ?? '—').toString(),
                                    imageUrl: u['avatarUrl']?.toString(),
                                    isClient: u['isClient'] == true,
                                    size: 36,
                                  ),
                                  title: Text((u['name'] ?? '—').toString(),
                                      style: TextStyle(
                                          color: c.text,
                                          fontWeight: BestieTokens.fwSemibold)),
                                  subtitle: Text(
                                      (u['customTitle'] ?? u['role'] ?? '')
                                          .toString()
                                          .replaceAll('_', ' ')
                                          .toLowerCase(),
                                      style: TextStyle(
                                          color: c.textMuted, fontSize: 12)),
                                  activeColor: BestieTokens.cBrand,
                                );
                              },
                            ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: selected.isEmpty
                            ? null
                            : () async {
                                try {
                                  await api.inviteMeetingParticipants(
                                      slug, selected.toList());
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    bestieToast(
                                        context, 'Invited ${selected.length}',
                                        body:
                                            'They will get a meeting preview and notification.',
                                        kind: BestieToastKind.success);
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    bestieToast(ctx, 'Invite failed',
                                        body: formatApiError(e),
                                        kind: BestieToastKind.error);
                                  }
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: BestieTokens.cBrand,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded,
                            size: 18),
                        label: Text(selected.isEmpty
                            ? 'Pick people to invite'
                            : 'Invite ${selected.length}'),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          );
        });
      },
    );
  }

  /// For meetings, surface a copy-able room link teammates (or external
  /// guests) can paste into a browser / desktop client.
  void _showMeetingShare() {
    final slug = widget.meetingSlug;
    if (slug == null) return;
    // Must match the backend's `serializeRoom().shareUrl` so external guests
    // land on the working /meetings/join/<slug> page where they can request
    // access without an account.
    final link = 'https://mytaskking.com/meetings/join/$slug';
    final c = BestieColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(BestieTokens.rXl)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invite to meeting',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: BestieTokens.fwBold,
                      color: c.text,
                      letterSpacing: BestieTokens.lsTight,
                    )),
                const SizedBox(height: 4),
                Text('Share this link — teammates or external guests can join.',
                    style: TextStyle(color: c.textMuted, fontSize: 13)),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(BestieTokens.rMd),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(children: [
                    Expanded(
                        child: Text(link,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: c.text,
                              fontWeight: BestieTokens.fwSemibold,
                            ))),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: 'Copy',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        if (ctx.mounted)
                          bestieToast(ctx, 'Copied to clipboard',
                              kind: BestieToastKind.success);
                      },
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Close'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: link));
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted)
                        bestieToast(context, 'Link copied — share away',
                            kind: BestieToastKind.success);
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: BestieTokens.cBrand),
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('Copy & share'),
                  )),
                ]),
              ]),
        ),
      ),
    );
  }

  Widget _remoteSurface() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white70, size: 42),
            const SizedBox(height: 10),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                setState(() {
                  _error = null;
                });
                _bootstrap();
              },
              child: const Text('Retry'),
            ),
          ]),
        ),
      );
    }
    if (!_isVideo) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 112, 20, 220),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            _voiceParticipantsGrid(),
            const SizedBox(height: 24),
            _participantsStrip(showTimer: false),
            const SizedBox(height: 14),
            Text(_connectedAt == null ? _status : _formatElapsed(_elapsed),
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              'Tap Video to switch on your camera',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.46), fontSize: 12),
            ),
          ]),
        ),
      );
    }
    if (_remoteUids.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _participantsStrip(showTimer: false),
          const SizedBox(height: 18),
          Icon(Icons.videocam_outlined, color: Colors.white24, size: 76),
          const SizedBox(height: 16),
          Text(_joined ? 'Waiting for others…' : _status,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ]),
      );
    }
    final firstRemote = _remoteUids.first;
    return Stack(children: [
      Positioned.fill(
        child: AgoraVideoView(
            controller: VideoViewController.remote(
          rtcEngine: _engine!,
          canvas: VideoCanvas(uid: firstRemote),
          connection: RtcConnection(channelId: _channelName ?? ''),
        )),
      ),
      Positioned(
          left: 16,
          right: 16,
          top: 96,
          child: Center(child: _participantsStrip())),
    ]);
  }

  Widget _participantsStrip({bool showTimer = true}) {
    final names = <String>[
      if (_remoteNames.isEmpty && _remoteUids.isNotEmpty) 'Participant',
      ..._remoteNames.values,
    ];
    final label = names.isEmpty ? 'Waiting for others' : names.join(', ');
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.42),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.people_alt_rounded, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (showTimer && _connectedAt != null) ...[
          const SizedBox(width: 10),
          Text(
            _formatElapsed(_elapsed),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ]),
    );
  }

  Widget _voiceParticipantsGrid() {
    final me = ref.read(authStoreProvider).user;
    final names = <String>[
      me?.name ?? 'You',
      if (_remoteNames.isNotEmpty) ..._remoteNames.values,
      if (_remoteNames.isEmpty && _remoteUids.isNotEmpty) 'Participant',
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 18,
      children: [
        for (var i = 0; i < names.length; i++)
          Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 92,
              height: 92,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i == 0
                    ? BestieTokens.cBrand.withOpacity(0.22)
                    : BestieTokens.cSuccess.withOpacity(0.18),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                names[i].isEmpty ? '?' : names[i][0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 110,
              child: Text(
                i == 0 ? 'You' : names[i],
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ]),
      ],
    );
  }

  Widget _controls() {
    Widget pill({
      required IconData icon,
      required VoidCallback onTap,
      bool active = false,
      String? label,
    }) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            child: Icon(icon,
                color: active ? Colors.black : Colors.white, size: 22),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: BestieTokens.fwSemibold)),
        ],
      ]);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          pill(
            icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            onTap: _toggleMute,
            active: _muted,
            label: 'Mute',
          ),
          pill(
            icon: (!_videoEnabled || _cameraOff)
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            onTap: _toggleCamera,
            active: !_videoEnabled || _cameraOff,
            label: _videoEnabled ? 'Camera' : 'Video',
          ),
          pill(
            icon: _speakerOn
                ? Icons.volume_up_rounded
                : Icons.volume_down_rounded,
            onTap: _toggleSpeaker,
            active: !_speakerOn,
            label: 'Speaker',
          ),
          pill(
            icon: _sharing
                ? Icons.stop_screen_share_rounded
                : Icons.screen_share_rounded,
            onTap: _toggleShare,
            active: _sharing,
            label: _sharing ? 'Stop' : 'Share',
          ),
          pill(
            icon: _recording
                ? Icons.stop_circle_rounded
                : Icons.fiber_manual_record_rounded,
            onTap: _toggleRecord,
            active: _recording,
            label: _recording ? 'Stop' : 'Record',
          ),
        ]),
        const SizedBox(height: 22),
        GestureDetector(
          onTap: _hangup,
          child: Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
                color: BestieTokens.cDanger, shape: BoxShape.circle),
            child: const Icon(Icons.call_end_rounded,
                color: Colors.white, size: 30),
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
  const _Participant(
      {required this.name,
      required this.role,
      required this.muted,
      required this.video});
}
