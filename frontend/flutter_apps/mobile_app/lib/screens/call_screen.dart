import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../active_call_state.dart';
import '../router.dart';
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
  static bool muted = false;
  static bool cameraOff = false;
  static CallAudioRoute audioRoute = CallAudioRoute.earpiece;
  static DateTime? connectedAt;
  static bool recording = false;
  static bool savingRecording = false;
  static String? recordingPath;

  /// This device's randomly-chosen Agora uid for the active call. Random per
  /// device so the same account can join from two phones without colliding.
  static int? myUid;

  /// True while the live call screen (/call or /meeting) is mounted on top.
  /// The "ongoing call · tap to return" pill keys off this instead of the
  /// router location — reading GoRouterState from the app-level builder
  /// context (above the Navigator) is unreliable and was making the pill
  /// show even while the user was on the call screen.
  static bool onCallScreen = false;
  static final Set<int> remoteUids = {};
  static final Map<int, String> remoteNames = {};
  static final Map<int, bool> remoteMuted = {};

  /// Bumps whenever the session activates or deactivates so widgets
  /// outside the call screen (e.g. the "ongoing call" return pill) can
  /// rebuild without polling.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static void _ping() {
    revision.value = revision.value + 1;
  }

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
    myUid = null;
    muted = false;
    cameraOff = false;
    audioRoute = CallAudioRoute.earpiece;
    connectedAt = null;
    recording = false;
    savingRecording = false;
    recordingPath = null;
    onCallScreen = false;
    remoteUids.clear();
    remoteNames.clear();
    remoteMuted.clear();
    _ping();
  }
}

// Backwards-compat alias for existing private references in this file.
typedef _CallSession = CallSession;

class _CallScreenState extends ConsumerState<CallScreen>
    with WidgetsBindingObserver {
  RtcEngine? get _engine => _CallSession.engine;
  String? get _channelName => _CallSession.channelName;
  set _channelName(String? v) => _CallSession.channelName = v;
  bool get _joined => _CallSession.joined;
  set _joined(bool v) => _CallSession.joined = v;
  bool get _videoEnabled => _CallSession.videoEnabled;
  set _videoEnabled(bool v) => _CallSession.videoEnabled = v;
  Set<int> get _remoteUids => _CallSession.remoteUids;
  Map<int, String> get _remoteNames => _CallSession.remoteNames;
  Map<int, bool> get _remoteMuted => _CallSession.remoteMuted;
  bool get _muted => _CallSession.muted;
  set _muted(bool v) => _CallSession.muted = v;
  bool get _cameraOff => _CallSession.cameraOff;
  set _cameraOff(bool v) => _CallSession.cameraOff = v;
  CallAudioRoute get _route => _CallSession.audioRoute;
  set _route(CallAudioRoute v) => _CallSession.audioRoute = v;
  bool get _recording => _CallSession.recording;
  set _recording(bool v) => _CallSession.recording = v;
  bool get _savingRecording => _CallSession.savingRecording;
  set _savingRecording(bool v) => _CallSession.savingRecording = v;
  String? get _recordingPath => _CallSession.recordingPath;
  set _recordingPath(String? v) => _CallSession.recordingPath = v;
  DateTime? get _connectedAt => _CallSession.connectedAt;
  set _connectedAt(DateTime? v) => _CallSession.connectedAt = v;

  String _status = 'Preparing…';
  // Peer Agora uids we've already seen announce — gates one-time re-announce.
  final Set<int> _seenPeerUids = {};
  bool _sharing = false;
  bool _reconnecting = false;
  String? _error;
  Map<String, dynamic>? _callMeta;
  final List<void Function()> _callUnsubs = [];
  bool _remoteClosed = false;
  Timer? _timer;
  Timer? _audioHealthTimer;
  Duration _elapsed = Duration.zero;
  final _ringtone = FlutterRingtonePlayer();
  final _tts = FlutterTts();
  String _headOfficeName = 'HQ India';

  bool get _isVideo => _videoEnabled;
  bool get _isCallInitiator {
    final call = (_callMeta?['call'] as Map?)?.cast<String, dynamic>();
    return call?['initiatorId'] == ref.read(authStoreProvider).user?.id;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_CallSession.matches(widget.callId, widget.meetingSlug)) {
      _videoEnabled = widget.mode == 'video';
      // Voice calls default to earpiece (so Bluetooth/earpiece is used and the
      // call is private); video calls default to speaker.
      _route = widget.mode == 'video'
          ? CallAudioRoute.speaker
          : CallAudioRoute.earpiece;
    }
    // The call screen is now on top — hide the return-to-call pill.
    _CallSession.onCallScreen = true;
    _CallSession._ping();
    _subscribeCallLifecycle();
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final u in _callUnsubs) {
      u();
    }
    _callUnsubs.clear();
    _timer?.cancel();
    _audioHealthTimer?.cancel();
    _ringtone.stop();
    _tts.stop();
    // Left the call screen — if the call is still live, the return pill should
    // reappear. (We do NOT tear the engine down here; only explicit Hang Up
    // ends the session, so the call keeps running in the background.)
    _CallSession.onCallScreen = false;
    _CallSession._ping();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_CallSession.matches(widget.callId, widget.meetingSlug)) return;
    if (state == AppLifecycleState.resumed) {
      if (_connectedAt != null) _startTimer();
      _reassertAudio();
      _showOngoingCallNotification();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Reassert the media path and foreground service before the screen locks.
      _reassertAudio();
      _showOngoingCallNotification();
    }
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
    _callUnsubs.add(rt.onAny('call.busy', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      _ringtone.stop();
      final name = (data['userName'] ?? 'The person').toString();
      _speak('$name is currently on another call. Please leave a message.');
      if (mounted) setState(() => _status = '$name is busy');
    }));
    _callUnsubs.add(rt.onAny('call.transferred', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      final from = (data['fromName'] ?? 'A participant').toString();
      final to = (data['toName'] ?? 'another person').toString();
      _speak('$from transferred the call to $to.');
    }));
    _callUnsubs.add(rt.onAny('call.buzzer', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      _playEmergencyBuzzer(data['fromName']?.toString());
    }));
    // A participant (any device) announced its real Agora uid + name. We use
    // this to label the tile for that uid. Because each device announces its
    // own random uid, the same account on two phones shows as two tiles.
    void onPresence([dynamic data]) {
      if (data is! Map || data['callId'] != callId) return;
      final uidRaw = data['agoraUid'];
      final uid = uidRaw is int ? uidRaw : int.tryParse('$uidRaw');
      if (uid == null || uid <= 0) return;
      if (uid == _CallSession.myUid) return; // that's me
      final name = data['userName']?.toString();
      if (!mounted) return;
      // Track seen peer uids separately from names — an announce can arrive
      // with an empty name, and keying "is this new?" off the names map would
      // make such a peer perpetually "new" and trigger a re-announce storm.
      final isNew = _seenPeerUids.add(uid);
      setState(() {
        if (name != null && name.isNotEmpty) _remoteNames[uid] = name;
      });
      // Bidirectional discovery: when a genuinely new peer appears, re-announce
      // myself once so they learn my uid→name too (I may have joined first).
      if (isNew) _announceSelf();
    }

    _callUnsubs.add(rt.onAny('call.participant.joined', onPresence));
    _callUnsubs.add(rt.onAny('call.announce', onPresence));
    _callUnsubs.add(rt.onAny('call.participant.muted', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      final me = ref.read(authStoreProvider).user;
      if (data['userId'] == me?.id) return;
      // Agora's onUserMuteAudio callback supplies the per-device value. This
      // socket event makes sure the call UI repaints immediately as well.
      if (mounted) setState(() {});
    }));
  }

  /// Tell the other call participants this device's real Agora uid + name so
  /// they can label our tile. Debounced lightly via best-effort fire-and-forget.
  void _announceSelf() {
    final callId = widget.callId;
    final uid = _CallSession.myUid;
    if (callId == null || uid == null) return;
    final me = ref.read(authStoreProvider).user;
    ref.read(apiProvider).post('/calls/$callId/announce', body: {
      'agoraUid': uid,
      'userName': me?.name ?? ''
    }).catchError((_) => <String, dynamic>{});
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
    _timer?.cancel();
    _connectedAt ??= DateTime.now();
    void updateElapsed() {
      final started = _connectedAt;
      if (!mounted || started == null) return;
      setState(() => _elapsed = DateTime.now().difference(started));
    }

    updateElapsed();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      updateElapsed();
    });
  }

  void _startAudioHealthCheck() {
    _audioHealthTimer?.cancel();
    _audioHealthTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_joined) _reassertAudio();
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
        'startedAtMs': (_connectedAt ?? DateTime.now()).millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  Future<void> _hideOngoingCallNotification() async {
    try {
      await _callNotificationChannel.invokeMethod('hide');
    } catch (_) {}
  }

  Future<void> _teardown({bool notifyServer = true}) async {
    // Flush an in-progress recording before the engine is released — whether
    // the call ends by hang up OR the remote party leaving. Otherwise the
    // local file is never finalized/uploaded and is silently lost.
    if (_recording) {
      _recording = false;
      try {
        await _engine?.stopAudioRecording();
        await _uploadRecording();
      } catch (_) {/* best-effort */}
    }
    if (notifyServer && widget.callId != null) {
      try {
        await ref.read(apiProvider).post('/calls/${widget.callId}/leave');
      } catch (_) {}
    }
    await _CallSession.teardown();
    await _ringtone.stop();
    await _tts.stop();
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
          _reconnecting = false;
          // Before anyone answers we're ringing them, not connected.
          _status = _remoteUids.isEmpty ? 'Ringing…' : 'Connected';
        });
        _publishActiveCallState();
        _showOngoingCallNotification();
        _startAudioHealthCheck();
        if (_remoteUids.isEmpty && !_isMeeting) _playRingback();
      },
      onUserJoined: (conn, remoteUid, elapsed) {
        if (!mounted) return;
        setState(() {
          _remoteUids.add(remoteUid);
          _reconnecting = false;
        });
        _markRemoteConnected();
        _ringtone.stop();
        _reassertAudio();
        _publishActiveCallState();
        _showOngoingCallNotification();
      },
      onUserOffline: (conn, remoteUid, reason) {
        if (!mounted) return;
        setState(() {
          _reconnecting = _connectedAt != null;
          _status = _connectedAt == null ? 'Ringing…' : 'Reconnecting…';
        });
        // Do not remove the participant immediately. Agora also fires this
        // for temporary network drops; the backend call.ended event is the
        // source of truth for a real hang-up.
      },
      onUserMuteAudio: (conn, remoteUid, muted) {
        if (mounted) {
          setState(() => _remoteMuted[remoteUid] = muted);
        }
        // Make sure we're subscribed to their audio when they unmute — guards
        // against the "no audio for a while then it comes back" dropouts.
        if (!muted) {
          try {
            engine.muteRemoteAudioStream(uid: remoteUid, mute: false);
          } catch (_) {}
        }
      },
      onConnectionLost: (conn) {
        if (!mounted) return;
        setState(() {
          _reconnecting = true;
          _status = 'Reconnecting…';
        });
      },
      onRejoinChannelSuccess: (conn, elapsed) {
        if (!mounted) return;
        setState(() {
          _reconnecting = false;
          _status = _remoteUids.isEmpty ? 'Ringing…' : 'Connected';
        });
        // Audio engine often needs a nudge after a rejoin or the call stays
        // silent for both sides until something else wakes it.
        if (_connectedAt != null) _startTimer();
        _reassertAudio();
        _showOngoingCallNotification();
      },
      onConnectionStateChanged: (conn, state, reason) {
        if (!mounted) return;
        if (state == ConnectionStateType.connectionStateReconnecting) {
          setState(() {
            _reconnecting = true;
            _status = 'Reconnecting…';
          });
        } else if (state == ConnectionStateType.connectionStateConnected) {
          setState(() {
            _reconnecting = false;
            _status = _remoteUids.isEmpty ? 'Ringing…' : 'Connected';
          });
          if (_connectedAt != null) _startTimer();
          _reassertAudio();
          _showOngoingCallNotification();
        } else if (state == ConnectionStateType.connectionStateFailed) {
          setState(() {
            _reconnecting = true;
            _status = 'Reconnecting…';
          });
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
        // A mid-call native error should NOT blank the whole call screen — keep
        // the call UI up and show a reconnect state. Only surface a hard error
        // (with Retry) if we never managed to join in the first place.
        if (_joined) {
          setState(() {
            _reconnecting = true;
            _status = 'Reconnecting…';
          });
          return;
        }
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
        _audioHealthTimer?.cancel();
      },
    ));
  }

  Future<void> _playRingback() async {
    try {
      await _ringtone.play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.electronic,
        looping: true,
        volume: 0.75,
        asAlarm: false,
      );
    } catch (_) {}
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setPitch(1.02);
      await _tts.setSpeechRate(0.36);
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _playEmergencyBuzzer(String? fromName) async {
    try {
      await _ringtone.play(
        android: AndroidSounds.alarm,
        ios: IosSounds.alarm,
        looping: false,
        volume: 1.0,
        asAlarm: true,
      );
      if (mounted) {
        bestieToast(context, 'Emergency buzzer',
            body: '${fromName ?? 'A participant'} sent an emergency alert.',
            kind: BestieToastKind.warning);
      }
    } catch (_) {}
  }

  Future<void> _sendEmergencyBuzzer() async {
    final callId = widget.callId;
    if (callId == null) return;
    try {
      await ref.read(apiProvider).post('/calls/$callId/buzzer');
      if (mounted)
        bestieToast(context, 'Emergency buzzer sent',
            kind: BestieToastKind.warning);
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not send buzzer',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  /// Re-enable + re-route audio after a (re)connect. Without this the call can
  /// stay silent for both parties for a while after a network blip until the
  /// engine recovers on its own.
  Future<void> _reassertAudio() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.enableAudio();
      await engine.muteAllRemoteAudioStreams(false);
      if (_muted) {
        await engine.muteLocalAudioStream(true);
      } else {
        await engine.enableLocalAudio(true);
        await engine.muteLocalAudioStream(false);
      }
      await _applyAudioRoute(_route);
      await engine.adjustPlaybackSignalVolume(160);
    } catch (_) {/* best-effort recovery */}
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
        if (_connectedAt != null) _startTimer();
        _startAudioHealthCheck();
        _reassertAudio();
        _showOngoingCallNotification();
      } finally {
        _booting = false;
      }
      return;
    }
    // Different call already running — leave it cleanly before joining a new
    // one. Without this Agora throws -17 (already in channel).
    if (_CallSession.engine != null) {
      await _CallSession.teardown();
      // teardown() clears onCallScreen; we're still on the call screen, so set
      // it back or the "ongoing call" pill would wrongly show over this call.
      _CallSession.onCallScreen = true;
    }

    // Track which step is in flight so the error message can identify the
    // exact failing call (-3 with a null message is otherwise opaque).
    String step = 'start';
    try {
      // 1. OS-level permissions.
      step = 'permissions';
      final perms = <Permission>[Permission.microphone];
      if (_isVideo) perms.add(Permission.camera);
      // Android 12+ needs runtime BLUETOOTH_CONNECT to route call audio to a
      // Bluetooth headset. Requested best-effort — not fatal if denied.
      if (Platform.isAndroid) perms.add(Permission.bluetoothConnect);
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
      setState(() => _status = _isMeeting ? 'Joining…' : 'Calling…');
      final tokenResp = await _fetchToken();
      _callMeta = tokenResp;
      try {
        final settings =
            await ref.read(apiProvider).settingsScope(scope: 'calls');
        final calls = (settings['calls'] as Map?)?.cast<String, dynamic>();
        _headOfficeName = (calls?['headOfficeName'] ?? 'HQ India').toString();
      } catch (_) {}
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

      // Clear, Bluetooth-friendly voice. SPEECH_STANDARD enables Agora's voice
      // noise-suppression + echo cancellation (kills the background noise), and
      // the default scenario lets audio route to earpiece/speaker/Bluetooth.
      // We use a MODERATE playback boost — the old 300% gain clipped and pumped
      // the AGC, which is what made audio cut out for both sides then return.
      step = 'audio-profile';
      try {
        await engine.setAudioProfile(
          profile: AudioProfileType.audioProfileSpeechStandard,
          scenario: AudioScenarioType.audioScenarioDefault,
        );
      } catch (_) {/* non-critical tuning */}
      try {
        await engine.adjustPlaybackSignalVolume(160);
        await engine.adjustRecordingSignalVolume(120);
      } catch (_) {/* non-critical tuning */}

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
        await _applyAudioRoute(_route);
      } catch (_) {/* will retry post-join */}

      // 6. Join. The server returns a wildcard token (uid 0) for calls, so we
      // pick our OWN random uid per device — that's what lets the same account
      // join from two phones as two distinct participants. Meetings still
      // return a fixed uid, which we honor.
      step = 'join-channel';
      final serverUid = uidRaw is int ? uidRaw : int.tryParse('$uidRaw') ?? 0;
      final uid =
          serverUid > 0 ? serverUid : (1 + Random().nextInt(2147483646));
      _CallSession.myUid = uid;
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

      // Re-assert route + gain after join — some Android devices reset the
      // audio route when the channel connects, which is what made calls quiet.
      try {
        await _applyAudioRoute(_route);
        await engine.adjustPlaybackSignalVolume(160);
      } catch (_) {/* non-critical */}

      if (widget.callId != null) {
        try {
          // Tell the server our real per-device uid so it broadcasts the right
          // uid→name mapping to the other participants' tiles.
          await ref
              .read(apiProvider)
              .post('/calls/${widget.callId}/join', body: {'agoraUid': uid});
        } catch (_) {}
        // Announce again over the socket once we're in — covers participants
        // who were already in the call before us.
        _announceSelf();
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
    await _engine?.enableLocalAudio(true);
    await _engine?.muteLocalAudioStream(_muted);
    _CallSession._ping();
    if (widget.callId != null) {
      try {
        await ref
            .read(apiProvider)
            .post('/calls/${widget.callId}/mute', body: {'muted': _muted});
      } catch (_) {}
    }
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

  /// Cycle earpiece → speaker → bluetooth → earpiece.
  Future<void> _cycleAudioRoute() async {
    final next = switch (_route) {
      CallAudioRoute.earpiece => CallAudioRoute.speaker,
      CallAudioRoute.speaker => CallAudioRoute.bluetooth,
      CallAudioRoute.bluetooth => CallAudioRoute.earpiece,
    };
    await _applyAudioRoute(next);
    if (mounted) setState(() => _route = next);
    if (mounted) {
      bestieToast(context, _audioRouteLabel(next), kind: BestieToastKind.info);
    }
  }

  String _audioRouteLabel(CallAudioRoute r) => switch (r) {
        CallAudioRoute.earpiece => 'Earpiece',
        CallAudioRoute.speaker => 'Speaker',
        CallAudioRoute.bluetooth => 'Bluetooth',
      };

  IconData _audioRouteIcon(CallAudioRoute r) => switch (r) {
        CallAudioRoute.earpiece => Icons.phone_in_talk_rounded,
        CallAudioRoute.speaker => Icons.volume_up_rounded,
        CallAudioRoute.bluetooth => Icons.bluetooth_audio_rounded,
      };

  Future<void> _applyAudioRoute(CallAudioRoute r) async {
    final engine = _engine;
    if (engine == null) return;
    final speaker = r == CallAudioRoute.speaker;
    // Earpiece + Bluetooth both keep the loudspeaker OFF — when a Bluetooth
    // headset is connected Android auto-routes to it; otherwise it's the
    // earpiece. Speaker forces the loudspeaker on.
    try {
      await engine.setDefaultAudioRouteToSpeakerphone(speaker);
    } catch (_) {}
    try {
      await engine.setEnableSpeakerphone(speaker);
    } catch (_) {}
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

  /// Records the whole channel (everyone's mixed audio) to a local file via
  /// the Agora SDK, then on stop uploads it and attaches the URL to the
  /// call/meeting so it surfaces in the admin panel. Fully client-side — no
  /// Agora Cloud Recording add-on needed.
  Future<void> _toggleRecord() async {
    final engine = _engine;
    if (engine == null || _savingRecording) return;
    if (!_recording) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final id = widget.callId ?? widget.meetingSlug ?? 'call';
        final path =
            '${dir.path}/rec_${id}_${DateTime.now().millisecondsSinceEpoch}.aac';
        await engine.startAudioRecording(AudioRecordingConfiguration(
          filePath: path,
          fileRecordingType: AudioFileRecordingType.audioFileRecordingMixed,
          quality: AudioRecordingQualityType.audioRecordingQualityHigh,
          sampleRate: 32000,
        ));
        setState(() {
          _recording = true;
          _recordingPath = path;
        });
        if (mounted) {
          bestieToast(context, 'Recording started',
              body: 'Everyone in this call is being recorded.',
              kind: BestieToastKind.success);
        }
      } catch (e) {
        if (mounted) {
          bestieToast(context, 'Recording unavailable',
              body: e.toString(), kind: BestieToastKind.error);
        }
      }
      return;
    }
    // Stop + upload + attach.
    setState(() {
      _recording = false;
      _savingRecording = true;
    });
    try {
      await engine.stopAudioRecording();
      await _uploadRecording();
    } catch (e) {
      if (mounted) {
        bestieToast(context, "Couldn't save recording",
            body: e.toString(), kind: BestieToastKind.error);
      }
    } finally {
      _savingRecording = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _uploadRecording() async {
    final path = _recordingPath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    final api = ref.read(apiProvider);
    final asset = await api.uploadFile(
      bytes: bytes,
      filename: path.split('/').last,
      mimeType: 'audio/aac',
    );
    final fileId = asset['id']?.toString();
    final url = asset['url']?.toString();
    // Attach the recording to the call or meeting so admins can find it.
    if (widget.callId != null) {
      await api.post('/calls/${widget.callId}/recording',
          body: {'fileId': fileId, 'url': url});
    } else if (widget.meetingSlug != null) {
      await api.post('/meetings/${widget.meetingSlug}/recording',
          body: {'fileId': fileId, 'url': url});
    }
    _recordingPath = null;
    try {
      await file.delete();
    } catch (_) {}
    if (mounted) {
      bestieToast(context, 'Recording saved',
          body: 'Available to admins in the web panel.',
          kind: BestieToastKind.success);
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
        // Only people actually IN the call: me + every live remote stream.
        // (We deliberately don't list invited-but-not-joined users here — the
        // sheet answers "who's on this call right now".)
        for (final uid in _remoteUids) {
          participants.add(_Participant(
              name: _remoteNames[uid] ?? 'Participant',
              role: 'In call',
              muted: _remoteMuted[uid] == true,
              video: true));
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
    // _teardown flushes any in-progress recording before releasing the engine.
    await _teardown();
    if (mounted) context.go('/chat');
  }

  void _minimize() {
    context.go('/chat');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final topInset = MediaQuery.of(context).padding.top;
    final showingVideo = _isVideo && _remoteUids.isNotEmpty;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _minimize();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          // Depth backdrop — a soft vertical gradient so voice calls aren't a
          // flat black void (WhatsApp does the same). Hidden once real remote
          // video fills the screen.
          if (!showingVideo)
            const Positioned.fill(child: _FuturisticCallBackdrop()),
          Positioned.fill(child: _remoteSurface()),

          // Top scrim for header legibility over video.
          if (showingVideo)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: topInset + 110,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.55),
                        Colors.transparent
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Bottom scrim for control legibility over video.
          if (showingVideo)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: bottomInset + 160,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.6),
                        Colors.transparent
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Self-view PiP — rounded, shadowed, tap to flip camera.
          if (_isVideo && _joined && !_cameraOff)
            Positioned(
              right: 14,
              top: topInset + 64,
              width: 104,
              height: 150,
              child: GestureDetector(
                onTap: _flipCamera,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Colors.white.withOpacity(0.2), width: 1),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
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
            ),

          Positioned(top: topInset + 8, left: 8, right: 8, child: _header()),
          // Premium status chips (HD Voice / Network / Secure calling) — voice calls
          // only, matching the redesigned call screen.
          if (!_isMeeting && !showingVideo)
            Positioned(
              top: topInset + 58,
              left: 16,
              right: 16,
              child: IgnorePointer(child: _topChips()),
            ),
          if (_muteStatusText() != null)
            Positioned(
              top: topInset + 62,
              left: 20,
              right: 20,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.62),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.mic_off_rounded,
                          color: Color(0xFFFBBF24), size: 15),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          _muteStatusText()!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: BestieTokens.fwSemibold,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          // Network-trouble banner — keeps the call UI visible (never blanks)
          // and tells the user to check their connection while Agora reconnects.
          if (_reconnecting && _error == null)
            Positioned(
              top: topInset + (_muteStatusText() == null ? 64 : 104),
              left: 16,
              right: 16,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB45309).withOpacity(0.95),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white)),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Reconnecting… check your internet connection',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: BestieTokens.fwSemibold),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          // Controls fade + slide up on entrance.
          Positioned(
            bottom: 22 + bottomInset,
            left: 0,
            right: 0,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              builder: (ctx, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(
                    offset: Offset(0, (1 - v) * 24), child: child),
              ),
              child: _controls(),
            ),
          ),
        ]),
      ),
    );
  }

  bool get _isMeeting => widget.meetingSlug != null;

  String? _muteStatusText() {
    final labels = <String>[];
    if (_muted) labels.add('You are muted');
    for (final entry in _remoteMuted.entries) {
      if (!entry.value) continue;
      labels.add('${_remoteNames[entry.key] ?? 'Participant'} is muted');
    }
    return labels.isEmpty ? null : labels.join(' · ');
  }

  /// Small translucent circle button used in both call + meeting headers.
  Widget _circleHeaderIcon(IconData icon, VoidCallback onTap,
      {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _header() {
    return _isMeeting ? _meetingHeader() : _callHeader();
  }

  /// Human-readable call title: the other participant's name (or names for a
  /// group), never the raw Agora channel id ("call_wSEPLkpXr").
  String _callDisplayTitle() {
    final me = ref.read(authStoreProvider).user;
    final call = (_callMeta?['call'] as Map?)?.cast<String, dynamic>();
    final initiator = (call?['initiator'] as Map?)?.cast<String, dynamic>();
    if (call?['kind'] == 'GROUP' && initiator?['id'] != me?.id) {
      final mainCaller = (initiator?['name'] ?? '').toString().trim();
      if (mainCaller.isNotEmpty) return mainCaller;
    }
    // Prefer the invited participants from the call metadata.
    final parts = (_callMeta?['call']?['participants'] as List?) ??
        (_callMeta?['participants'] as List?) ??
        const [];
    final names = <String>[];
    for (final p in parts) {
      if (p is! Map) continue;
      if (p['userId'] == me?.id) continue;
      final u = (p['user'] as Map?)?.cast<String, dynamic>();
      final n = (u?['name'] ?? '').toString().trim();
      if (n.isNotEmpty && !names.contains(n)) names.add(n);
    }
    // Fall back to the live remote-stream names (announce map).
    if (names.isEmpty) {
      for (final n in _remoteNames.values) {
        if (n.isNotEmpty && !names.contains(n)) names.add(n);
      }
    }
    if (names.isEmpty) return _joined ? 'In call' : 'Connecting…';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]}, ${names[1]}';
    return '${names[0]} +${names.length - 1}';
  }

  /// WhatsApp-style: minimize on the left, caller name centered, add-participant
  /// on the right. Timer shown under the name once connected.
  Widget _callHeader() {
    final title = _callDisplayTitle();
    // Voice calls use the premium center stage (name + timer there), so the
    // header is minimal: minimize · verified MyTaskKing brand · invite. Video
    // calls keep the name + timer in the header (no center stage over video).
    final showingVideo = _isVideo && _remoteUids.isNotEmpty;
    if (!showingVideo) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Row(children: [
          _circleHeaderIcon(Icons.keyboard_arrow_down_rounded, _minimize,
              tooltip: 'Minimize'),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('MyTaskKing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: BestieTokens.fwBold,
                        )),
                    SizedBox(width: 5),
                    Icon(Icons.verified_rounded,
                        color: Color(0xFF38BDF8), size: 17),
                  ]),
                ]),
          ),
          _circleHeaderIcon(Icons.person_add_alt_1_rounded, _showInvite,
              tooltip: 'Invite'),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(children: [
        _circleHeaderIcon(Icons.close_fullscreen_rounded, _minimize,
            tooltip: 'Minimize'),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: BestieTokens.fwBold,
                  letterSpacing: BestieTokens.lsSnug,
                )),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                _connectedAt == null ? _status : _formatElapsed(_elapsed),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (_recording) ...[
                const SizedBox(width: 8),
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ]),
          ]),
        ),
        _circleHeaderIcon(Icons.person_add_alt_1_rounded, _showInvite,
            tooltip: 'Invite'),
      ]),
    );
  }

  /// Google Meet–style: meeting name + e2e/time on the left, participants chip
  /// on the right (taps to open the participants sheet).
  Widget _meetingHeader() {
    final title = _channelName ?? 'Meeting';
    final count = 1 + _remoteUids.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
      child: Row(children: [
        _circleHeaderIcon(Icons.close_fullscreen_rounded, _minimize,
            tooltip: 'Minimize'),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: BestieTokens.fwBold,
                )),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                _connectedAt == null ? _status : _formatElapsed(_elapsed),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (_recording) ...[
                const SizedBox(width: 8),
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ]),
          ]),
        ),
        GestureDetector(
          onTap: _showParticipants,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.people_alt_rounded,
                  color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text('$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: BestieTokens.fwSemibold)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        _circleHeaderIcon(Icons.person_add_alt_1_rounded, _showInvite,
            tooltip: 'Invite'),
      ]),
    );
  }

  /// Builds a labelled section (header + checkbox rows) for the invite sheet.
  /// Returns an empty list when there are no people so the header is hidden.
  List<Widget> _inviteSection(
    BuildContext ctx,
    BestieColors c,
    String label,
    List<Map<String, dynamic>> people,
    Set<String> selected,
    StateSetter set,
  ) {
    if (people.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(label.toUpperCase(),
            style: TextStyle(
              color: c.textMuted,
              fontSize: 11,
              fontWeight: BestieTokens.fwBold,
              letterSpacing: BestieTokens.lsWide,
            )),
      ),
      for (final u in people)
        Builder(builder: (_) {
          final id = u['id'] as String;
          final picked = selected.contains(id);
          return CheckboxListTile(
            value: picked,
            onChanged: (_) => set(() {
              picked ? selected.remove(id) : selected.add(id);
            }),
            controlAffinity: ListTileControlAffinity.trailing,
            secondary: BestieAvatar(
              name: (u['name'] ?? '—').toString(),
              imageUrl: u['avatarUrl']?.toString(),
              isClient: u['isClient'] == true,
              size: 36,
            ),
            title: Text((u['name'] ?? '—').toString(),
                style: TextStyle(
                    color: c.text, fontWeight: BestieTokens.fwSemibold)),
            subtitle: Text(
                (u['customTitle'] ?? u['role'] ?? '')
                    .toString()
                    .replaceAll('_', ' ')
                    .toLowerCase(),
                style: TextStyle(color: c.textMuted, fontSize: 12)),
            activeColor: BestieTokens.cBrand,
          );
        }),
    ];
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
    final me = ref.read(authStoreProvider).user;
    List<Map<String, dynamic>> members = [];
    List<Map<String, dynamic>> clients = [];
    String? error;
    bool loading = true;

    Future<void> fetchPeople(StateSetter set, String q) async {
      try {
        // Members and clients come from separate endpoints — fetch both and
        // show them in two sections.
        final results = await Future.wait([
          api.listEmployees(q: q.isEmpty ? null : q),
          api
              .listClients(q: q.isEmpty ? null : q)
              .catchError((_) => <Map<String, dynamic>>[]),
        ]);
        if (mounted)
          set(() {
            members = results[0].where((u) => u['id'] != me?.id).toList();
            clients = results[1].where((u) => u['id'] != me?.id).toList();
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
          if (members.isEmpty && clients.isEmpty && loading && error == null) {
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
                          : (members.isEmpty && clients.isEmpty)
                              ? BestieEmptyState(
                                  icon: Icons.search_off_rounded,
                                  title: 'No one found',
                                  description: 'Try a different search.')
                              : ListView(
                                  controller: sc,
                                  children: [
                                    ..._inviteSection(
                                        ctx,
                                        c,
                                        'Organization members',
                                        members,
                                        selected,
                                        set),
                                    ..._inviteSection(ctx, c, 'Clients',
                                        clients, selected, set),
                                  ],
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
                                      callId, selected.toList(),
                                      mode: widget.mode.toUpperCase());
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
      // For meetings keep the multi-tile grid (Google Meet style).
      if (_isMeeting) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 112, 20, 220),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              _voiceParticipantsGrid(),
              const SizedBox(height: 24),
              _participantsStrip(showTimer: false),
              const SizedBox(height: 14),
              Text(_connectedAt == null ? _status : _formatElapsed(_elapsed),
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ]),
          ),
        );
      }
      // Calls with more than one remote stream (e.g. the same account joined
      // from two devices, or a group call) → show a tile per participant so
      // every joined device gets its own icon.
      if (_remoteUids.length > 1) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 112, 20, 220),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              _voiceParticipantsGrid(),
              const SizedBox(height: 18),
              Text(_connectedAt == null ? _status : _formatElapsed(_elapsed),
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ]),
          ),
        );
      }
      // 1:1 call: premium voice stage — waveform-ringed avatar + name +
      // designation + ACTIVE CALL + timer, all centered.
      final remoteName = _remoteUids.isNotEmpty
          ? (_remoteNames[_remoteUids.first] ?? 'Participant')
          : (_callDisplayTitle());
      return _voiceCallStage(remoteName);
    }
    if (_remoteUids.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Soft pulsing ring around the call icon while we wait.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1.0),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOut,
            builder: (ctx, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: const Icon(Icons.videocam_outlined,
                  color: Colors.white38, size: 46),
            ),
          ),
          const SizedBox(height: 22),
          Text(_joined ? 'Waiting for others to join…' : _status,
              style: const TextStyle(color: Colors.white70, fontSize: 15)),
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
    // One entry per live remote stream (so the same account on two devices
    // reads as two participants), labelled from the announce map.
    final names =
        _remoteUids.map((uid) => _remoteNames[uid] ?? 'Participant').toList();
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
    // Me first, then one tile per live remote stream (keyed by Agora uid, so
    // two devices of the same account show as two tiles).
    final names = <String>[
      me?.name ?? 'You',
      ..._remoteUids.map((uid) => _remoteNames[uid] ?? 'Participant'),
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

  /// A single circular control button used inside the WhatsApp/Meet bars.
  Widget _ctrlCircle({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    Color? background,
    Color? iconColor,
    double size = 52,
    double iconSize = 22,
  }) {
    final Color bg =
        background ?? (active ? Colors.white : Colors.white.withOpacity(0.14));
    final Color fg = iconColor ??
        (background != null
            ? Colors.white
            : (active ? Colors.black : Colors.white));
    return _PressableCircle(
      onTap: onTap,
      size: size,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          boxShadow: background != null
              ? [
                  BoxShadow(
                    color: background.withOpacity(0.5),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Icon(icon, color: fg, size: iconSize),
      ),
    );
  }

  // ───────────────────────── Premium voice-call UI ─────────────────────────

  /// The other party's designation (admin-set customTitle) / role, shown under
  /// their name on the voice-call stage.
  String? _callDisplaySubtitle() {
    final me = ref.read(authStoreProvider).user;
    final call = (_callMeta?['call'] as Map?)?.cast<String, dynamic>();
    final initiator = (call?['initiator'] as Map?)?.cast<String, dynamic>();
    if (call?['kind'] == 'GROUP' && initiator?['id'] != me?.id) {
      final title = (initiator?['customTitle'] ?? initiator?['role'] ?? '')
          .toString()
          .trim();
      if (title.isNotEmpty) return title.replaceAll('_', ' ');
    }
    final parts = (_callMeta?['call']?['participants'] as List?) ??
        (_callMeta?['participants'] as List?) ??
        const [];
    for (final p in parts) {
      if (p is! Map) continue;
      if (p['userId'] == me?.id) continue;
      final u = (p['user'] as Map?)?.cast<String, dynamic>();
      final title = (u?['customTitle'] ?? '').toString().trim();
      if (title.isNotEmpty) return title;
      final role = (u?['role'] ?? '').toString().trim();
      if (role.isNotEmpty) {
        return role
            .replaceAll('_', ' ')
            .toLowerCase()
            .split(' ')
            .map(
                (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
      }
    }
    return null;
  }

  String? _callDisplayAvatarUrl() {
    final me = ref.read(authStoreProvider).user;
    final call = (_callMeta?['call'] as Map?)?.cast<String, dynamic>();
    final initiator = (call?['initiator'] as Map?)?.cast<String, dynamic>();
    if (call?['kind'] == 'GROUP' && initiator?['id'] != me?.id) {
      final url = initiator?['avatarUrl']?.toString();
      if (url != null && url.isNotEmpty) return url;
    }
    final parts = (_callMeta?['call']?['participants'] as List?) ??
        (_callMeta?['participants'] as List?) ??
        const [];
    for (final p in parts) {
      if (p is! Map || p['userId'] == me?.id) continue;
      final user = (p['user'] as Map?)?.cast<String, dynamic>();
      final url = user?['avatarUrl']?.toString();
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  /// Centered premium stage: waveform-ringed avatar with a live status badge,
  /// the caller's name + designation, and the ACTIVE CALL label + timer.
  Widget _voiceCallStage(String remoteName) {
    final subtitle = _callDisplaySubtitle();
    final connected = _connectedAt != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 120, 24, 232),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 230,
              height: 230,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Animated concentric rings + side equalizer bars.
                  const _PulseRings(size: 230, active: true),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00F2FF).withValues(alpha: 0.5),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color:
                              const Color(0xFFFF00EA).withValues(alpha: 0.38),
                          blurRadius: 52,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: BestieAvatar(
                      name: remoteName,
                      imageUrl: _callDisplayAvatarUrl(),
                      size: 150,
                    ),
                  ),
                  // Small green "in call" badge bottom-right of the avatar.
                  Positioned(
                    right: 44,
                    bottom: 44,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF0B1220), width: 3),
                      ),
                      child: const Icon(Icons.call_rounded,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Text(
              remoteName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 5),
            Text(
              _headOfficeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF76839E),
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 18),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.graphic_eq_rounded,
                  size: 15,
                  color: connected ? const Color(0xFF22C55E) : Colors.white54),
              const SizedBox(width: 6),
              Text(
                connected ? 'ACTIVE CALL' : _status.toUpperCase(),
                style: TextStyle(
                  color: connected
                      ? const Color(0xFF22C55E)
                      : _status.toLowerCase().contains('ring')
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFEF4444),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              connected ? _formatElapsed(_elapsed) : '00:00',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Top status chips: HD Voice / Network / Secure calling.
  Widget _topChips() {
    final net = _reconnecting ? 'Reconnecting' : 'Excellent';
    final netColor =
        _reconnecting ? const Color(0xFFFBBF24) : const Color(0xFF22C55E);
    return Row(children: [
      Expanded(
        child: _statChip(Icons.graphic_eq_rounded, 'HD Voice', 'Crystal Clear',
            const Color(0xFF60A5FA)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _statChip(
            Icons.signal_cellular_alt_rounded, 'Network', net, netColor),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _statChip(Icons.shield_outlined, 'Secure calling', 'Connected',
            const Color(0xFF38BDF8)),
      ),
    ]);
  }

  Widget _statChip(IconData icon, String title, String sub, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 7),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
            ],
          ),
        ),
      ]),
    );
  }

  bool _held = false;
  Future<void> _toggleHold() async {
    final engine = _engine;
    if (engine == null) return;
    final next = !_held;
    try {
      await engine.muteLocalAudioStream(next || _muted);
      await engine.muteAllRemoteAudioStreams(next);
      if (_isVideo) await engine.muteLocalVideoStream(next || _cameraOff);
    } catch (_) {/* best-effort */}
    if (mounted) setState(() => _held = next);
  }

  Future<void> _showCallNotes() async {
    final callId = widget.callId;
    if (callId == null) return;
    final initial =
        (_callMeta?['call']?['notes'] ?? _callMeta?['notes'] ?? '').toString();
    final controller = TextEditingController(text: initial);
    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Call notes'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 5,
          maxLines: 10,
          maxLength: 4000,
          decoration: const InputDecoration(
            hintText: 'Write notes for this call...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (notes == null) return;
    try {
      final updated = await ref
          .read(apiProvider)
          .dio
          .patch('/calls/$callId/notes', data: {'notes': notes});
      if (_callMeta != null) _callMeta!['call'] = updated.data;
      if (mounted) {
        bestieToast(context, 'Call notes saved', kind: BestieToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not save notes',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  Future<void> _showTransfer() async {
    final callId = widget.callId;
    if (callId == null) return;
    try {
      final me = ref.read(authStoreProvider).user;
      final people = (await ref.read(apiProvider).listEmployees())
          .where((u) => u['id'] != me?.id)
          .toList();
      if (!mounted) return;
      final target = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final c = BestieColors.of(ctx);
          return Container(
            constraints: const BoxConstraints(maxHeight: 520),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text('Transfer call to',
                    style: TextStyle(
                        color: c.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final user in people)
                      ListTile(
                        leading: BestieAvatar(
                          name: (user['name'] ?? 'User').toString(),
                          imageUrl: user['avatarUrl']?.toString(),
                          size: 38,
                        ),
                        title: Text((user['name'] ?? 'User').toString()),
                        subtitle: Text(
                            (user['customTitle'] ?? user['role'] ?? '')
                                .toString()
                                .replaceAll('_', ' ')),
                        onTap: () => Navigator.pop(ctx, user),
                      ),
                  ],
                ),
              ),
            ]),
          );
        },
      );
      if (target == null) return;
      await ref.read(apiProvider).post('/calls/$callId/transfer', body: {
        'targetUserId': target['id'],
        'mode': widget.mode.toUpperCase(),
      });
      await _speak(
          '${me?.name ?? 'A participant'} transferred the call to ${target['name']}.');
      await _teardown();
      if (mounted) context.go('/chat');
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not transfer call',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  void _openVoiceMail() {
    bestieToast(context, 'Voice mail',
        body: 'Opening the call chat so you can record a voice message.',
        kind: BestieToastKind.info);
    _openCallChat();
  }

  /// Premium 2-row control grid + bottom action bar, matching the redesign.
  Widget _premiumCallControls() {
    final routeActive = _route != CallAudioRoute.earpiece;
    final bluetoothOn = _route == CallAudioRoute.bluetooth;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          _gridTile(Icons.mic_off_rounded, 'Mute',
              active: _muted, onTap: _toggleMute),
          _gridTile(_audioRouteIcon(_route), 'Speaker',
              active: routeActive && !bluetoothOn, onTap: _cycleAudioRoute),
          _gridTile(Icons.bluetooth_rounded, 'Bluetooth',
              active: bluetoothOn, onTap: _cycleAudioRoute),
          _gridTile(Icons.pause_rounded, 'Hold',
              active: _held, onTap: _toggleHold),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _gridTile(Icons.voicemail_rounded, 'Voice Mail',
              onTap: _openVoiceMail),
          _gridTile(Icons.swap_calls_rounded, 'Transfer', onTap: _showTransfer),
          _gridTile(Icons.person_add_alt_1_rounded, 'Add', onTap: _showInvite),
          if (_isCallInitiator)
            _gridTile(Icons.fiber_manual_record_rounded, 'Record',
                active: _recording,
                accent: const Color(0xFFEF4444),
                onTap: _toggleRecord),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _gridTile(Icons.dialpad_rounded, 'Keyboard',
              onTap: () => bestieToast(context, 'Keypad ready')),
          _gridTile(Icons.note_alt_outlined, 'Notes', onTap: _showCallNotes),
          _gridTile(Icons.campaign_rounded, 'Buzzer',
              accent: const Color(0xFFFBBF24), onTap: _sendEmergencyBuzzer),
        ]),
        const SizedBox(height: 18),
        // Bottom action bar: message · end · keypad placeholder.
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _ctrlCircle(
              icon: Icons.chat_bubble_outline_rounded,
              onTap: _openCallChat,
              size: 46,
              iconSize: 20),
          const SizedBox(width: 36),
          _PressableCircle(
            onTap: _hangup,
            size: 72,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                      blurRadius: 24,
                      spreadRadius: 1),
                ],
              ),
              child: const Icon(Icons.call_end_rounded,
                  color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(width: 36),
          _ctrlCircle(
              icon: (!_videoEnabled || _cameraOff)
                  ? Icons.videocam_off_rounded
                  : Icons.videocam_rounded,
              onTap: _toggleCamera,
              size: 46,
              iconSize: 20),
        ]),
      ]),
    );
  }

  /// One rounded-card control in the premium grid.
  Widget _gridTile(IconData icon, String label,
      {bool active = false, Color? accent, required VoidCallback onTap}) {
    final a = accent ?? const Color(0xFF60A5FA);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: _PressableCircle(
          onTap: onTap,
          size: 76,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 76,
            decoration: BoxDecoration(
              color: active
                  ? a.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active
                    ? a.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.10),
              ),
              boxShadow: [
                BoxShadow(
                  color: a.withValues(alpha: active ? 0.42 : 0.20),
                  blurRadius: active ? 24 : 16,
                  spreadRadius: active ? 2 : 0,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (label == 'Record' && active)
                  _RecordingPulse(child: Icon(icon, color: a, size: 22))
                else
                  Icon(icon, color: active ? a : Colors.white, size: 22),
                const SizedBox(height: 6),
                Text(label,
                    style: TextStyle(
                        color: active ? a : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the call's chat channel (message button on the call screen).
  void _openCallChat() {
    final channelId =
        (_callMeta?['call']?['channelId'] ?? _callMeta?['channelId'])
            ?.toString();
    if (channelId == null || channelId.isEmpty) {
      bestieToast(context, 'Chat opens after the call connects',
          kind: BestieToastKind.info);
      return;
    }
    _minimize();
    ref.read(routerProvider).go('/chat/$channelId');
  }

  Widget _controls() {
    if (_isMeeting) return _meetingControls();
    // Premium grid for voice calls; keep the compact pill for video calls so
    // it doesn't cover the video feed.
    final showingVideo = _isVideo && _remoteUids.isNotEmpty;
    return showingVideo ? _callControls() : _premiumCallControls();
  }

  /// WhatsApp call controls — one translucent rounded pill with 5 circles:
  /// more · camera · speaker · mic · end. Share / Record / Flip live in the
  /// `_showMore` sheet to keep the bar uncluttered.
  Widget _callControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ctrlCircle(icon: Icons.more_horiz_rounded, onTap: _showMore),
          _ctrlCircle(
            icon: (!_videoEnabled || _cameraOff)
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            onTap: _toggleCamera,
            active: !_videoEnabled || _cameraOff,
          ),
          _ctrlCircle(
            icon: _audioRouteIcon(_route),
            onTap: _cycleAudioRoute,
            active: _route != CallAudioRoute.earpiece,
          ),
          _ctrlCircle(
            icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            onTap: _toggleMute,
            active: _muted,
          ),
          _ctrlCircle(
            icon: Icons.call_end_rounded,
            onTap: _hangup,
            background: BestieTokens.cDanger,
          ),
        ]),
      ),
    );
  }

  /// Google Meet meeting controls — six circles in a row: mic · camera ·
  /// share · raise hand · more · leave.
  Widget _meetingControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.62),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ctrlCircle(
            icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            onTap: _toggleMute,
            active: _muted,
          ),
          _ctrlCircle(
            icon: (!_videoEnabled || _cameraOff)
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            onTap: _toggleCamera,
            active: !_videoEnabled || _cameraOff,
          ),
          _ctrlCircle(
            icon: _sharing
                ? Icons.stop_screen_share_rounded
                : Icons.present_to_all_rounded,
            onTap: _toggleShare,
            active: _sharing,
          ),
          _ctrlCircle(
            icon: Icons.front_hand_outlined,
            onTap: () =>
                bestieToast(context, 'Hand raised', kind: BestieToastKind.info),
          ),
          _ctrlCircle(
            icon: Icons.more_vert_rounded,
            onTap: _showMore,
          ),
          _ctrlCircle(
            icon: Icons.call_end_rounded,
            onTap: _hangup,
            background: BestieTokens.cDanger,
            size: 56,
            iconSize: 24,
          ),
        ]),
      ),
    );
  }

  /// Overflow menu reached from the call/meeting controls' "more" button.
  /// Holds the secondary actions (screen share, record, flip camera,
  /// participants) so the main controls stay clean and WhatsApp-like.
  void _showMore() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = BestieColors.of(ctx);
        Widget tile(IconData icon, String label, VoidCallback onTap,
            {Color? color}) {
          return ListTile(
            leading: Icon(icon, color: color ?? c.text),
            title: Text(label, style: TextStyle(color: c.text)),
            onTap: () {
              Navigator.of(ctx).pop();
              onTap();
            },
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(BestieTokens.rXl)),
          ),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: c.borderStrong,
                  borderRadius: BorderRadius.circular(BestieTokens.rPill),
                ),
              ),
              tile(
                _sharing
                    ? Icons.stop_screen_share_rounded
                    : Icons.screen_share_rounded,
                _sharing ? 'Stop sharing' : 'Share screen',
                _toggleShare,
                color: _sharing ? c.danger : null,
              ),
              tile(
                _savingRecording
                    ? Icons.hourglass_top_rounded
                    : (_recording
                        ? Icons.stop_circle_rounded
                        : Icons.fiber_manual_record_rounded),
                _savingRecording
                    ? 'Saving recording…'
                    : (_recording ? 'Stop recording' : 'Record call'),
                _toggleRecord,
                color: _recording ? c.danger : null,
              ),
              if (_isVideo)
                tile(Icons.cameraswitch_outlined, 'Flip camera', _flipCamera),
              tile(Icons.people_alt_rounded, 'Participants', _showParticipants),
              const SizedBox(height: 4),
            ]),
          ),
        );
      },
    );
  }
}

/// Audio output route the user can cycle through: earpiece → speaker →
/// bluetooth. Earpiece and bluetooth both keep the loudspeaker off; when a
/// Bluetooth headset is connected Android routes to it automatically.
enum CallAudioRoute { earpiece, speaker, bluetooth }

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

/// A circular control that scales down slightly while pressed for tactile
/// feedback — used by every call/meeting control button.
/// Concentric expanding rings behind the voice-call avatar — the "waveform"
/// pulse from the redesign. Purely decorative; runs only while [active].
class _PulseRings extends StatefulWidget {
  final double size;
  final bool active;
  const _PulseRings({required this.size, this.active = true});

  @override
  State<_PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<_PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _PulseRings old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(alignment: Alignment.center, children: [
            for (int i = 0; i < 3; i++) _ring((_ctrl.value + i / 3) % 1.0),
          ]),
        );
      },
    );
  }

  Widget _ring(double t) {
    final size = widget.size * (0.62 + 0.38 * t);
    final opacity = (1 - t).clamp(0.0, 1.0) * 0.5;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color:
              Color.lerp(const Color(0xFFFF00EA), const Color(0xFF00F2FF), t)!
                  .withValues(alpha: opacity),
          width: 2,
        ),
      ),
    );
  }
}

class _FuturisticCallBackdrop extends StatelessWidget {
  const _FuturisticCallBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(children: const [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-1.15, -0.05),
              radius: 1.2,
              colors: [Color(0x66FF00EA), Color(0x0003060C)],
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(1.15, -0.05),
              radius: 1.2,
              colors: [Color(0x6600F2FF), Color(0x0003060C)],
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.15),
              radius: 1.25,
              colors: [Color(0x0003060C), Color(0xFF03060C)],
              stops: [0.08, 1],
            ),
          ),
        ),
      ),
    ]);
  }
}

class _RecordingPulse extends StatefulWidget {
  final Widget child;
  const _RecordingPulse({required this.child});

  @override
  State<_RecordingPulse> createState() => _RecordingPulseState();
}

class _RecordingPulseState extends State<_RecordingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.25, end: 1).animate(_controller),
        child: widget.child,
      );
}

class _PressableCircle extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double size;
  const _PressableCircle(
      {required this.child, required this.onTap, required this.size});

  @override
  State<_PressableCircle> createState() => _PressableCircleState();
}

class _PressableCircleState extends State<_PressableCircle> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: widget.child,
        ),
      ),
    );
  }
}
