import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
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
import '../app_sounds.dart';
import '../call_proximity.dart';
import '../call_screen_theme.dart';
import '../router.dart';
import '../state.dart';
import '../widgets/call_dialpad_sheet.dart';
import '../widgets/call_screen_design.dart';

const _callNotificationChannel = MethodChannel('mytaskking/call_notification');
const _kPremiumControlGridWidth = 354.0;
const _kPremiumControlColumnGap = 10.0;

/// Outbound ring with no answer — matches server `RING_NO_ANSWER_MS` (60s).
const _kOutgoingRingTimeout = Duration(seconds: 60);

enum _CallMemberConnection { connected, ringing, notConnected }

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
  static bool held = false;
  static bool cameraOff = false;
  static CallAudioRoute audioRoute = CallAudioRoute.earpiece;
  static DateTime? connectedAt;
  static bool recording = false;
  static bool savingRecording = false;
  static String? recordingPath;
  static Timer? _audioRouteKeepAliveTimer;

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
  static final Map<int, bool> remoteVideoMuted = {};

  /// Real Agora uid → backend userId (from call.announce). Used to match
  /// volume-indication uids to tiles and to drop duplicate self tiles.
  static final Map<int, String> agoraUidToUserId = {};

  /// Local screen share active on this device.
  static bool screenSharing = false;

  /// Remote participant sharing their screen (Agora uid + userId).
  static int? remoteScreenShareUid;
  static String? remoteScreenShareUserId;

  /// Backend-tracked participants still in the call (userId → display name).
  /// Stable source of truth for the header count — Agora uid churn during
  /// reconnects no longer makes "2" flicker to "1".
  static final Map<String, String> joinedParticipants = {};

  /// Cached call metadata + remote peer display fields survive CallScreen
  /// dispose so the return bubble and re-opened call UI still show the person
  /// you are talking to (not a placeholder title / "Connecting…").
  static Map<String, dynamic>? callMeta;
  static String? remotePeerName;
  static String? remotePeerSubtitle;
  static String? remotePeerAvatarUrl;

  /// Bumps whenever the session activates or deactivates so widgets
  /// outside the call screen (e.g. the "ongoing call" return pill) can
  /// rebuild without polling.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static void _ping() {
    revision.value = revision.value + 1;
  }

  /// Notifies widgets outside the call screen (return bubble, etc.).
  static void notifyRevision() => _ping();

  static bool get isActive => engine != null;

  /// Re-apply the user's chosen output route on the live Agora engine.
  static Future<void> reapplyAudioRoute() async {
    final e = engine;
    if (e == null || !joined || held) return;
    final speaker = audioRoute == CallAudioRoute.speaker;
    try {
      await e.setDefaultAudioRouteToSpeakerphone(speaker);
    } catch (_) {}
    try {
      await e.setEnableSpeakerphone(speaker);
    } catch (_) {}
    try {
      await e.adjustPlaybackSignalVolume(speaker ? 255 : 160);
    } catch (_) {}
  }

  static void startAudioRouteKeepAlive() {
    _audioRouteKeepAliveTimer?.cancel();
    _audioRouteKeepAliveTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => unawaited(reapplyAudioRoute()),
    );
  }

  static void stopAudioRouteKeepAlive() {
    _audioRouteKeepAliveTimer?.cancel();
    _audioRouteKeepAliveTimer = null;
  }

  /// Wipe any in-memory call UI before placing a new outgoing call.
  static Future<void> prepareForNewCall() async {
    await teardown();
    ActiveCallState.clear();
    _ping();
  }

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
    held = false;
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
    remoteVideoMuted.clear();
    agoraUidToUserId.clear();
    screenSharing = false;
    remoteScreenShareUid = null;
    remoteScreenShareUserId = null;
    joinedParticipants.clear();
    callMeta = null;
    remotePeerName = null;
    remotePeerSubtitle = null;
    remotePeerAvatarUrl = null;
    stopAudioRouteKeepAlive();
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
  bool get _routeWantsVideo => widget.mode.toLowerCase() == 'video';
  Set<int> get _remoteUids => _CallSession.remoteUids;
  Map<int, String> get _remoteNames => _CallSession.remoteNames;
  Map<int, bool> get _remoteMuted => _CallSession.remoteMuted;
  Map<int, bool> get _remoteVideoMuted => _CallSession.remoteVideoMuted;
  Map<int, String> get _agoraUidToUserId => _CallSession.agoraUidToUserId;
  Map<String, String> get _joinedParticipants =>
      _CallSession.joinedParticipants;
  bool get _muted => _CallSession.muted;
  set _muted(bool v) => _CallSession.muted = v;
  bool get _held => _CallSession.held;
  set _held(bool v) => _CallSession.held = v;
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
  bool get _sharing => _CallSession.screenSharing;
  set _sharing(bool v) => _CallSession.screenSharing = v;
  int? get _remoteScreenShareUid => _CallSession.remoteScreenShareUid;
  set _remoteScreenShareUid(int? v) => _CallSession.remoteScreenShareUid = v;
  String? get _remoteScreenShareUserId => _CallSession.remoteScreenShareUserId;
  set _remoteScreenShareUserId(String? v) =>
      _CallSession.remoteScreenShareUserId = v;
  String? _syncedActiveSpeakerUserId;
  Timer? _speakerEmitTimer;
  String? _lastEmittedSpeakerUserId;
  bool _reconnecting = false;
  String? _error;
  Map<String, dynamic>? _callMeta;
  final List<void Function()> _callUnsubs = [];
  bool _remoteClosed = false;
  bool _hangingUp = false;
  bool _handRaised = false;
  final Map<String, String> _raisedHands = {};
  Timer? _timer;
  Timer? _audioHealthTimer;
  Timer? _tokenRefreshTimer;
  Timer? _ringTimeoutTimer;
  Timer? _waitingAnswerPollTimer;
  bool _frontCamera = true;
  Duration _elapsed = Duration.zero;
  final _ringtone = FlutterRingtonePlayer();
  final _tonePlayer = AudioPlayer();
  final _tts = FlutterTts();
  String _headOfficeName = 'HQ India';
  String? _ringingSoundUrl;
  String? _buzzerSoundUrl;
  bool _proximityNear = false;
  CallProximityController? _proximity;
  final Map<String, Timer> _participantLeaveTimers = {};
  /// Soft-offline Agora UIDs — keep person tiles during reconnect blips.
  final Map<int, Timer> _remoteOfflineGraceTimers = {};
  Timer? _remoteHangupFallbackTimer;
  static const _kRemoteHangupGrace = Duration(seconds: 3);
  static const _kRemoteOfflineUiGrace = Duration(seconds: 8);

  /// When each invitee was last rung — drives ringing vs ring-again in Members.
  final Map<String, DateTime> _invitedAtByUserId = {};
  static const _kInviteRingWindow = Duration(seconds: 60);

  /// Agora uid of the loudest current speaker (0 = local) — WhatsApp-style tile border.
  int? _activeSpeakerUid;
  static const _kSpeakingBorderColor = Color(0xFFE8A060);

  bool get _isVideo => _videoEnabled;
  bool get _isCallInitiator {
    final call = (_callMeta?['call'] as Map?)?.cast<String, dynamic>();
    return call?['initiatorId'] == ref.read(authStoreProvider).user?.id;
  }

  /// Outgoing 1:1 call still ringing — callee has not answered on the server.
  bool get _waitingForAnswer =>
      _joined &&
      _connectedAt == null &&
      !_isMeeting &&
      !_remoteClosed &&
      _isCallInitiator;

  /// True when the call is still live (not hanging up / remote ended).
  bool get _isLiveCallActive =>
      !_hangingUp &&
      !_remoteClosed &&
      _CallSession.engine != null &&
      (_CallSession.connectedAt != null || _joined);

  /// UI-only: show "Ending call…" only while we are actually tearing down.
  bool get _showEndingUi => _hangingUp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_CallSession.matches(widget.callId, widget.meetingSlug)) {
      _videoEnabled = _routeWantsVideo;
      // Voice calls default to earpiece (so Bluetooth/earpiece is used and the
      // call is private); video calls default to speaker.
      _route = _routeWantsVideo
          ? CallAudioRoute.speaker
          : CallAudioRoute.earpiece;
    }
    // The call screen is now on top — hide the return-to-call pill.
    _CallSession.onCallScreen = true;
    _CallSession._ping();
    _subscribeCallLifecycle();
    if (_CallSession.matches(widget.callId, widget.meetingSlug)) {
      _callMeta = _CallSession.callMeta;
      _restoreLiveCallUi();
    } else if (_callMeta == null &&
        widget.callId != null &&
        _CallSession.callMeta != null) {
      final seededId =
          (_CallSession.callMeta?['call'] as Map?)?['id']?.toString();
      if (seededId == widget.callId) {
        _callMeta = _CallSession.callMeta;
        _syncParticipantsFromCallMeta();
      }
    }
    if (!_routeWantsVideo && widget.meetingSlug == null) {
      unawaited(_startProximityIfVoice());
    }
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final u in _callUnsubs) {
      u();
    }
    _callUnsubs.clear();
    for (final t in _participantLeaveTimers.values) {
      t.cancel();
    }
    _participantLeaveTimers.clear();
    for (final t in _remoteOfflineGraceTimers.values) {
      t.cancel();
    }
    _remoteOfflineGraceTimers.clear();
    _remoteHangupFallbackTimer?.cancel();
    _timer?.cancel();
    _audioHealthTimer?.cancel();
    _tokenRefreshTimer?.cancel();
    _speakerEmitTimer?.cancel();
    _cancelOutgoingRingTimeout();
    _stopWaitingForAnswerPoll();
    _ringtone.stop();
    _tonePlayer.dispose();
    _tts.stop();
    unawaited(_proximity?.stop());
    _proximity = null;
    if (_CallSession.engine != null && _CallSession.joined) {
      unawaited(_CallSession.reapplyAudioRoute());
    }
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
      // Agora may briefly fire onLeaveChannel when backgrounded — restore the
      // live session flag so the timer does not flip to "Ending call…".
      if (_CallSession.engine != null && _CallSession.connectedAt != null) {
        _joined = true;
        _reconnecting = false;
        if (mounted) {
          setState(() => _status = 'Connected');
        }
      }
      if (_connectedAt != null) _startTimer();
      _reassertAudio();
      _showOngoingCallNotification();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Reassert the media path and foreground service before the screen locks.
      unawaited(_stopRingback());
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
      final status = data['status']?.toString();
      if (status == 'ENDED' || status == 'MISSED' || status == 'DECLINED') {
        _endBecauseRemoteClosed(Map<String, dynamic>.from(data));
      }
    }));
    _callUnsubs.add(rt.onAny('call.ended', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      _endBecauseRemoteClosed(Map<String, dynamic>.from(data));
    }));
    _callUnsubs.add(rt.onAny('call.busy', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      unawaited(_stopRingback());
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
      _playEmergencyBuzzer(
        data['fromName']?.toString(),
        data['audioUrl']?.toString(),
      );
    }));
    // Backend join — updates stable participant list only. Do NOT add agoraUid
    // to _remoteUids here: early rejoin emits a derived uid before the device
    // has joined Agora, which duplicated "You" + your own name on the grid.
    void onParticipantJoined([dynamic data]) {
      if (data is! Map || data['callId'] != callId) return;
      final userId = data['userId']?.toString();
      final name = data['userName']?.toString();
      final uidRaw = data['agoraUid'];
      final agoraUid = uidRaw is int ? uidRaw : int.tryParse('$uidRaw');
      final me = ref.read(authStoreProvider).user;
      final isSelf = userId != null && userId == me?.id;
      if (userId != null && userId.isNotEmpty) {
        final resolved =
            name ?? _joinedParticipants[userId] ?? 'Participant';
        _markParticipantJoined(userId, resolved);
        // Never treat our own server join as a remote stream — that made the
        // outbound ring UI show the caller's name until the callee answered.
        if (!isSelf && agoraUid != null && agoraUid > 0) {
          _agoraUidToUserId[agoraUid] = userId;
          _remoteNames[agoraUid] = resolved;
          _seenPeerUids.add(agoraUid);
          if (mounted) {
            setState(() => _remoteUids.add(agoraUid));
          }
        }
        if (!isSelf) _onCalleeAnsweredViaServer(userId);
      }
      if (mounted) setState(() {});
    }

    // A participant announced its real per-device Agora uid + name.
    void onAnnounce([dynamic data]) {
      if (data is! Map || data['callId'] != callId) return;
      final uidRaw = data['agoraUid'];
      final uid = uidRaw is int ? uidRaw : int.tryParse('$uidRaw');
      if (uid == null || uid <= 0) return;
      final userId = data['userId']?.toString();
      final me = ref.read(authStoreProvider).user;
      if (uid == _CallSession.myUid || userId == me?.id) return;
      final name = data['userName']?.toString();
      if (userId != null && userId.isNotEmpty) {
        _markParticipantJoined(
          userId,
          name ?? _joinedParticipants[userId] ?? 'Participant',
        );
        _bindRemoteUidName(uid, userId: userId, name: name);
        _onCalleeAnsweredViaServer(userId);
        _agoraUidToUserId[uid] = userId;
        _dedupeRemoteUidsForUser(userId, keepUid: uid);
      }
      if (!mounted) return;
      final isNew = _seenPeerUids.add(uid);
      setState(() {
        _remoteUids.add(uid);
        if (name != null && name.isNotEmpty) _remoteNames[uid] = name;
      });
      _purgeSelfFromRemoteTracking();
      _syncRemotePeerSnapshot();
      if (isNew) _announceSelf();
    }

    _callUnsubs.add(rt.onAny('call.participant.joined', onParticipantJoined));
    _callUnsubs.add(rt.onAny('call.announce', onAnnounce));
    _callUnsubs.add(rt.onAny('call.participant.left', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      final status = data['status']?.toString();
      if (status == 'ENDED' || status == 'MISSED') {
        _remoteHangupFallbackTimer?.cancel();
        unawaited(_endBecauseRemoteClosed(Map<String, dynamic>.from(data)));
        return;
      }
      _scheduleParticipantLeave(data['userId']?.toString());
    }));
    _callUnsubs.add(rt.onAny('call.signal', ([data]) {
      if (data is! Map) return;
      final payload = (data['payload'] as Map?)?.cast<String, dynamic>();
      if (payload == null) return;
      final enriched = Map<String, dynamic>.from(payload);
      if (enriched['fromUserId'] == null && data['from'] != null) {
        enriched['fromUserId'] = data['from'];
      }
      _handleCallSignalPayload(enriched);
    }));
    // Legacy handlers if backend is updated later.
    _callUnsubs.add(rt.onAny('call.activeSpeaker', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      _handleCallSignalPayload({
        'callId': callId,
        'type': 'activeSpeaker',
        'userId': data['userId'],
      });
    }));
    _callUnsubs.add(rt.onAny('call.screenShare', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      _handleCallSignalPayload({
        'callId': callId,
        'type': 'screenShare',
        'userId': data['userId'],
        'active': data['active'],
        'agoraUid': data['agoraUid'],
      });
    }));
    _callUnsubs.add(rt.onAny('call.participant.muted', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      final me = ref.read(authStoreProvider).user;
      if (data['userId'] == me?.id) return;
      // Agora's onUserMuteAudio callback supplies the per-device value. This
      // socket event makes sure the call UI repaints immediately as well.
      if (mounted) setState(() {});
    }));
    _callUnsubs.add(rt.onAny('call.participants.updated', ([data]) {
      if (data is! Map || data['callId'] != callId) return;
      final call = (data['call'] as Map?)?.cast<String, dynamic>();
      if (call == null) return;
      if (_callMeta != null) _callMeta!['call'] = call;
      _syncParticipantsFromCallMeta();
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
    if (me != null) _markParticipantJoined(me.id, me.name);
    ref.read(apiProvider).post('/calls/$callId/announce',
        body: {'agoraUid': uid, 'userName': me?.name ?? ''}).then((_) {
      if (me != null) _agoraUidToUserId[uid] = me.id;
    }).catchError((_) => <String, dynamic>{});
  }

  void _markInvited(Iterable<String> userIds) {
    final now = DateTime.now();
    for (final id in userIds) {
      if (id.isEmpty) continue;
      _invitedAtByUserId[id] = now;
    }
  }

  List<Map<String, dynamic>> _participantsFromMeta() {
    final call = (_callMeta?['call'] as Map?)?.cast<String, dynamic>();
    return (call?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
  }

  DateTime? _callCreatedAt() {
    final raw = (_callMeta?['call'] as Map?)?['createdAt']?.toString();
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// User ids currently connected (joined, not left) — used to disable Add list.
  Set<String> _userIdsInCall() {
    final ids = <String>{};
    final me = ref.read(authStoreProvider).user?.id;
    if (me != null) ids.add(me);
    for (final p in _participantsFromMeta()) {
      if (p['joinedAt'] != null && p['leftAt'] == null) {
        final id = p['userId']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    for (final id in _joinedParticipants.keys) {
      ids.add(id);
    }
    return ids;
  }

  String _participantProfileName(Map<String, dynamic> p) {
    final user = (p['user'] as Map?)?.cast<String, dynamic>();
    final name = (user?['name'] ?? 'Participant').toString().trim();
    return name.isEmpty ? 'Participant' : name;
  }

  String? _nameFromCallMeta(String userId) {
    for (final p in _participantsFromMeta()) {
      if (p['userId']?.toString() == userId) {
        return _participantProfileName(p);
      }
    }
    return null;
  }

  String _displayNameForUserId(String? userId, {String fallback = 'Participant'}) {
    if (userId == null || userId.isEmpty) return fallback;
    final me = ref.read(authStoreProvider).user;
    if (userId == me?.id) return me?.name ?? 'You';
    final joined = _joinedParticipants[userId]?.trim();
    if (joined != null && joined.isNotEmpty) return joined;
    final meta = _nameFromCallMeta(userId);
    if (meta != null && meta.isNotEmpty && meta != 'Participant') return meta;
    return fallback;
  }

  String _displayNameForAgoraUid(int uid) {
    final cached = _remoteNames[uid]?.trim();
    if (cached != null && cached.isNotEmpty && cached != 'Participant') {
      return cached;
    }
    final userId = _agoraUidToUserId[uid];
    if (userId != null) {
      final resolved = _displayNameForUserId(userId, fallback: '');
      if (resolved.isNotEmpty) return resolved;
    }
    return cached?.isNotEmpty == true ? cached! : 'Participant';
  }

  void _bindRemoteUidName(int uid, {String? userId, String? name}) {
    if (userId != null && userId.isNotEmpty) {
      _agoraUidToUserId[uid] = userId;
      final resolved = (name != null && name.trim().isNotEmpty)
          ? name.trim()
          : _displayNameForUserId(userId);
      _remoteNames[uid] = resolved;
      _markParticipantJoined(userId, resolved);
      return;
    }
    final resolved = _displayNameForAgoraUid(uid);
    if (resolved != 'Participant') _remoteNames[uid] = resolved;
  }

  _CallMemberConnection _memberConnection(Map<String, dynamic> p) {
    if (p['joinedAt'] != null && p['leftAt'] == null) {
      return _CallMemberConnection.connected;
    }
    final userId = p['userId']?.toString() ?? '';
    if (p['joinedAt'] == null && p['leftAt'] == null) {
      final invitedAt =
          _invitedAtByUserId[userId] ?? _callCreatedAt() ?? DateTime.now();
      if (DateTime.now().difference(invitedAt) < _kInviteRingWindow) {
        return _CallMemberConnection.ringing;
      }
      return _CallMemberConnection.notConnected;
    }
    if (p['joinedAt'] == null && p['leftAt'] != null) {
      return _CallMemberConnection.notConnected;
    }
    return _CallMemberConnection.notConnected;
  }

  Future<void> _refreshCallMeta() async {
    if (widget.callId == null) return;
    try {
      final fresh = await _fetchToken();
      _callMeta = fresh;
      _CallSession.callMeta = fresh;
      _syncParticipantsFromCallMeta();
    } catch (_) {}
  }

  Future<void> _ringParticipantAgain(String userId) async {
    final callId = widget.callId;
    if (callId == null) return;
    try {
      await ref.read(apiProvider).addCallParticipants(
            callId,
            [userId],
            mode: widget.mode.toUpperCase(),
          );
      _markInvited([userId]);
      await _refreshCallMeta();
      if (mounted) {
        setState(() {});
        bestieToast(context, 'Ringing again', kind: BestieToastKind.info);
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not ring',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  void _markParticipantJoined(String userId, String name) {
    _invitedAtByUserId.remove(userId);
    _participantLeaveTimers[userId]?.cancel();
    _participantLeaveTimers.remove(userId);
    _joinedParticipants[userId] = name;
    final me = ref.read(authStoreProvider).user;
    if (me != null && userId != me.id && name.trim().isNotEmpty) {
      _CallSession.remotePeerName = name.trim();
    }
  }

  void _scheduleParticipantLeave(String? userId) {
    if (userId == null || userId.isEmpty) return;
    final me = ref.read(authStoreProvider).user?.id;
    if (userId == me) return;
    _participantLeaveTimers[userId]?.cancel();
    _participantLeaveTimers[userId] = Timer(const Duration(seconds: 4), () {
      _participantLeaveTimers.remove(userId);
      _joinedParticipants.remove(userId);
      if (mounted) setState(() {});
    });
  }

  void _cancelRemoteOfflineGrace(int uid) {
    _remoteOfflineGraceTimers.remove(uid)?.cancel();
  }

  /// Keep remote UIDs briefly after Agora offline so the grid doesn't drop
  /// people during reconnect. Mapping (name / userId) is never cleared here.
  void _scheduleRemoteOfflineGrace(int uid) {
    _remoteOfflineGraceTimers[uid]?.cancel();
    _remoteOfflineGraceTimers[uid] = Timer(_kRemoteOfflineUiGrace, () {
      _remoteOfflineGraceTimers.remove(uid);
      if (!mounted) return;
      setState(() {
        _remoteUids.remove(uid);
        if (_remoteUids.isEmpty && _connectedAt != null) {
          _reconnecting = true;
          _status = 'Reconnecting…';
        } else if (_remoteUids.isNotEmpty) {
          _reconnecting = false;
          _status = 'Connected';
        }
      });
    });
  }

  bool _isOneToOneCall() {
    if (_isMeeting) return false;
    final call = (_callMeta?['call'] as Map?)?.cast<String, dynamic>();
    return call?['kind']?.toString() != 'GROUP';
  }

  void _scheduleRemoteHangupFallback() {
    if (_remoteClosed || _hangingUp) return;
    _remoteHangupFallbackTimer?.cancel();
    _remoteHangupFallbackTimer = Timer(_kRemoteHangupGrace, () {
      if (!mounted || _remoteClosed || _hangingUp) return;
      unawaited(_verifyRemoteHangupFromServer());
    });
  }

  Future<void> _verifyRemoteHangupFromServer() async {
    if (_remoteClosed || _hangingUp || !mounted) return;
    final callId = widget.callId;
    if (callId == null || callId.isEmpty) return;
    try {
      final fresh = await ref.read(apiProvider).get('/calls/$callId/token');
      final call = (fresh['call'] as Map?)?.cast<String, dynamic>();
      final status = call?['status']?.toString();
      if (status == 'ENDED' ||
          status == 'MISSED' ||
          status == 'DECLINED' ||
          status == 'FAILED') {
        await _endBecauseRemoteClosed({'callId': callId, 'status': status});
        return;
      }
      if (_isOneToOneCall() && _remoteUids.isEmpty) {
        await _endBecauseRemoteClosed({'callId': callId, 'status': 'ENDED'});
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('ended') ||
          msg.contains('not found') ||
          msg.contains('404') ||
          msg.contains('403')) {
        await _endBecauseRemoteClosed({'callId': callId, 'status': 'ENDED'});
      }
    }
  }

  /// Drop stale remote uids that refer to this device (wrong derived uid from
  /// an early server join event, or a duplicate announce).
  void _purgeSelfFromRemoteTracking() {
    final me = ref.read(authStoreProvider).user;
    final meId = me?.id;
    final meName = me?.name?.trim();
    final myUid = _CallSession.myUid;
    final remove = <int>[];
    for (final uid in _remoteUids) {
      if (uid == myUid) {
        remove.add(uid);
        continue;
      }
      if (meId != null && _agoraUidToUserId[uid] == meId) {
        remove.add(uid);
        continue;
      }
      // Early call.participant.joined used a derived uid + your real name.
      if (meName != null &&
          meName.isNotEmpty &&
          !_agoraUidToUserId.containsKey(uid) &&
          _remoteNames[uid]?.trim() == meName) {
        remove.add(uid);
      }
    }
    if (remove.isEmpty) return;
    for (final uid in remove) {
      _remoteUids.remove(uid);
      _remoteNames.remove(uid);
      _remoteMuted.remove(uid);
      _agoraUidToUserId.remove(uid);
      _seenPeerUids.remove(uid);
    }
  }

  /// Keep one Agora uid per user when a newer announce arrives.
  void _dedupeRemoteUidsForUser(String userId, {required int keepUid}) {
    final keepName = _remoteNames[keepUid];
    final stale = <int>[];
    for (final uid in _remoteUids) {
      if (uid == keepUid) continue;
      if (_agoraUidToUserId[uid] == userId) {
        stale.add(uid);
        continue;
      }
      if (keepName != null &&
          keepName.isNotEmpty &&
          _remoteNames[uid] == keepName &&
          (_agoraUidToUserId[uid] == null ||
              _agoraUidToUserId[uid] == userId)) {
        stale.add(uid);
      }
    }
    for (final uid in stale) {
      _remoteUids.remove(uid);
      _remoteNames.remove(uid);
      _remoteMuted.remove(uid);
      _agoraUidToUserId.remove(uid);
      _seenPeerUids.remove(uid);
    }
  }

  int? _agoraUidForUserId(String? userId) {
    if (userId == null) return null;
    for (final e in _agoraUidToUserId.entries) {
      if (e.value == userId) return e.key;
    }
    return null;
  }

  String? _userIdForAgoraUid(int uid) {
    if (_isAgoraUidLocal(uid)) {
      return ref.read(authStoreProvider).user?.id;
    }
    return _agoraUidToUserId[uid];
  }

  void _emitActiveSpeaker(String? userId) {
    if (userId == _lastEmittedSpeakerUserId) return;
    _lastEmittedSpeakerUserId = userId;
    final meId = ref.read(authStoreProvider).user?.id;
    _broadcastCallSignal({
      'type': 'activeSpeaker',
      'userId': userId,
      'fromUserId': meId,
    });
  }

  void _scheduleActiveSpeakerEmit(String? userId) {
    _speakerEmitTimer?.cancel();
    _speakerEmitTimer = Timer(const Duration(milliseconds: 120), () {
      _emitActiveSpeaker(userId);
    });
  }

  /// Everyone we should fan out call signals to — DB join list plus anyone
  /// we've seen live in Agora (they can be connected before the server marks
  /// them joined, which is what broke screen-share notify).
  Set<String> _callPeerUserIds() {
    final meId = ref.read(authStoreProvider).user?.id;
    final peers = <String>{
      ..._joinedParticipants.keys,
      ..._agoraUidToUserId.values,
    };
    if (meId != null) peers.remove(meId);
    peers.removeWhere((id) => id.isEmpty);
    return peers;
  }

  void _emitScreenShareState({required bool active}) {
    final callId = widget.callId;
    if (callId == null) return;
    final meId = ref.read(authStoreProvider).user?.id;
    final agoraUid = active ? _CallSession.myUid : null;
    final rt = ref.read(realtimeProvider);

    // Primary path: backend fans out to every call participant in the DB.
    rt.emit('call.screenShare', {
      'callId': callId,
      'active': active,
      'agoraUid': agoraUid,
    });

    // Fallback for older clients / direct delivery when DB join lags Agora.
    final envelope = {
      'callId': callId,
      'type': 'screenShare',
      'active': active,
      'agoraUid': agoraUid,
      'fromUserId': meId,
    };
    for (final peerId in _callPeerUserIds()) {
      rt.emit('call.signal', {'to': peerId, 'payload': envelope});
    }
  }

  void _broadcastCallSignal(Map<String, dynamic> payload) {
    final callId = widget.callId;
    if (callId == null) return;
    final envelope = {...payload, 'callId': callId};
    final rt = ref.read(realtimeProvider);
    for (final peerId in _callPeerUserIds()) {
      rt.emit('call.signal', {'to': peerId, 'payload': envelope});
    }
  }

  void _handleCallSignalPayload(Map<String, dynamic> payload) {
    final callId = widget.callId;
    if (callId == null || payload['callId'] != callId) return;
    final type = payload['type']?.toString();
    if (type == 'activeSpeaker') {
      final speakerId = payload['userId']?.toString();
      if (mounted) {
        setState(() => _syncedActiveSpeakerUserId =
            speakerId != null && speakerId.isNotEmpty ? speakerId : null);
      }
      return;
    }
    if (type == 'screenShare') {
      final sharerId =
          payload['fromUserId']?.toString() ?? payload['userId']?.toString();
      final me = ref.read(authStoreProvider).user;
      if (sharerId != null && sharerId == me?.id) return;
      final active = payload['active'] == true;
      final uidRaw = payload['agoraUid'];
      var uid = uidRaw is int ? uidRaw : int.tryParse('$uidRaw');
      if (active && (uid == null || uid <= 0) && sharerId != null) {
        uid = _agoraUidForUserId(sharerId);
      }
      if (!mounted) return;
      setState(() {
        if (active && uid != null && uid > 0) {
          _remoteScreenShareUid = uid;
          _remoteScreenShareUserId = sharerId;
          if (sharerId != null) {
            _remoteUids.add(uid);
            _agoraUidToUserId[uid] = sharerId;
          }
          unawaited(_ensureRemoteVideoSubscribed(uid));
        } else {
          _remoteScreenShareUid = null;
          _remoteScreenShareUserId = null;
        }
      });
      return;
    }
    if (type == 'raiseHand') {
      final userId = payload['fromUserId']?.toString();
      if (userId == null || userId.isEmpty) return;
      final meId = ref.read(authStoreProvider).user?.id;
      if (userId == meId) return;
      final active = payload['active'] == true;
      final name = payload['userName']?.toString() ?? 'Participant';
      if (!mounted) return;
      setState(() {
        if (active) {
          _raisedHands[userId] = name;
        } else {
          _raisedHands.remove(userId);
        }
      });
      return;
    }
  }

  Future<void> _ensureRemoteVideoSubscribed(int uid) async {
    final engine = _engine;
    if (engine == null) return;
    try {
      // Voice calls join with camera off; make sure the video module is on
      // so screen-share tracks from the remote uid can be decoded.
      await engine.enableVideo();
      await engine.muteRemoteVideoStream(uid: uid, mute: false);
      await engine.muteAllRemoteVideoStreams(false);
    } catch (_) {}
  }

  Future<void> _playCallEndedSound() async {
    await AppSounds.playCallEnded();
    await Future<void>.delayed(const Duration(milliseconds: 320));
  }

  bool _isAgoraUidLocal(int uid) => uid == 0 || uid == _CallSession.myUid;

  void _syncParticipantsFromCallMeta() {
    final call = (_callMeta?['call'] as Map?)?.cast<String, dynamic>() ??
        _callMeta?.cast<String, dynamic>();
    final parts =
        (call?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
    for (final p in parts) {
      final userId = p['userId']?.toString();
      if (userId != null &&
          p['joinedAt'] == null &&
          p['leftAt'] == null &&
          !_invitedAtByUserId.containsKey(userId)) {
        _invitedAtByUserId[userId] = _callCreatedAt() ?? DateTime.now();
      }
      if (p['leftAt'] != null) continue;
      if (userId == null) continue;
      final me = ref.read(authStoreProvider).user;
      // Invited-but-not-joined yet shouldn't inflate the live count while ringing.
      if (p['joinedAt'] == null && userId != me?.id) continue;
      final user = (p['user'] as Map?)?.cast<String, dynamic>();
      final name = (user?['name'] ?? 'Participant').toString();
      _markParticipantJoined(userId, name);
      final uidRaw = p['agoraUid'];
      final agoraUid = uidRaw is int ? uidRaw : int.tryParse('$uidRaw');
      if (agoraUid != null && agoraUid > 0) {
        _agoraUidToUserId[agoraUid] = userId;
        _remoteNames[agoraUid] = name;
      }
    }
    final me = ref.read(authStoreProvider).user;
    if (me != null) _markParticipantJoined(me.id, me.name);
    _maybeMarkCalleeConnectedFromMeta();
  }

  /// If the server already marked the callee as joined but the socket event
  /// was missed, still flip the header from "Ringing…" to the live timer.
  void _maybeMarkCalleeConnectedFromMeta() {
    if (!_waitingForAnswer) return;
    final me = ref.read(authStoreProvider).user?.id;
    for (final p in _participantsFromMeta()) {
      final userId = p['userId']?.toString();
      if (userId == null || userId.isEmpty || userId == me) continue;
      if (p['joinedAt'] != null && p['leftAt'] == null) {
        _onCalleeAnsweredViaServer(userId);
        return;
      }
    }
  }

  void _maybeMarkConnectedFromRemoteAudio(List<AudioVolumeInfo> speakers) {
    if (!_waitingForAnswer) return;
    for (final s in speakers) {
      final uid = s.uid ?? 0;
      if (uid == 0 || _isAgoraUidLocal(uid)) continue;
      if ((s.volume ?? 0) >= 5) {
        _markRemoteConnected();
        _cancelOutgoingRingTimeout();
        unawaited(_stopRingback());
        return;
      }
    }
  }

  void _startWaitingForAnswerPoll() {
    _waitingAnswerPollTimer?.cancel();
    if (!_waitingForAnswer) return;
    _waitingAnswerPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_waitingForAnswer || !mounted) {
        _waitingAnswerPollTimer?.cancel();
        return;
      }
      unawaited(_refreshCallMeta().then((_) {
        if (mounted) _maybeMarkCalleeConnectedFromMeta();
      }));
    });
  }

  void _stopWaitingForAnswerPoll() {
    _waitingAnswerPollTimer?.cancel();
    _waitingAnswerPollTimer = null;
  }

  /// Stable participant count for the header chip — prefers backend join state
  /// over raw Agora uid count so reconnect blips don't flicker 1 ↔ 2.
  int get _participantCount {
    final backend = _joinedParticipants.length;
    if (backend > 0) return backend;
    return max(1, 1 + _remoteUids.length);
  }

  bool get _useWhatsAppParticipantGrid =>
      _isMeeting ||
      _isVideo ||
      _participantCount > 2 ||
      _joinedParticipants.length > 2 ||
      _remoteUids.length > 1 ||
      ((_callMeta?['call'] as Map?)?['kind'] == 'GROUP' &&
          _participantCount >= 3);

  Future<void> _enableSpeakerHighlight() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.enableAudioVolumeIndication(
        interval: 200,
        smooth: 3,
        reportVad: true,
      );
    } catch (_) {/* non-critical */}
  }

  bool _isParticipantSpeaking({
    required bool isLocal,
    required int? agoraUid,
    required String? userId,
    required bool muted,
  }) {
    if (muted) return false;
    if (userId != null &&
        _syncedActiveSpeakerUserId != null &&
        userId == _syncedActiveSpeakerUserId) {
      return true;
    }
    if (_activeSpeakerUid == null) return false;
    final active = _activeSpeakerUid!;
    if (isLocal) return _isAgoraUidLocal(active);
    final activeUserId = _agoraUidToUserId[active];
    if (userId != null && activeUserId == userId) return true;
    if (agoraUid != null && active == agoraUid) return true;
    final mappedUid = _agoraUidForUserId(userId);
    return mappedUid != null && active == mappedUid;
  }

  void _updateActiveSpeaker(List<AudioVolumeInfo> speakers) {
    if (!_useWhatsAppParticipantGrid) {
      if (_activeSpeakerUid != null && mounted) {
        setState(() => _activeSpeakerUid = null);
      }
      _scheduleActiveSpeakerEmit(null);
      return;
    }
    int? loudest;
    var loudestVol = 0;
    for (final s in speakers) {
      final vol = s.volume ?? 0;
      if (vol <= 0) continue;
      final uid = s.uid ?? 0;
      final muted =
          _isAgoraUidLocal(uid) ? _muted : (_remoteMuted[uid] ?? false);
      if (muted) continue;
      if (vol > loudestVol) {
        loudestVol = vol;
        loudest = uid;
      }
    }
    // Relative threshold — remote levels are often quieter than local.
    final minVol = loudestVol >= 25 ? 8 : 3;
    if (loudestVol < minVol) loudest = null;

    final speakerUserId = loudest != null ? _userIdForAgoraUid(loudest) : null;
    _scheduleActiveSpeakerEmit(speakerUserId);

    if (_activeSpeakerUid != loudest && mounted) {
      setState(() => _activeSpeakerUid = loudest);
    }
  }

  Future<void> _startProximityIfVoice() async {
    if (_isVideo || _isMeeting) return;
    _proximity ??= CallProximityController(onChanged: (near) {
      if (!mounted) return;
      setState(() => _proximityNear = near);
      // Never auto-switch away from speaker — user must turn it off manually.
      if (near && _route == CallAudioRoute.speaker) return;
      if (near && _route != CallAudioRoute.earpiece) {
        if (mounted) setState(() => _route = CallAudioRoute.earpiece);
        unawaited(_applyAudioRoute(CallAudioRoute.earpiece));
      }
    });
    await _proximity!.start();
  }

  Future<void> _stopProximity() async {
    await _proximity?.stop();
    _proximity = null;
    if (mounted) setState(() => _proximityNear = false);
  }

  Future<void> _endBecauseRemoteClosed([Map<String, dynamic>? data]) async {
    if (_remoteClosed) return;
    _remoteHangupFallbackTimer?.cancel();
    _remoteClosed = true;
    _hangingUp = true;
    _cancelOutgoingRingTimeout();
    await _stopRingback();
    unawaited(_playCallEndedSound());
    await _teardown(notifyServer: false);
    if (!mounted) return;
    final status = data?['status']?.toString();
    final body = status == 'MISSED'
        ? 'No answer — the call was not picked up.'
        : status == 'DECLINED'
            ? 'The other person declined the call.'
            : 'The other person left the call.';
    context.go('/chat');
    if (mounted) {
      bestieToast(
        context,
        status == 'MISSED' ? 'No answer' : 'Call ended',
        body: body,
        kind: BestieToastKind.info,
      );
    }
  }

  void _startTimer() {
    final started = _connectedAt;
    if (started == null) return;
    _timer?.cancel();
    void updateElapsed() {
      if (!mounted || _connectedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_connectedAt!));
    }

    updateElapsed();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      updateElapsed();
    });
  }

  void _startAudioHealthCheck() {
    _audioHealthTimer?.cancel();
    _audioHealthTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_joined && !_held) _reassertAudio();
    });
  }

  void _startTokenRefresh() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 15), (_) async {
      if (!_joined || _engine == null) return;
      try {
        final fresh = await _fetchToken();
        final newToken = fresh['token']?.toString();
        if (newToken != null) await _engine!.renewToken(newToken);
      } catch (_) {/* best-effort */}
    });
  }

  Future<void> _renewTokenNow() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      final fresh = await _fetchToken();
      final newToken = fresh['token']?.toString();
      if (newToken != null) await engine.renewToken(newToken);
    } catch (_) {}
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _publishActiveCallState() {
    _syncRemotePeerSnapshot();
    final displayTitle = _callDisplayTitle();
    final multiParty = _isMeeting ||
        _participantCount > 2 ||
        _remoteUids.length > 1 ||
        ((_callMeta?['call'] as Map?)?['kind'] == 'GROUP' &&
            _participantCount >= 2);
    String? liveRemoteName;
    if (multiParty &&
        displayTitle != 'Connecting…' &&
        displayTitle != 'In call') {
      liveRemoteName = displayTitle;
    } else {
      final me = ref.read(authStoreProvider).user;
      for (final entry in _remoteNames.entries) {
        if (_agoraUidToUserId[entry.key] == me?.id) continue;
        if (entry.value.trim().isNotEmpty) {
          liveRemoteName = entry.value.trim();
          break;
        }
      }
    }
    final title = widget.meetingSlug != null
        ? 'Meeting'
        : (_CallSession.remotePeerName ??
            liveRemoteName ??
            (displayTitle != 'Connecting…' && displayTitle != 'In call'
                ? displayTitle
                : 'Call'));
    final participants = <String>[];
    final me = ref.read(authStoreProvider).user;
    for (final entry in _remoteNames.entries) {
      if (_agoraUidToUserId[entry.key] == me?.id) continue;
      final n = entry.value.trim();
      if (n.isNotEmpty && !participants.contains(n)) participants.add(n);
    }
    if (participants.isEmpty) {
      for (final p in _participantsFromMeta()) {
        final userId = p['userId']?.toString();
        if (userId == null || userId == me?.id) continue;
        final n = _participantProfileName(p);
        if (n.isNotEmpty && n != 'Participant' && !participants.contains(n)) {
          participants.add(n);
        }
      }
    }
    ActiveCallState.update(
      title: title,
      participants: participants,
    );
  }

  /// Persist who we are on a call with so minimize → bubble → return keeps
  /// the correct name even after CallScreen disposes.
  void _syncRemotePeerSnapshot() {
    final me = ref.read(authStoreProvider).user;
    String? name;

    // Outbound ring: callee name comes from invite metadata, not Agora uids.
    if (_waitingForAnswer) {
      final fromMeta = _callDisplayTitle();
      if (fromMeta != 'Connecting…' && fromMeta != 'In call') {
        name = fromMeta;
      }
    }

    if (name == null) {
      for (final entry in _joinedParticipants.entries) {
        if (entry.key != me?.id && entry.value.trim().isNotEmpty) {
          name = entry.value.trim();
          break;
        }
      }
    }
    if (name == null && _remoteUids.isNotEmpty) {
      for (final uid in _remoteUids) {
        if (_agoraUidToUserId[uid] == me?.id) continue;
        final n = _remoteNames[uid]?.trim();
        if (n != null && n.isNotEmpty) {
          name = n;
          break;
        }
      }
    }
    if (name == null) {
      final fromMeta = _callDisplayTitle();
      if (fromMeta != 'Connecting…' && fromMeta != 'In call') {
        name = fromMeta;
      }
    }

    final subtitle = _callDisplaySubtitle();
    final avatar = _callDisplayAvatarUrl();

    if (name != null && name.isNotEmpty) {
      _CallSession.remotePeerName = name;
    }
    _CallSession.remotePeerSubtitle = subtitle;
    _CallSession.remotePeerAvatarUrl = avatar;
    if (_callMeta != null) {
      _CallSession.callMeta = Map<String, dynamic>.from(_callMeta!);
    }
    _CallSession._ping();
  }

  String _primaryRemoteDisplayName() {
    if (_waitingForAnswer) {
      final invited = _callDisplayTitle();
      if (invited != 'Connecting…' && invited != 'In call') {
        return invited;
      }
    }
    final cached = _CallSession.remotePeerName;
    if (cached != null &&
        cached.isNotEmpty &&
        cached != 'Call' &&
        cached != 'Connecting…' &&
        cached != 'In call') {
      return cached;
    }
    final activeTitle = ActiveCallState.current.value?.title;
    if (activeTitle != null &&
        activeTitle.isNotEmpty &&
        activeTitle != 'Call' &&
        activeTitle != 'Connecting…' &&
        activeTitle != 'In call') {
      return activeTitle;
    }
    final me = ref.read(authStoreProvider).user;
    if (_remoteUids.isNotEmpty) {
      for (final uid in _remoteUids) {
        if (_agoraUidToUserId[uid] == me?.id) continue;
        final n = _remoteNames[uid]?.trim();
        if (n != null && n.isNotEmpty) return n;
      }
    }
    for (final entry in _joinedParticipants.entries) {
      if (entry.key != me?.id && entry.value.trim().isNotEmpty) {
        return entry.value.trim();
      }
    }
    final fromMeta = _callDisplayTitle();
    if (fromMeta != 'Connecting…' && fromMeta != 'In call') return fromMeta;
    return cached ?? 'Participant';
  }

  String? _primaryRemoteSubtitle() =>
      _CallSession.remotePeerSubtitle ?? _callDisplaySubtitle();

  String? _primaryRemoteAvatarUrl() =>
      _CallSession.remotePeerAvatarUrl ?? _callDisplayAvatarUrl();

  List<({String name, String? imageUrl})> _desktopCompanionProfiles(
      String primaryName) {
    final me = ref.read(authStoreProvider).user;
    var skippedPrimary = false;
    final profiles = <({String name, String? imageUrl})>[];
    for (final p in _participantsFromMeta()) {
      final userId = p['userId']?.toString();
      if (userId != null && userId == me?.id) continue;
      if (_memberConnection(p) != _CallMemberConnection.connected) continue;
      final name = _participantProfileName(p);
      if (!skippedPrimary && name == primaryName) {
        skippedPrimary = true;
        continue;
      }
      final user = (p['user'] as Map?)?.cast<String, dynamic>();
      profiles.add((name: name, imageUrl: user?['avatarUrl']?.toString()));
    }
    return profiles.take(5).toList(growable: false);
  }

  /// When returning to an already-live call, restore timer + connected status
  /// from the static session instead of "Connecting…".
  void _restoreLiveCallUi() {
    if (_CallSession.connectedAt != null && _CallSession.engine != null) {
      _joined = true;
      _reconnecting = false;
      _startTimer();
      if (mounted) setState(() => _status = 'Connected');
      return;
    }
    // Still ringing — joined the Agora channel but callee has not answered.
    if (_waitingForAnswer) {
      _timer?.cancel();
      _elapsed = Duration.zero;
      if (mounted) setState(() => _status = 'Ringing…');
    }
  }

  void _markRemoteConnected() {
    if (_connectedAt == null) {
      _connectedAt = DateTime.now();
      ActiveCallState.markConnected(_connectedAt!);
    }
    _stopWaitingForAnswerPoll();
    _startTimer();
    _syncRemotePeerSnapshot();
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
        'startedAtMs': (_connectedAt ??
                ActiveCallState.current.value?.startedAt ??
                DateTime.now())
            .millisecondsSinceEpoch,
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
    await _stopProximity();
    _cancelOutgoingRingTimeout();
    await _stopRingback();
    await _tts.stop();
    _connectedAt = null;
    _syncedActiveSpeakerUserId = null;
    _lastEmittedSpeakerUserId = null;
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
          _error = null;
          // Before anyone answers we're ringing them, not connected.
          _status = _remoteUids.isEmpty ? 'Ringing…' : 'Connected';
        });
        unawaited(_enableSpeakerHighlight());
        _purgeSelfFromRemoteTracking();
        _publishActiveCallState();
        _showOngoingCallNotification();
        _CallSession.startAudioRouteKeepAlive();
        _startAudioHealthCheck();
        _startTokenRefresh();
        if (_remoteUids.isEmpty && !_isMeeting && _isCallInitiator) {
          unawaited(_playRingback());
          _startOutgoingRingTimeout();
          _startWaitingForAnswerPoll();
        }
        if (!_isVideo) unawaited(_startProximityIfVoice());
      },
      onUserJoined: (conn, remoteUid, elapsed) {
        if (!mounted) return;
        _remoteHangupFallbackTimer?.cancel();
        _bindRemoteUidName(remoteUid);
        _cancelRemoteOfflineGrace(remoteUid);
        setState(() {
          _remoteUids.add(remoteUid);
          _reconnecting = false;
        });
        unawaited(_ensureRemoteVideoSubscribed(remoteUid));
        // During outbound ringing, prefer the server join event — but if that
        // socket message is missed, fall back to meta/audio checks below.
        if (_waitingForAnswer) {
          unawaited(_refreshCallMeta().then((_) {
            if (mounted) _maybeMarkCalleeConnectedFromMeta();
          }));
          return;
        }
        _markRemoteConnected();
        _cancelOutgoingRingTimeout();
        unawaited(_stopRingback());
        _reassertAudio();
        _publishActiveCallState();
        _showOngoingCallNotification();
      },
      onUserOffline: (conn, remoteUid, reason) {
        if (!mounted) return;
        // Soft-offline: keep the person tile (joinedParticipants / name map)
        // during reconnect blips. Only drop the live Agora uid after a grace
        // window if they never come back.
        setState(() {
          _reconnecting = _connectedAt != null;
          _status = _connectedAt == null ? 'Ringing…' : 'Reconnecting…';
        });
        _scheduleRemoteOfflineGrace(remoteUid);
        // Agora fires this for network blips too; confirm with the server
        // (call.participant.left / call.ended) before ending locally.
        _scheduleRemoteHangupFallback();
      },
      onAudioVolumeIndication: (conn, speakers, speakerNumber, totalVolume) {
        if (!mounted) return;
        _maybeMarkConnectedFromRemoteAudio(speakers);
        _updateActiveSpeaker(speakers);
      },
      onVideoSizeChanged: (conn, sourceType, uid, width, height, rotation) {
        if (!mounted) return;
        final isScreen =
            sourceType == VideoSourceType.videoSourceScreenPrimary ||
                sourceType == VideoSourceType.videoSourceScreen;
        if (!isScreen) return;
        setState(() {
          if (width > 0 && height > 0) {
            if (uid == 0 || uid == _CallSession.myUid) {
              _sharing = true;
            } else {
              _remoteScreenShareUid = uid;
              _remoteScreenShareUserId = _agoraUidToUserId[uid];
            }
          } else if (uid == 0 || uid == _CallSession.myUid) {
            _sharing = false;
          } else if (uid == _remoteScreenShareUid) {
            _remoteScreenShareUid = null;
            _remoteScreenShareUserId = null;
          }
        });
        if (width > 0 && height > 0 && uid != 0) {
          unawaited(_ensureRemoteVideoSubscribed(uid));
        }
      },
      onLocalVideoStateChanged: (source, state, reason) {
        if (!mounted) return;
        final isScreen = source == VideoSourceType.videoSourceScreenPrimary ||
            source == VideoSourceType.videoSourceScreen;
        if (!isScreen) return;
        if (state == LocalVideoStreamState.localVideoStreamStateStopped ||
            state == LocalVideoStreamState.localVideoStreamStateFailed) {
          setState(() => _sharing = false);
          _emitScreenShareState(active: false);
        }
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
      onUserMuteVideo: (conn, remoteUid, muted) {
        if (!mounted) return;
        setState(() => _remoteVideoMuted[remoteUid] = muted);
      },
      onRemoteVideoStateChanged: (conn, remoteUid, state, reason, elapsed) {
        if (!mounted) return;
        final off = state == RemoteVideoState.remoteVideoStateStopped ||
            state == RemoteVideoState.remoteVideoStateFrozen;
        final on = state == RemoteVideoState.remoteVideoStateDecoding;
        if (!off && !on) return;
        setState(() => _remoteVideoMuted[remoteUid] = off);
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
        unawaited(_enableSpeakerHighlight());
        _purgeSelfFromRemoteTracking();
        // Audio engine often needs a nudge after a rejoin or the call stays
        // silent for both sides until something else wakes it.
        if (_connectedAt != null) _startTimer();
        unawaited(_renewTokenNow());
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
          unawaited(_renewTokenNow());
          _reassertAudio();
          _showOngoingCallNotification();
        } else if (state == ConnectionStateType.connectionStateFailed) {
          setState(() {
            _reconnecting = true;
            _status = 'Reconnecting…';
          });
          unawaited(_renewTokenNow());
        }
      },
      onTokenPrivilegeWillExpire: (conn, t) async {
        await _renewTokenNow();
      },
      onRequestToken: (conn) async {
        await _renewTokenNow();
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
        // Agora may emit a transient leave when the app is backgrounded while
        // audio is still live — only treat it as ended when we hung up.
        if (!_hangingUp && !_remoteClosed && _CallSession.connectedAt != null) {
          return;
        }
        setState(() {
          _joined = false;
          _status = 'Ended';
          _activeSpeakerUid = null;
        });
        _timer?.cancel();
        _audioHealthTimer?.cancel();
        _tokenRefreshTimer?.cancel();
      },
    ));
  }

  /// Server confirmed the callee joined (POST /join) — end the outbound ring.
  void _onCalleeAnsweredViaServer(String userId) {
    final me = ref.read(authStoreProvider).user;
    if (me != null && userId == me.id) return;
    final call = (_callMeta?['call'] as Map?)?.cast<String, dynamic>();
    final initiatorId = call?['initiatorId']?.toString();
    if (initiatorId != null && userId == initiatorId) return;
    if (!_isCallInitiator || _isMeeting) return;
    _cancelOutgoingRingTimeout();
    unawaited(_stopRingback());
    if (_connectedAt == null) _markRemoteConnected();
  }

  Future<void> _stopRingback() async {
    try {
      await _ringtone.stop();
      await _tonePlayer.stop();
    } catch (_) {}
  }

  void _cancelOutgoingRingTimeout() {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
  }

  void _startOutgoingRingTimeout() {
    if (_ringTimeoutTimer != null) return;
    if (!_isCallInitiator || _isMeeting || _remoteClosed) return;
    if (!_joined || _remoteUids.isNotEmpty) return;
    _ringTimeoutTimer = Timer(_kOutgoingRingTimeout, () {
      if (!mounted || _remoteClosed) return;
      if (!_isCallInitiator || _isMeeting) return;
      if (_connectedAt != null) return;
      unawaited(_handleNoAnswerTimeout());
    });
  }

  Future<void> _handleNoAnswerTimeout() async {
    if (_remoteClosed) return;
    _remoteClosed = true;
    _cancelOutgoingRingTimeout();
    await _stopRingback();
    await _teardown(notifyServer: true);
    if (!mounted) return;
    bestieToast(
      context,
      'No answer',
      body: 'The call was not picked up.',
      kind: BestieToastKind.info,
    );
    context.go('/chat');
  }

  Future<void> _playRingback() async {
    if (!_isCallInitiator || _isMeeting) return;
    try {
      await _stopRingback();
      final url = _ringingSoundUrl;
      await _tonePlayer.setAudioContext(_ringbackAudioContext(_route));
      await _tonePlayer.setReleaseMode(ReleaseMode.loop);
      final ringVolume = switch (_route) {
        CallAudioRoute.speaker => 1.0,
        CallAudioRoute.bluetooth => 0.95,
        CallAudioRoute.earpiece => 0.75,
      };
      if (url != null && url.isNotEmpty) {
        await _tonePlayer.play(UrlSource(url), volume: ringVolume);
        _startOutgoingRingTimeout();
        return;
      }
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await _tonePlayer.play(
          BytesSource(AppSounds.desktopRingtoneBytes()),
          volume: ringVolume,
        );
        _startOutgoingRingTimeout();
        return;
      }
      // Custom URL absent: earpiece uses the system ringtone stream; speaker /
      // Bluetooth need a different stream or Agora hijacks the session.
      if (_route == CallAudioRoute.earpiece) {
        await _ringtone.play(
          android: AndroidSounds.ringtone,
          ios: IosSounds.electronic,
          looping: true,
          volume: ringVolume,
          asAlarm: false,
        );
      } else {
        await _ringtone.play(
          android: AndroidSounds.ringtone,
          ios: IosSounds.electronic,
          looping: true,
          volume: ringVolume,
          asAlarm: true,
        );
      }
      _startOutgoingRingTimeout();
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

  Future<void> _playEmergencyBuzzer(String? fromName,
      [String? eventAudioUrl]) async {
    try {
      final url =
          eventAudioUrl?.isNotEmpty == true ? eventAudioUrl : _buzzerSoundUrl;
      if (url != null && url.isNotEmpty) {
        await _tonePlayer.setReleaseMode(ReleaseMode.release);
        await _tonePlayer.play(UrlSource(url), volume: 1);
      } else {
        await _ringtone.play(
          android: AndroidSounds.alarm,
          ios: IosSounds.alarm,
          looping: false,
          volume: 1.0,
          asAlarm: true,
        );
      }
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
    if (_held) return;
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.enableAudio();
      await engine.muteAllRemoteAudioStreams(false);
      for (final uid in _remoteUids) {
        try {
          await engine.muteRemoteAudioStream(uid: uid, mute: false);
        } catch (_) {}
      }
      if (_muted) {
        await engine.muteLocalAudioStream(true);
      } else {
        await engine.enableLocalAudio(true);
        await engine.muteLocalAudioStream(false);
      }
      await _applyAudioRoute(_route);
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
        if (mounted) setState(() => _error = null);
        _callMeta = _CallSession.callMeta;
        if (_callMeta == null && _CallSession.joined) {
          try {
            _callMeta = await _fetchToken();
            _CallSession.callMeta = _callMeta;
          } catch (e) {
            if (_isCallEndedError(e)) {
              await _teardown(notifyServer: false);
              if (mounted) context.go('/chat');
              return;
            }
            // Token refresh is optional when the live engine is already up.
          }
        }
        _syncParticipantsFromCallMeta();
        _registerHandlers(_CallSession.engine!);
        unawaited(_enableSpeakerHighlight());
        _purgeSelfFromRemoteTracking();
        _restoreLiveCallUi();
        setState(() {
          if (_CallSession.connectedAt != null && _CallSession.engine != null) {
            _joined = true;
          } else {
            _joined = _CallSession.joined;
          }
        });
        _syncRemotePeerSnapshot();
        _publishActiveCallState();
        _startAudioHealthCheck();
        _startTokenRefresh();
        _reassertAudio();
        _showOngoingCallNotification();
        _CallSession.startAudioRouteKeepAlive();
        if (!_isVideo) unawaited(_startProximityIfVoice());
      } catch (e) {
        if (!mounted) return;
        if (_isCallEndedError(e)) {
          await _teardown(notifyServer: false);
          if (mounted) context.go('/chat');
          return;
        }
        setState(() {
          _error = formatApiError(e);
          _status = 'Failed';
        });
      } finally {
        _booting = false;
      }
      return;
    }
    // New or different call — always wipe stale session maps / bubble state.
    await _CallSession.teardown();
    ActiveCallState.clear();
    _CallSession.onCallScreen = true;
    _videoEnabled = _routeWantsVideo;
    _route = _routeWantsVideo ? CallAudioRoute.speaker : CallAudioRoute.earpiece;
    _CallSession._ping();

    // Track which step is in flight so the error message can identify the
    // exact failing call (-3 with a null message is otherwise opaque).
    String step = 'start';
    try {
      // 1. OS-level permissions.
      step = 'permissions';
      final desktopRuntime =
          Platform.isWindows || Platform.isLinux || Platform.isMacOS;
      if (!desktopRuntime) {
        final perms = <Permission>[Permission.microphone];
        if (_routeWantsVideo) perms.add(Permission.camera);
        // Android 12+ needs runtime BLUETOOTH_CONNECT to route call audio to a
        // Bluetooth headset. Requested best-effort - not fatal if denied.
        if (Platform.isAndroid) perms.add(Permission.bluetoothConnect);
        final granted = await perms.request();
        final mic = granted[Permission.microphone];
        if (mic != PermissionStatus.granted &&
            mic != PermissionStatus.limited) {
          throw 'Microphone permission denied. Open Settings -> Apps -> MyTaskKing -> Permissions and enable it.';
        }
        if (_routeWantsVideo) {
          final cam = granted[Permission.camera];
          if (cam != PermissionStatus.granted &&
              cam != PermissionStatus.limited) {
            throw 'Camera permission denied. Open Settings -> Apps -> MyTaskKing -> Permissions and enable it.';
          }
        }
      }

      // 2. Re-register on the server when returning to an ACTIVE call (clears
      // leftAt from a prior hang-up) before we fetch an Agora token.
      if (widget.callId != null) {
        step = 'server-join';
        try {
          final joined = await ref.read(apiProvider).joinCall(widget.callId!);
          _callMeta = {'call': joined};
          _CallSession.callMeta = _callMeta;
          _syncParticipantsFromCallMeta();
        } catch (e) {
          if (_isCallEndedError(e)) rethrow;
          // Outgoing first connect — token fetch still works without this.
        }
      }

      // 3. Fetch token + appId from the backend.
      step = 'token-fetch';
      setState(() => _status = _isMeeting ? 'Joining…' : 'Calling…');
      final tokenResp = await _fetchToken();
      _callMeta = tokenResp;
      _CallSession.callMeta = tokenResp;
      _videoEnabled = _routeWantsVideo;
      _syncParticipantsFromCallMeta();
      try {
        final settings =
            await ref.read(apiProvider).settingsScope(scope: 'calls');
        final calls = (settings['calls'] as Map?)?.cast<String, dynamic>();
        _headOfficeName = (calls?['headOfficeName'] ?? 'HQ India').toString();
        _ringingSoundUrl = calls?['ringingSoundUrl']?.toString();
        _buzzerSoundUrl = calls?['emergencyBuzzerSoundUrl']?.toString();
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
      final displayTitle = _callDisplayTitle();
      ActiveCallState.start(
        callId: widget.callId,
        meetingSlug: widget.meetingSlug,
        mode: widget.mode,
        title: widget.meetingSlug != null
            ? 'Meeting'
            : (displayTitle != 'Connecting…' && displayTitle != 'In call'
                ? displayTitle
                : 'Call'),
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
      await _enableSpeakerHighlight();

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
        await engine.adjustPlaybackSignalVolume(140);
        await engine.adjustRecordingSignalVolume(120);
      } catch (_) {/* non-critical tuning */}

      if (_routeWantsVideo) {
        step = 'enable-video';
        await engine.enableVideo();

        step = 'start-preview';
        await engine.startPreview();
      } else {
        // Voice calls still need the video module so screen-share tracks
        // can be published and received (camera stays off).
        try {
          await engine.enableVideo();
        } catch (_) {}
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
      final me = ref.read(authStoreProvider).user;
      if (me != null) _agoraUidToUserId[uid] = me.id;
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
      } catch (_) {/* non-critical */}

      if (widget.callId != null) {
        try {
          // Tell the server our real per-device uid so it broadcasts the right
          // uid→name mapping to the other participants' tiles.
          final joined = await ref
              .read(apiProvider)
              .post('/calls/${widget.callId}/join', body: {'agoraUid': uid});
          _callMeta = {...?_callMeta, 'call': joined};
          _syncParticipantsFromCallMeta();
          _purgeSelfFromRemoteTracking();
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
      if (_isCallEndedError(e)) {
        await _teardown(notifyServer: false);
        if (mounted) context.go('/chat');
        return;
      }
      setState(() {
        _error = formatApiError(e);
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

  bool _isCallEndedError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 404) return true;
      if (code == 400) {
        final msg = formatApiError(e).toLowerCase();
        return msg.contains('ended') || msg.contains('not available');
      }
    }
    return false;
  }

  static const _activeCallLabelStyle = TextStyle(
    color: CallScreenUiColors.neonGreen,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.5,
  );

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
    final engine = _engine;
    if (!_isVideo || engine == null) return;
    if (_cameraOff) {
      if (mounted) {
        bestieToast(
          context,
          'Turn on camera first',
          kind: BestieToastKind.info,
        );
      }
      return;
    }
    try {
      await engine.switchCamera();
      _frontCamera = !_frontCamera;
    } catch (_) {
      try {
        _frontCamera = !_frontCamera;
        await engine.setCameraCapturerConfiguration(
          CameraCapturerConfiguration(
            cameraDirection: _frontCamera
                ? CameraDirection.cameraFront
                : CameraDirection.cameraRear,
          ),
        );
      } catch (e) {
        if (mounted) {
          bestieToast(
            context,
            'Could not switch camera',
            body: formatApiError(e),
            kind: BestieToastKind.error,
          );
        }
      }
    }
  }

  /// Cycle earpiece → speaker → bluetooth → earpiece.
  Future<void> _cycleAudioRoute() async {
    final next = switch (_route) {
      CallAudioRoute.earpiece => CallAudioRoute.speaker,
      CallAudioRoute.speaker => CallAudioRoute.bluetooth,
      CallAudioRoute.bluetooth => CallAudioRoute.earpiece,
    };
    if (mounted) {
      setState(() => _route = next);
    } else {
      _route = next;
    }
    await _applyAudioRoute(next);
    if (mounted) {
      bestieToast(context, _audioRouteLabel(next), kind: BestieToastKind.info);
    }
  }

  Future<void> _setAudioRoute(CallAudioRoute route) async {
    final next = _route == route ? CallAudioRoute.earpiece : route;
    if (mounted) {
      setState(() => _route = next);
    } else {
      _route = next;
    }
    await _applyAudioRoute(next);
    if (mounted) {
      bestieToast(
        context,
        _audioRouteLabel(next),
        kind: BestieToastKind.info,
      );
    }
  }

  Future<void> _toggleSpeakerRoute() async {
    final next = _route == CallAudioRoute.speaker
        ? CallAudioRoute.earpiece
        : CallAudioRoute.speaker;
    if (mounted) {
      setState(() => _route = next);
    } else {
      _route = next;
    }
    await _applyAudioRoute(next);
    if (mounted) {
      bestieToast(
        context,
        _audioRouteLabel(next),
        kind: BestieToastKind.info,
      );
    }
  }

  Future<void> _toggleBluetoothRoute() async {
    final next = _route == CallAudioRoute.bluetooth
        ? CallAudioRoute.earpiece
        : CallAudioRoute.bluetooth;
    if (mounted) {
      setState(() => _route = next);
    } else {
      _route = next;
    }
    await _applyAudioRoute(next);
    if (mounted) {
      bestieToast(
        context,
        _audioRouteLabel(next),
        kind: BestieToastKind.info,
      );
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

  AudioContext _ringbackAudioContext(CallAudioRoute route) {
    final audioRoute = switch (route) {
      CallAudioRoute.earpiece => AudioContextConfigRoute.earpiece,
      CallAudioRoute.speaker => AudioContextConfigRoute.speaker,
      CallAudioRoute.bluetooth => AudioContextConfigRoute.system,
    };
    return AudioContextConfig(
      route: audioRoute,
      focus: AudioContextConfigFocus.mixWithOthers,
      stayAwake: true,
    ).build();
  }

  Future<void> _applyAudioRoute(CallAudioRoute r) async {
    // While still ringing, only move the ringback tone — touching Agora's
    // speakerphone route here steals the audio session and mutes ringback.
    if (_waitingForAnswer) {
      await _restartRingbackForRouteChange();
      return;
    }

    final engine = _engine;
    if (engine == null) return;
    final speaker = r == CallAudioRoute.speaker;
    try {
      await engine.setDefaultAudioRouteToSpeakerphone(speaker);
    } catch (_) {}
    try {
      await engine.setEnableSpeakerphone(speaker);
    } catch (_) {}
    try {
      // Speaker mode needs a stronger playback gain so the call is clearly audible.
      await engine.adjustPlaybackSignalVolume(speaker ? 255 : 160);
    } catch (_) {}
  }

  Future<void> _restartRingbackForRouteChange() async {
    try {
      await _ringtone.stop();
      await _tonePlayer.stop();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted ||
          !_joined ||
          _remoteUids.isNotEmpty ||
          _isMeeting ||
          _remoteClosed) {
        return;
      }
      if (!_isCallInitiator) return;
      await _playRingback();
    } catch (_) {}
  }

  Future<void> _toggleShare() async {
    if (_engine == null) return;
    if (!_joined) {
      if (mounted) {
        bestieToast(
          context,
          'Not connected yet',
          body: 'Screen share is available once the call is connected.',
          kind: BestieToastKind.info,
        );
      }
      return;
    }
    try {
      if (_sharing) {
        await _engine!.stopScreenCapture();
        await _engine!.updateChannelMediaOptions(ChannelMediaOptions(
          publishScreenCaptureVideo: false,
          publishScreenCaptureAudio: false,
          publishScreenTrack: false,
          publishCameraTrack: _isVideo && !_cameraOff,
        ));
        setState(() => _sharing = false);
        _emitScreenShareState(active: false);
        if (mounted) {
          bestieToast(context, 'Screen share stopped',
              kind: BestieToastKind.info);
        }
      } else {
        // Let Agora own the Android media-projection flow — starting our own
        // foreground service first was crashing the app on Android 14+.
        for (final scenario in [
          ScreenScenarioType.screenScenarioVideo,
          ScreenScenarioType.screenScenarioGaming,
        ]) {
          try {
            await _engine!.setScreenCaptureScenario(scenario);
            break;
          } catch (_) {}
        }
        try {
          await _engine!.enableVideo();
        } catch (_) {}
        await _engine!.startScreenCapture(
          const ScreenCaptureParameters2(
            captureVideo: true,
            captureAudio: false,
          ),
        );
        await _engine!.updateChannelMediaOptions(ChannelMediaOptions(
          publishScreenCaptureVideo: true,
          publishScreenCaptureAudio: false,
          publishScreenTrack: true,
          publishCameraTrack: _isVideo && !_cameraOff,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          autoSubscribeVideo: true,
        ));
        // Android sometimes needs a second nudge after projection starts.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        try {
          await _engine!.updateChannelMediaOptions(ChannelMediaOptions(
            publishScreenCaptureVideo: true,
            publishScreenCaptureAudio: false,
            publishScreenTrack: true,
            publishCameraTrack: _isVideo && !_cameraOff,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            autoSubscribeVideo: true,
          ));
        } catch (_) {}
        setState(() => _sharing = true);
        _emitScreenShareState(active: true);
        // Re-notify after publish settles — covers peers who connected via
        // Agora just before our first fan-out.
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (!mounted || !_sharing) return;
          _emitScreenShareState(active: true);
        });
        if (mounted) {
          bestieToast(context, 'Sharing your screen',
              kind: BestieToastKind.success);
        }
      }
    } catch (e) {
      setState(() => _sharing = false);
      _emitScreenShareState(active: false);
      try {
        await _engine?.stopScreenCapture();
      } catch (_) {}
      if (mounted) {
        bestieToast(context, 'Screen share not available',
            body: formatApiError(e), kind: BestieToastKind.error);
      }
    }
  }

  void _toggleRaiseHand() {
    if (!_isMeeting) return;
    final me = ref.read(authStoreProvider).user;
    final meId = me?.id;
    if (meId == null) return;
    final next = !_handRaised;
    setState(() => _handRaised = next);
    _broadcastCallSignal({
      'type': 'raiseHand',
      'active': next,
      'fromUserId': meId,
      'userName': me?.name ?? 'Participant',
    });
    if (mounted) {
      bestieToast(
        context,
        next ? 'Hand raised' : 'Hand lowered',
        kind: BestieToastKind.info,
      );
    }
  }

  Future<void> _showDialPad() async {
    await showCallDialpadSheet(
      context,
      onDigit: (_) {
        // Local DTMF UX — tones are played via haptics in the sheet.
      },
    );
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

  void _showParticipants() => _showMembersSheet();

  Future<void> _showMembersSheet() async {
    await _refreshCallMeta();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Timer? tick;
            void scheduleTick() {
              tick?.cancel();
              final hasRinging = _participantsFromMeta().any(
                (p) => _memberConnection(p) == _CallMemberConnection.ringing,
              );
              if (hasRinging) {
                tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
                  if (ctx.mounted) setSheet(() {});
                });
              }
            }

            scheduleTick();

            final c = BestieColors.of(ctx);
            final me = ref.read(authStoreProvider).user;
            final parts = _participantsFromMeta();
            final connected = <Map<String, dynamic>>[];
            final ringing = <Map<String, dynamic>>[];
            final notConnected = <Map<String, dynamic>>[];

            for (final p in parts) {
              final uid = p['userId']?.toString();
              if (uid == me?.id) continue;
              switch (_memberConnection(p)) {
                case _CallMemberConnection.connected:
                  connected.add(p);
                case _CallMemberConnection.ringing:
                  ringing.add(p);
                case _CallMemberConnection.notConnected:
                  notConnected.add(p);
              }
            }

            return PopScope(
              onPopInvokedWithResult: (_, __) => tick?.cancel(),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.72,
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(BestieTokens.rXl),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 12),
                      decoration: BoxDecoration(
                        color: c.borderStrong,
                        borderRadius: BorderRadius.circular(BestieTokens.rPill),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${connected.length + 1} connected',
                          style: TextStyle(
                            color: c.textMuted,
                            fontSize: 13,
                            fontWeight: BestieTokens.fwSemibold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: BestieTokens.cSuccess.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_add_alt_1_rounded,
                            color: BestieTokens.cSuccess, size: 22),
                      ),
                      title: Text('Add people',
                          style: TextStyle(
                            color: c.text,
                            fontWeight: BestieTokens.fwSemibold,
                          )),
                      onTap: () {
                        tick?.cancel();
                        Navigator.of(ctx).pop();
                        _showInvite();
                      },
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                        children: [
                          if (me != null)
                            _membersRow(
                              c: c,
                              name: '${me.name} (You)',
                              avatarName: me.name,
                              imageUrl: me.avatarUrl,
                              trailing: const SizedBox.shrink(),
                            ),
                          for (final p in connected)
                            _membersRow(
                              c: c,
                              name: _participantProfileName(p),
                              avatarName: _participantProfileName(p),
                              imageUrl:
                                  (p['user'] as Map?)?['avatarUrl']?.toString(),
                              trailing: Icon(Icons.mic_rounded,
                                  size: 18, color: c.textMuted),
                            ),
                          if (ringing.isNotEmpty ||
                              notConnected.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                              child: Text(
                                'Not connected',
                                style: TextStyle(
                                  color: c.textMuted,
                                  fontSize: 13,
                                  fontWeight: BestieTokens.fwSemibold,
                                ),
                              ),
                            ),
                            for (final p in ringing)
                              _membersRow(
                                c: c,
                                name: _participantProfileName(p),
                                avatarName: _participantProfileName(p),
                                imageUrl: (p['user'] as Map?)?['avatarUrl']
                                    ?.toString(),
                                trailing: const _ConnectingDots(),
                              ),
                            for (final p in notConnected)
                              _membersRow(
                                c: c,
                                name: _participantProfileName(p),
                                avatarName: _participantProfileName(p),
                                imageUrl: (p['user'] as Map?)?['avatarUrl']
                                    ?.toString(),
                                trailing: IconButton(
                                  icon: Icon(
                                      Icons.notifications_active_outlined,
                                      color: c.text),
                                  tooltip: 'Ring again',
                                  onPressed: () async {
                                    final uid = p['userId']?.toString();
                                    if (uid == null) return;
                                    await _ringParticipantAgain(uid);
                                    if (ctx.mounted) setSheet(() {});
                                    scheduleTick();
                                  },
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _membersRow({
    required BestieColors c,
    required String name,
    required String avatarName,
    String? imageUrl,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          BestieAvatar(
            name: avatarName,
            imageUrl: imageUrl,
            isClient: false,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.text,
                fontWeight: BestieTokens.fwSemibold,
                fontSize: 15,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Future<void> _hangup() async {
    if (_hangingUp) return;
    _hangingUp = true;
    if (mounted) setState(() {});
    unawaited(_playCallEndedSound());
    if (mounted) context.go('/chat');
    await _teardown();
  }

  void _minimize() {
    _syncRemotePeerSnapshot();
    _publishActiveCallState();
    _CallSession.onCallScreen = false;
    _CallSession._ping();
    CallSession.notifyRevision();
    unawaited(_CallSession.reapplyAudioRoute());
    _showOngoingCallNotification();
    context.go('/chat');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final topInset = MediaQuery.of(context).padding.top;
    // WhatsApp-style: outgoing video shows your camera full-screen while ringing.
    final showingVideo =
        _isVideo && (_remoteUids.isNotEmpty || _waitingForAnswer);
    final screenShareActive = _sharing || _remoteScreenShareUid != null;
    final desktopVoiceStage =
        (Platform.isWindows || Platform.isLinux) && !_isVideo && !_isMeeting;
    final isPremiumOneToOneVoice = !_isVideo &&
        !_isMeeting &&
        !showingVideo &&
        (desktopVoiceStage ||
            (!_useWhatsAppParticipantGrid && _remoteUids.length <= 1));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _minimize();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (isPremiumOneToOneVoice)
              (screenShareActive
                  ? _premiumVoiceScreenShareBody()
                  : _exactPrototypeVoiceBody())
            else
              Stack(children: [
                // Depth backdrop — a soft vertical gradient so voice calls aren't a
                // flat black void (WhatsApp does the same). Hidden once real remote
                // video fills the screen.
                if (!showingVideo)
                  const Positioned.fill(child: _FuturisticCallBackdrop()),
                Positioned.fill(child: _remoteSurface()),

                // Top scrim for header legibility over video / screen share.
                if (showingVideo || screenShareActive)
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
                // Bottom scrim for control legibility over video / screen share.
                if (showingVideo || screenShareActive)
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

                // Self-view PiP once the other person joins (full-screen self while ringing).
                if (_isVideo &&
                    _joined &&
                    !_cameraOff &&
                    _remoteUids.isNotEmpty)
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

                Positioned(
                    top: topInset + 8, left: 8, right: 8, child: _header()),
                // Premium status chips — 1:1 voice only (hidden during screen share).
                if (!_isMeeting &&
                    !showingVideo &&
                    !screenShareActive &&
                    !_useWhatsAppParticipantGrid)
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
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
                if (_isMeeting && (_handRaised || _raisedHands.isNotEmpty))
                  Positioned(
                    top: topInset + 108,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(child: Center(child: _raisedHandsBanner())),
                  ),
                // Network trouble — compact pill for group calls; full banner for 1:1.
                if (_reconnecting && _error == null && _isLiveCallActive)
                  Positioned(
                    top: topInset +
                        (_useWhatsAppParticipantGrid
                            ? 52
                            : (_muteStatusText() == null ? 64 : 104)),
                    left: 16,
                    right: 16,
                    child: IgnorePointer(
                      child: _useWhatsAppParticipantGrid
                          ? Center(child: _compactReconnectBanner())
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFFB45309).withOpacity(0.95),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(
                                              Colors.white)),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Reconnecting… check your internet connection',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight:
                                                BestieTokens.fwSemibold),
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
            if (_proximityNear && !_isVideo)
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
          ],
        ),
      ),
    );
  }

  Widget _exactPrototypeVoiceBody() {
    final remoteName = _primaryRemoteDisplayName();
    final subtitle = _primaryRemoteSubtitle();
    final desktopLayout = Platform.isWindows || Platform.isLinux;
    final ending = _showEndingUi;
    final timerLine = ending
        ? 'Ending call…'
        : (_connectedAt != null ? _formatElapsed(_elapsed) : _status);
    final timerColor = ending
        ? CallScreenUiColors.textMuted
        : (_connectedAt != null
            ? CallScreenUiColors.neonGreen
            : _status.toLowerCase().contains('ring')
                ? const Color(0xFFFFB020)
                : CallScreenUiColors.textPrimary);
    final showReconnect =
        _reconnecting && _error == null && _isLiveCallActive;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = desktopLayout ||
            constraints.maxHeight < 760 ||
            constraints.maxWidth < 420;
        final avatarHeight = desktopLayout
            ? max(216.0, min(286.0, constraints.maxHeight * 0.34))
            : (compact ? 174.0 : 200.0);
        final contentGap = compact ? 4.0 : 10.0;
        final nameSize = compact ? 20.0 : 26.0;
        final subtitleSize = compact ? 12.0 : 14.0;
        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                CallScreenUiColors.backgroundTop,
                CallScreenUiColors.backgroundMid,
                CallScreenUiColors.backgroundBottom,
              ],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _callHeader(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _topChips(),
                ),
                if (showReconnect) ...[
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _PrototypeReconnectBanner(),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  timerLine,
                  style: TextStyle(
                    color: timerColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                SizedBox(height: contentGap),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        desktopLayout
                            ? _DesktopMeshAvatarStage(
                                name: remoteName,
                                imageUrl: _primaryRemoteAvatarUrl(),
                                connected: _connectedAt != null && !ending,
                                height: avatarHeight,
                                companions:
                                    _desktopCompanionProfiles(remoteName),
                              )
                            : _CallUiAvatarStage(
                                name: remoteName,
                                imageUrl: _primaryRemoteAvatarUrl(),
                                connected: _connectedAt != null && !ending,
                                height: avatarHeight,
                                companions: const [],
                              ),
                        SizedBox(height: compact ? 2 : 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              if (!ending)
                                const Text(
                                  'Active call',
                                  style: _activeCallLabelStyle,
                                ),
                              if (!ending) const SizedBox(height: 3),
                              Text(
                                remoteName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: CallScreenUiColors.textPrimary,
                                  fontSize: nameSize,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (subtitle != null && subtitle.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: CallScreenUiColors.textSecondary,
                                    fontSize: subtitleSize,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 3),
                              Text(
                                _headOfficeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: CallScreenUiColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    desktopLayout ? 10 : 18,
                    0,
                    desktopLayout ? 10 : 18,
                    desktopLayout ? 6 : 8,
                  ),
                  child: desktopLayout
                      ? _desktopPremiumCallFooter()
                      : _premiumCallControlsCore(compact: compact),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Premium 1:1 voice layout while screen sharing — same column structure as
  /// [_exactPrototypeVoiceBody] so controls/header don't stack on top of video.
  Widget _premiumVoiceScreenShareBody() {
    final desktopLayout = Platform.isWindows || Platform.isLinux;
    if (desktopLayout) return _desktopVoiceScreenShareBody();

    final isLocal = _sharing;
    final remoteUid = _remoteScreenShareUid;
    final shareLabel = isLocal
        ? 'You are sharing your screen'
        : '${_remoteNames[remoteUid] ?? _primaryRemoteDisplayName()} is sharing their screen';
    final ending = _showEndingUi;
    final timerLine = ending
        ? 'Ending call…'
        : (_connectedAt != null ? _formatElapsed(_elapsed) : _status);
    final timerColor = ending
        ? CallScreenUiColors.textMuted
        : (_connectedAt != null
            ? CallScreenUiColors.neonGreen
            : _status.toLowerCase().contains('ring')
                ? const Color(0xFFFFB020)
                : CallScreenUiColors.textPrimary);
    final showReconnect =
        _reconnecting && _error == null && _isLiveCallActive;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                CallScreenUiColors.backgroundTop,
                CallScreenUiColors.backgroundMid,
                CallScreenUiColors.backgroundBottom,
              ],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _callHeader(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.screen_share_rounded,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            shareLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (showReconnect) ...[
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _PrototypeReconnectBanner(),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  timerLine,
                  style: TextStyle(
                    color: timerColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          border: Border.all(color: Colors.white12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _screenShareVideo(),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: _premiumCallControlsCore(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Windows/Linux voice call during screen share — compact preview, no profile
  /// block, same fixed-size footer buttons as the normal desktop call UI.
  Widget _desktopVoiceScreenShareBody() {
    final isLocal = _sharing;
    final remoteUid = _remoteScreenShareUid;
    final shareLabel = isLocal
        ? 'You are sharing your screen'
        : '${_remoteNames[remoteUid] ?? _primaryRemoteDisplayName()} is sharing';
    final ending = _hangingUp || !_joined;
    final timerLine = ending
        ? 'Ending call…'
        : (_connectedAt != null ? _formatElapsed(_elapsed) : _status);
    final timerColor = ending
        ? CallScreenUiColors.textMuted
        : (_connectedAt != null
            ? CallScreenUiColors.neonGreen
            : _status.toLowerCase().contains('ring')
                ? const Color(0xFFFFB020)
                : CallScreenUiColors.textPrimary);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                CallScreenUiColors.backgroundTop,
                CallScreenUiColors.backgroundMid,
                CallScreenUiColors.backgroundBottom,
              ],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _callHeader(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.screen_share_rounded,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            shareLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  timerLine,
                  style: TextStyle(
                    color: timerColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: min(360.0, constraints.maxWidth - 48),
                      height: min(200.0, constraints.maxHeight * 0.28),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A1628),
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: _screenShareVideo(),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                  child: _desktopPremiumCallFooter(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _prototypeMuteBanner(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(
              Icons.mic_off_rounded,
              color: Color(0xFFFBBF24),
              size: 15,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                text,
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
    );
  }

  bool get _isMeeting => widget.meetingSlug != null;

  String? _muteStatusText() {
    final labels = <String>[];
    if (_held) labels.add('On hold');
    if (_muted) labels.add('You are muted');
    for (final entry in _remoteMuted.entries) {
      if (!entry.value) continue;
      // Drop stale mute flags from participants no longer in the channel.
      if (!_remoteUids.contains(entry.key)) continue;
      final mapped = _agoraUidToUserId[entry.key];
      final announced = _remoteNames[entry.key]?.trim();
      final joined =
          mapped != null ? _joinedParticipants[mapped]?.trim() : null;
      final label = (announced != null &&
              announced.isNotEmpty &&
              announced != 'Participant')
          ? announced
          : (joined != null && joined.isNotEmpty ? joined : null);
      if (label == null) continue;
      labels.add('$label is muted');
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

  Widget _callThemeToggleButton() {
    return Consumer(
      builder: (context, ref, _) {
        final light = ref.watch(callScreenLightControlsProvider);
        return _callHeaderGlassButton(
          icon: light ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          tooltip: light ? 'Dark mode' : 'Light mode',
          onTap: () {
            ref.read(callScreenLightControlsProvider.notifier).state = !light;
          },
        );
      },
    );
  }

  Widget _callHeaderGlassButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: CallUiGlassContainer(
            borderRadius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: SizedBox(
              width: 34,
              height: 18,
              child: Center(
                child: Icon(
                  icon,
                  color: CallScreenUiColors.textPrimary,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _callHeaderParticipantsButton() {
    final count = _participantCount;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showParticipants,
        borderRadius: BorderRadius.circular(12),
        child: CallUiGlassContainer(
          borderRadius: 12,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.group_outlined,
                color: CallScreenUiColors.textPrimary,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: const TextStyle(
                  color: CallScreenUiColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
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
      if (p['userId']?.toString() == me?.id) continue;
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
    final title = _primaryRemoteDisplayName();
    // Voice calls use the premium center stage (name + timer there), so the
    // header is minimal: minimize · verified MyTaskKing brand · invite. Video
    // calls keep the name + timer in the header (no center stage over video).
    final showingVideo = _isVideo && _remoteUids.isNotEmpty;
    if (!showingVideo) {
      if (_useWhatsAppParticipantGrid) {
        final names = _callDisplayTitle();
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(children: [
            _circleHeaderIcon(Icons.keyboard_arrow_down_rounded, _minimize,
                tooltip: 'Minimize'),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(names,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: BestieTokens.fwBold,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      _connectedAt == null ? _status : _formatElapsed(_elapsed),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ]),
            ),
            _callThemeToggleButton(),
            const SizedBox(width: 4),
            _circleHeaderIcon(Icons.person_add_alt_1_rounded, _showInvite,
                tooltip: 'Add participant'),
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(children: [
          _callHeaderGlassButton(
            icon: Icons.keyboard_arrow_down_rounded,
            onTap: _minimize,
          ),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(mainAxisSize: MainAxisSize.min, children: [
                    CallUiBrandLogo(size: 34),
                    SizedBox(width: 6),
                    Text('MyTaskKing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CallScreenUiColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        )),
                    SizedBox(width: 5),
                    Icon(Icons.verified_rounded,
                        color: CallScreenUiColors.verifiedBlue, size: 16),
                  ]),
                ]),
          ),
          _callThemeToggleButton(),
          const SizedBox(width: 8),
          _callHeaderParticipantsButton(),
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
        _callThemeToggleButton(),
        const SizedBox(width: 4),
        _circleHeaderIcon(Icons.person_add_alt_1_rounded, _showInvite,
            tooltip: 'Invite'),
      ]),
    );
  }

  /// Google Meet–style: meeting name + e2e/time on the left, participants chip
  /// on the right (taps to open the participants sheet).
  Widget _meetingHeader() {
    final title = _channelName ?? 'Meeting';
    final count = _participantCount;
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
        _callThemeToggleButton(),
        const SizedBox(width: 6),
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
    Set<String> alreadyInCall,
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
          final inCall = alreadyInCall.contains(id);
          final picked = selected.contains(id);
          return CheckboxListTile(
            value: inCall ? true : picked,
            onChanged: inCall
                ? null
                : (_) => set(() {
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
                    color: inCall ? c.textMuted : c.text,
                    fontWeight: BestieTokens.fwSemibold)),
            subtitle: Text(
                inCall
                    ? 'Already in call'
                    : (u['customTitle'] ?? u['role'] ?? '')
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
          final alreadyInCall = _userIdsInCall();
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
                                        alreadyInCall,
                                        set),
                                    ..._inviteSection(ctx, c, 'Clients',
                                        clients, selected, alreadyInCall, set),
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
                                  _markInvited(selected);
                                  await _refreshCallMeta();
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

  Widget _screenShareVideo() {
    final engine = _engine;
    if (engine == null) {
      return const Center(
        child: Text(
          'Connecting to shared screen…',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    final isLocal = _sharing;
    final remoteUid = _remoteScreenShareUid;
    const screenSource = VideoSourceType.videoSourceScreenPrimary;

    if (isLocal) {
      // Local screen-capture preview is often blank on desktop/Android — show
      // status instead of an empty black panel while others see the real share.
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        return Container(
          color: Colors.black.withValues(alpha: 0.28),
          alignment: Alignment.center,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.screen_share_rounded, size: 36, color: Colors.white54),
              SizedBox(height: 8),
              Text(
                'Your screen is being shared',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Others can see your display',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        );
      }
      return Container(
        color: Colors.black.withValues(alpha: 0.28),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.screen_share_rounded, size: 44, color: Colors.white54),
            SizedBox(height: 10),
            Text(
              'Your screen is being shared',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Others can see your display',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (remoteUid != null) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: engine,
          canvas: VideoCanvas(
            uid: remoteUid,
            sourceType: screenSource,
            renderMode: RenderModeType.renderModeFit,
          ),
          connection: RtcConnection(channelId: _channelName ?? ''),
        ),
      );
    }
    return const Center(
      child: Text(
        'Connecting to shared screen…',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _screenShareSurface() {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final isLocal = _sharing;
    final remoteUid = _remoteScreenShareUid;
    final label = isLocal
        ? 'You are sharing your screen'
        : '${_remoteNames[remoteUid] ?? 'Participant'} is sharing their screen';

    return Stack(
      fit: StackFit.expand,
      children: [
        _screenShareVideo(),
        Positioned(
          top: topInset + 56,
          left: 16,
          right: 16,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.screen_share_rounded,
                      color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_useWhatsAppParticipantGrid)
          Positioned(
            left: 8,
            right: 8,
            bottom: bottomInset + 112,
            height: 120,
            child: Opacity(
              opacity: 0.92,
              child: _whatsappParticipantGrid(),
            ),
          ),
      ],
    );
  }

  Widget _remoteSurface() {
    if (_sharing || _remoteScreenShareUid != null) {
      return _screenShareSurface();
    }
    if (_error != null && !(_joined && _engine != null)) {
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
        return Padding(
          padding: EdgeInsets.fromLTRB(
              6, 96, 6, 108 + MediaQuery.paddingOf(context).bottom),
          child: Column(children: [
            Expanded(child: _whatsappParticipantGrid()),
            const SizedBox(height: 10),
            _participantsStrip(showTimer: false),
            const SizedBox(height: 8),
            Text(_connectedAt == null ? _status : _formatElapsed(_elapsed),
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ]),
        );
      }
      // Calls with more than one remote stream (e.g. the same account joined
      // from two devices, or a group call) → show a tile per participant so
      // every joined device gets its own icon.
      if (_useWhatsAppParticipantGrid || _remoteUids.length > 1) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            6,
            MediaQuery.paddingOf(context).top + 56,
            6,
            108 + MediaQuery.paddingOf(context).bottom,
          ),
          child: SizedBox.expand(child: _whatsappParticipantGrid()),
        );
      }
      // 1:1 call: premium voice stage — waveform-ringed avatar + name +
      // designation + ACTIVE CALL + timer, all centered.
      return _voiceCallStage(_primaryRemoteDisplayName());
    }
    // Video meetings: tile grid shows avatars whenever a camera is off.
    if (_isMeeting) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          6,
          MediaQuery.paddingOf(context).top + 88,
          6,
          108 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          children: [
            Expanded(child: _whatsappParticipantGrid(forVideo: true)),
            const SizedBox(height: 8),
            _participantsStrip(showTimer: false),
          ],
        ),
      );
    }
    if (_remoteUids.isEmpty) {
      // Outgoing / waiting: show local camera full-screen (WhatsApp-style).
      if (_isVideo && _engine != null && _joined && !_cameraOff) {
        return Stack(
          fit: StackFit.expand,
          children: [
            AgoraVideoView(
              controller: VideoViewController(
                rtcEngine: _engine!,
                canvas: const VideoCanvas(uid: 0),
              ),
            ),
            if (_waitingForAnswer)
              Positioned(
                left: 24,
                right: 24,
                bottom: MediaQuery.paddingOf(context).bottom + 324,
                child: IgnorePointer(
                  child: _VideoRingingIdentity(
                    name: _primaryRemoteDisplayName(),
                    subtitle: _primaryRemoteSubtitle(),
                    headOffice: _headOfficeName,
                    status: _status,
                  ),
                ),
              ),
          ],
        );
      }
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
    if (_remoteUids.length > 1) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
            6, 88, 6, 108 + MediaQuery.paddingOf(context).bottom),
        child: _whatsappParticipantGrid(forVideo: true),
      );
    }
    // Re-check — remotes can drop between Agora events and the next frame.
    final remotes = _remoteUids.toList(growable: false);
    final engine = _engine;
    if (remotes.isEmpty || engine == null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.videocam_outlined, color: Colors.white38, size: 46),
          const SizedBox(height: 22),
          Text(_joined ? 'Waiting for others to join…' : _status,
              style: const TextStyle(color: Colors.white70, fontSize: 15)),
        ]),
      );
    }
    final firstRemote = remotes.first;
    final remoteVideoOff = _remoteVideoMuted[firstRemote] ?? false;
    if (remoteVideoOff) {
      return _voiceCallStage(
        _remoteNames[firstRemote] ?? _primaryRemoteDisplayName(),
      );
    }
    return Stack(children: [
      Positioned.fill(
        child: AgoraVideoView(
            controller: VideoViewController.remote(
          rtcEngine: engine,
          canvas: VideoCanvas(uid: firstRemote),
          connection: RtcConnection(channelId: _channelName ?? ''),
        )),
      ),
    ]);
  }

  Widget _raisedHandsBanner() {
    final names = <String>[];
    if (_handRaised) {
      names.add('You');
    }
    for (final entry in _raisedHands.entries) {
      names.add(entry.value);
    }
    if (names.isEmpty) return const SizedBox.shrink();
    final label = names.length == 1
        ? '${names.first} raised a hand'
        : '${names.length} raised hands';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.front_hand_rounded, color: Color(0xFFFBBF24), size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _participantsStrip({bool showTimer = true}) {
    // Prefer stable joined people (userId → name). Never show raw Agora
    // "Participant" placeholders from unmapped UIDs.
    final me = ref.read(authStoreProvider).user;
    final names = <String>[];
    for (final entry in _joinedParticipants.entries) {
      if (entry.key == me?.id) continue;
      final n = entry.value.trim();
      if (n.isNotEmpty) names.add(n);
    }
    if (names.isEmpty) {
      for (final uid in _remoteUids) {
        final mapped = _agoraUidToUserId[uid];
        if (mapped != null && mapped == me?.id) continue;
        final n = _remoteNames[uid]?.trim();
        if (n != null && n.isNotEmpty && n != 'Participant') names.add(n);
      }
    }
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

  String? _avatarUrlForUserId(String? userId) {
    if (userId == null) return null;
    final parts = (_callMeta?['call']?['participants'] as List?) ??
        (_callMeta?['participants'] as List?) ??
        const [];
    for (final p in parts) {
      if (p is! Map || p['userId'] != userId) continue;
      final user = (p['user'] as Map?)?.cast<String, dynamic>();
      final url = user?['avatarUrl']?.toString();
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  List<
      ({
        String name,
        String? userId,
        String? imageUrl,
        int? agoraUid,
        bool isLocal,
        bool muted,
        bool videoMuted
      })> _participantTilesForGrid() {
    _purgeSelfFromRemoteTracking();
    final me = ref.read(authStoreProvider).user;
    final tiles = <({
      String name,
      String? userId,
      String? imageUrl,
      int? agoraUid,
      bool isLocal,
      bool muted,
      bool videoMuted,
    })>[
      (
        name: me?.name ?? 'You',
        userId: me?.id,
        imageUrl: me?.avatarUrl,
        agoraUid: _CallSession.myUid ?? 0,
        isLocal: true,
        muted: _muted,
        videoMuted: _cameraOff,
      ),
    ];
    final seen = <String>{if (me?.id != null) me!.id};
    for (final entry in _joinedParticipants.entries) {
      if (entry.key == me?.id || seen.contains(entry.key)) continue;
      seen.add(entry.key);
      final uid = _agoraUidForUserId(entry.key);
      tiles.add((
        name: entry.value,
        userId: entry.key,
        imageUrl: _avatarUrlForUserId(entry.key),
        agoraUid: uid,
        isLocal: false,
        muted: uid != null ? (_remoteMuted[uid] ?? false) : false,
        videoMuted: uid != null ? (_remoteVideoMuted[uid] ?? false) : false,
      ));
    }
    // Only attach live Agora streams that map to a known person.
    // Never create ghost tiles labeled "Participant" for unmapped UIDs.
    for (final uid in _remoteUids) {
      if (uid == _CallSession.myUid) continue;
      final mappedUserId = _agoraUidToUserId[uid];
      if (mappedUserId == null || mappedUserId.isEmpty) continue;
      if (mappedUserId == me?.id) continue;

      final announced = _remoteNames[uid]?.trim();
      final joined = _joinedParticipants[mappedUserId]?.trim();
      final displayName = (announced != null &&
              announced.isNotEmpty &&
              announced != 'Participant')
          ? announced
          : (joined != null && joined.isNotEmpty ? joined : null);
      if (displayName == null) continue;

      final existing =
          tiles.indexWhere((t) => !t.isLocal && t.userId == mappedUserId);
      if (existing >= 0) {
        final t = tiles[existing];
        tiles[existing] = (
          name: t.name.isNotEmpty && t.name != 'Participant'
              ? t.name
              : displayName,
          userId: mappedUserId,
          imageUrl: t.imageUrl ?? _avatarUrlForUserId(mappedUserId),
          agoraUid: uid,
          isLocal: false,
          muted: _remoteMuted[uid] ?? false,
          videoMuted: _remoteVideoMuted[uid] ?? false,
        );
      } else if (!seen.contains(mappedUserId)) {
        seen.add(mappedUserId);
        tiles.add((
          name: displayName,
          userId: mappedUserId,
          imageUrl: _avatarUrlForUserId(mappedUserId),
          agoraUid: uid,
          isLocal: false,
          muted: _remoteMuted[uid] ?? false,
          videoMuted: _remoteVideoMuted[uid] ?? false,
        ));
      }
    }
    return tiles;
  }

  Widget _whatsappParticipantGrid({bool forVideo = false}) {
    final tiles = _participantTilesForGrid();
    final n = tiles.length;
    if (n == 0) return const SizedBox.shrink();
    const gap = 6.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        Widget tileAt(int index, {double? height, double? width}) {
          final t = tiles[index];
          return _whatsappParticipantTile(
            name: t.isLocal ? 'You' : t.name,
            imageUrl: t.imageUrl,
            agoraUid: t.agoraUid,
            isLocal: t.isLocal,
            muted: t.muted,
            videoMuted: t.videoMuted,
            speaking: _isParticipantSpeaking(
              isLocal: t.isLocal,
              agoraUid: t.agoraUid,
              userId: t.userId,
              muted: t.muted,
            ),
            forVideo: forVideo,
            height: height,
            width: width,
          );
        }

        if (n == 1) {
          return tileAt(0,
              height: constraints.maxHeight, width: constraints.maxWidth);
        }
        if (n == 2) {
          final h = (constraints.maxHeight - gap) / 2;
          return Column(
            children: [
              SizedBox(height: h, child: tileAt(0, height: h)),
              const SizedBox(height: gap),
              SizedBox(height: h, child: tileAt(1, height: h)),
            ],
          );
        }
        final cols = 2;
        final rows = (n / cols).ceil();
        final tileH = (constraints.maxHeight - gap * (rows - 1)) / rows;
        return Column(
          children: [
            for (var r = 0; r < rows; r++) ...[
              SizedBox(
                height: tileH,
                child: Row(
                  children: [
                    for (var c = 0; c < cols; c++) ...[
                      Expanded(
                        child: () {
                          final idx = r * cols + c;
                          if (idx >= n) return const SizedBox.shrink();
                          return tileAt(idx, height: tileH);
                        }(),
                      ),
                      if (c < cols - 1) const SizedBox(width: gap),
                    ],
                  ],
                ),
              ),
              if (r < rows - 1) const SizedBox(height: gap),
            ],
          ],
        );
      },
    );
  }

  Widget _whatsappParticipantTile({
    required String name,
    required String? imageUrl,
    required int? agoraUid,
    required bool isLocal,
    required bool muted,
    required bool videoMuted,
    required bool speaking,
    required bool forVideo,
    double? height,
    double? width,
  }) {
    final showVideo = forVideo &&
        _engine != null &&
        !videoMuted &&
        ((!isLocal && agoraUid != null) || (isLocal && !_cameraOff));
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: speaking ? _kSpeakingBorderColor : Colors.transparent,
          width: speaking ? 2.5 : 0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(speaking ? 9.5 : 12),
        child: Container(
          color: const Color(0xFF2A2A2A),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showVideo && isLocal)
                AgoraVideoView(
                  controller: VideoViewController(
                    rtcEngine: _engine!,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                )
              else if (showVideo && agoraUid != null)
                AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: _engine!,
                    canvas: VideoCanvas(uid: agoraUid),
                    connection: RtcConnection(channelId: _channelName ?? ''),
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BestieAvatar(
                        name: name,
                        imageUrl: imageUrl,
                        isClient: false,
                        size: min(96, (height ?? 120) * 0.42),
                      ),
                      if (speaking) ...[
                        const SizedBox(height: 10),
                        const _SpeakingWaveform(color: _kSpeakingBorderColor),
                      ],
                    ],
                  ),
                ),
              Positioned(
                left: 10,
                bottom: 10,
                right: 10,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 6)
                          ],
                        ),
                      ),
                    ),
                    if (muted)
                      const Icon(Icons.mic_off_rounded,
                          color: Colors.white70, size: 16),
                  ],
                ),
              ),
              if (speaking && showVideo)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const _SpeakingWaveform(
                      color: _kSpeakingBorderColor,
                      compact: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
      if (p['userId']?.toString() == me?.id) continue;
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
      if (p is! Map || p['userId']?.toString() == me?.id) continue;
      final user = (p['user'] as Map?)?.cast<String, dynamic>();
      final url = user?['avatarUrl']?.toString();
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  /// Centered premium stage: waveform-ringed avatar with a live status badge,
  /// the caller's name + designation, and the ACTIVE CALL label + timer.
  Widget _voiceCallStage(String remoteName) {
    final subtitle = _primaryRemoteSubtitle();
    final connected = _connectedAt != null;
    final statusText = connected ? _formatElapsed(_elapsed) : _status;
    final statusColor = connected
        ? CallScreenUiColors.neonGreen
        : _status.toLowerCase().contains('ring')
            ? const Color(0xFFFFB020)
            : CallScreenUiColors.textPrimary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 760 || constraints.maxWidth < 380;
        final profileHeight = compact ? 198.0 : 218.0;
        final topPadding = compact ? 120.0 : 132.0;
        final bottomPadding = compact ? 208.0 : 236.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            topPadding,
            16,
            bottomPadding,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: profileHeight,
                  child: _CallUiAvatarStage(
                    name: remoteName,
                    imageUrl: _primaryRemoteAvatarUrl(),
                    connected: connected,
                    height: profileHeight,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Active call', style: _activeCallLabelStyle),
                const SizedBox(height: 4),
                Text(
                  remoteName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CallScreenUiColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: CallScreenUiColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _headOfficeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CallScreenUiColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  /// Small reconnect pill for group calls (WhatsApp-style).
  Widget _compactReconnectBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Color(0xFFFBBF24)),
            ),
          ),
          SizedBox(width: 8),
          Text(
            'Reconnecting…',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Top status chips: HD Voice / Network / Secure calling.
  Widget _topChips() {
    final net = _reconnecting ? 'Reconnecting' : 'Excellent';
    final netColor =
        _reconnecting ? const Color(0xFFFBBF24) : CallScreenUiColors.neonGreen;
    return Row(children: [
      Expanded(
        child: _statChip(
          Icons.graphic_eq_rounded,
          'HD Voice',
          'Crystal Clear',
          CallScreenUiColors.neonBlue,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _statChip(
          Icons.signal_cellular_alt_rounded,
          'Network',
          net,
          netColor,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _statChip(
          Icons.shield_outlined,
          'Secure calling',
          'Connected',
          CallScreenUiColors.textPrimary,
        ),
      ),
    ]);
  }

  Widget _statChip(IconData icon, String title, String sub, Color accent) {
    return CallUiGlassContainer(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 22, color: accent),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CallScreenUiColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  )),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CallScreenUiColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w400,
                  )),
            ],
          ),
        ),
      ]),
    );
  }

  Future<void> _toggleHold() async {
    final engine = _engine;
    if (engine == null) return;
    final next = !_held;
    try {
      if (next) {
        await engine.muteLocalAudioStream(true);
        await engine.muteAllRemoteAudioStreams(true);
        if (_isVideo) await engine.muteLocalVideoStream(true);
      } else {
        await engine.muteAllRemoteAudioStreams(false);
        for (final uid in _remoteUids) {
          try {
            await engine.muteRemoteAudioStream(uid: uid, mute: false);
          } catch (_) {}
        }
        await engine.enableLocalAudio(true);
        await engine.muteLocalAudioStream(_muted);
        if (_isVideo) await engine.muteLocalVideoStream(_cameraOff);
        await _reassertAudio();
      }
    } catch (_) {/* best-effort */}
    if (mounted) setState(() => _held = next);
    _CallSession._ping();
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

  Widget _desktopPremiumCallFooter() {
    final actions = [
      (
        label: 'Mute',
        icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
        selected: _muted,
        danger: false,
        onTap: _toggleMute,
      ),
      (
        label: 'Speaker',
        icon: _route == CallAudioRoute.speaker
            ? Icons.volume_up_rounded
            : Icons.hearing_rounded,
        selected: _route == CallAudioRoute.speaker,
        danger: false,
        onTap: _toggleSpeakerRoute,
      ),
      (
        label: 'Keypad',
        icon: Icons.dialpad_rounded,
        selected: false,
        danger: false,
        onTap: _showDialPad,
      ),
      (
        label: 'Buzzer',
        icon: Icons.campaign_rounded,
        selected: false,
        danger: false,
        onTap: _sendEmergencyBuzzer,
      ),
      (
        label: 'Chat',
        icon: Icons.chat_bubble_outline_rounded,
        selected: false,
        danger: false,
        onTap: _openCallChat,
      ),
      (
        label: 'Notes',
        icon: Icons.edit_note_rounded,
        selected: false,
        danger: false,
        onTap: _showCallNotes,
      ),
      (
        label: _sharing ? 'Stop' : 'Share',
        icon: _sharing
            ? Icons.stop_screen_share_rounded
            : Icons.screen_share_rounded,
        selected: _sharing,
        danger: false,
        onTap: _toggleShare,
      ),
      (
        label: 'End',
        icon: Icons.call_end_rounded,
        selected: false,
        danger: true,
        onTap: _hangup,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final fittedWidth =
            (constraints.maxWidth - (gap * (actions.length - 1))) /
                actions.length;
        final itemWidth = fittedWidth.clamp(44.0, 58.0);
        final minWidth =
            actions.length * itemWidth + (actions.length - 1) * gap;
        return SizedBox(
          height: 70,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: max(0, (constraints.maxWidth - minWidth) / 2)),
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    _desktopFooterAction(
                      width: itemWidth,
                      label: actions[i].label,
                      icon: actions[i].icon,
                      selected: actions[i].selected,
                      danger: actions[i].danger,
                      onTap: actions[i].onTap,
                    ),
                  ],
                  SizedBox(
                      width: max(0, (constraints.maxWidth - minWidth) / 2)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _desktopFooterAction({
    required double width,
    required String label,
    required IconData icon,
    required bool selected,
    required bool danger,
    required VoidCallback onTap,
  }) {
    final fill = danger
        ? CallScreenUiColors.endCallRed
        : selected
            ? CallScreenUiColors.buttonSelectedFillTop
            : const Color(0xCC0A192F);
    final border = danger
        ? CallScreenUiColors.endCallRed.withValues(alpha: 0.72)
        : selected
            ? CallScreenUiColors.neonBlue
            : CallScreenUiColors.speakerBorderSide;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(color: border, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: (danger
                            ? CallScreenUiColors.endCallRed
                            : CallScreenUiColors.neonBlue)
                        .withValues(alpha: selected || danger ? 0.28 : 0.14),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: CallScreenUiColors.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Premium 2-row control grid + bottom action bar, matching the redesign.
  Widget _premiumCallControls({bool compact = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
      child: _premiumCallControlsCore(compact: compact),
    );
  }

  Widget _premiumCallControlsCore({bool compact = false}) {
    final lightControls = ref.watch(callScreenLightControlsProvider);
    final rowGap = compact ? 6.0 : _kPremiumControlColumnGap;
    final actionBarHeight = compact ? 62.0 : 72.0;
    final actionSize = compact ? 42.0 : 48.0;
    final centerSize = compact ? 64.0 : 72.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _premiumControlRow([
        CallUiGlassControlButton(
          label: 'Mute',
          icon: Icons.mic_off_outlined,
          isSelected: _muted,
          onTap: _toggleMute,
          lightControls: lightControls,
          compact: compact,
          iconGradient: const [
            CallScreenUiColors.neonPurple,
            CallScreenUiColors.neonMagenta,
          ],
        ),
        CallUiSpeakerButton(
          isSelected: _route == CallAudioRoute.speaker,
          onTap: _toggleSpeakerRoute,
          lightControls: lightControls,
          compact: compact,
        ),
        CallUiGlassControlButton(
          label: 'Keypad',
          icon: Icons.dialpad,
          onTap: _showDialPad,
          lightControls: lightControls,
          compact: compact,
        ),
        CallUiGlassControlButton(
          label: 'Buzzer',
          icon: Icons.campaign_rounded,
          onTap: _sendEmergencyBuzzer,
          lightControls: lightControls,
          compact: compact,
          iconGradient: const [
            Color(0xFFFBBF24),
            Color(0xFFFF8A00),
          ],
        ),
      ], gap: rowGap),
      const SizedBox(height: 8),
      _premiumControlRow([
        CallUiGlassControlButton(
          label: _sharing ? 'Stop share' : 'Share screen',
          icon: _sharing
              ? Icons.stop_screen_share_rounded
              : Icons.screen_share_rounded,
          isSelected: _sharing,
          onTap: _toggleShare,
          lightControls: lightControls,
          compact: compact,
          iconGradient: const [
            CallScreenUiColors.neonBlue,
            CallScreenUiColors.verifiedBlue,
          ],
        ),
        CallUiGlassControlButton(
          label: 'Add Participant',
          icon: Icons.person_add_outlined,
          onTap: _showInvite,
          lightControls: lightControls,
          compact: compact,
          iconGradient: const [
            CallScreenUiColors.neonBlue,
            CallScreenUiColors.neonPurple,
          ],
        ),
        CallUiGlassControlButton(
          label: 'Record',
          icon: Icons.fiber_manual_record_outlined,
          isSelected: _recording,
          onTap: _toggleRecord,
          lightControls: lightControls,
          compact: compact,
          iconGradient: const [
            Color(0xFFFF6B6B),
            Color(0xFFFF4757),
          ],
        ),
        CallUiGlassControlButton(
          label: 'Call Notes',
          icon: Icons.edit_note_outlined,
          onTap: _showCallNotes,
          lightControls: lightControls,
          compact: compact,
        ),
      ], gap: rowGap),
      SizedBox(height: compact ? 12 : 18),
      SizedBox(
        height: actionBarHeight,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: CallUiBottomActionButton(
                      icon: Icons.chat_bubble_outline,
                      size: actionSize,
                      onTap: _openCallChat,
                      compact: compact,
                    ),
                  ),
                ),
                SizedBox(width: rowGap),
                const Expanded(child: SizedBox()),
                SizedBox(width: rowGap),
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: Offset(compact ? 4 : 6, 0),
                      child: CallUiBottomActionButton(
                        icon: (!_videoEnabled || _cameraOff)
                            ? Icons.videocam_off_outlined
                            : Icons.videocam_outlined,
                        size: actionSize,
                        onTap: _toggleCamera,
                        compact: compact,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            _PressableCircle(
              onTap: _hangup,
              size: centerSize,
              child: Container(
                width: centerSize,
                height: centerSize,
                decoration: BoxDecoration(
                  color: CallScreenUiColors.endCallRed,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          CallScreenUiColors.endCallRed.withValues(alpha: 0.55),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color:
                          CallScreenUiColors.endCallRed.withValues(alpha: 0.35),
                      blurRadius: 40,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _premiumControlRow(List<Widget> children,
      {double gap = _kPremiumControlColumnGap}) {
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: children[i]),
        ],
      ],
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
    final mq = MediaQuery.of(context);
    final compact = mq.size.width < 420 || mq.size.height < 760;
    if (_isMeeting) return _meetingControls(compact: compact);
    // 3+ participants: WhatsApp-style single bottom row (fixed-size circles).
    if (_useWhatsAppParticipantGrid) {
      return _groupCallBottomControls(compact: compact);
    }
    // Premium grid for 1:1 voice; compact pill for video calls.
    final showingVideo = _isVideo && _remoteUids.isNotEmpty;
    return showingVideo
        ? _callControls(compact: compact)
        : _premiumCallControls(compact: compact);
  }

  /// Bottom control bar for group calls (3+ people) — matches WhatsApp layout:
  /// more · video · speaker · mute · end. Fixed circle sizes; no FittedBox.
  Widget _groupCallBottomControls({bool compact = false}) {
    final buttonSize = compact ? 40.0 : 52.0;
    final iconSize = compact ? 18.0 : 22.0;
    final endSize = compact ? 48.0 : 52.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ctrlCircle(
            icon: Icons.more_horiz_rounded,
            onTap: _showGroupMore,
            size: buttonSize,
            iconSize: iconSize,
          ),
          _ctrlCircle(
            icon: _isVideo
                ? ((!_videoEnabled || _cameraOff)
                    ? Icons.videocam_off_rounded
                    : Icons.videocam_rounded)
                : (_sharing
                    ? Icons.stop_screen_share_rounded
                    : Icons.screen_share_rounded),
            onTap: _isVideo ? _toggleCamera : _toggleShare,
            active: _isVideo && !_cameraOff,
            size: buttonSize,
            iconSize: iconSize,
          ),
          if (_isVideo && !_cameraOff)
            _ctrlCircle(
              icon: Icons.cameraswitch_rounded,
              onTap: _flipCamera,
              size: buttonSize,
              iconSize: iconSize,
            ),
          _ctrlCircle(
            icon: Icons.volume_up_rounded,
            onTap: _toggleSpeakerRoute,
            active: _route == CallAudioRoute.speaker,
            size: buttonSize,
            iconSize: iconSize,
          ),
          _ctrlCircle(
            icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            onTap: _toggleMute,
            active: _muted,
            size: buttonSize,
            iconSize: iconSize,
          ),
          _ctrlCircle(
            icon: Icons.call_end_rounded,
            onTap: _hangup,
            background: BestieTokens.cDanger,
            size: endSize,
            iconSize: iconSize,
          ),
        ],
      ),
    );
  }

  void _showGroupMore() {
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
              tile(Icons.dialpad, 'Keypad', _showDialPad),
              tile(Icons.person_add_alt_1_rounded, 'Add participant',
                  _showInvite),
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
              tile(Icons.notes_rounded, 'Call notes', _showCallNotes),
              tile(Icons.campaign_rounded, 'Buzzer', _sendEmergencyBuzzer),
              tile(Icons.people_alt_rounded, 'Participants', _showParticipants),
              const SizedBox(height: 4),
            ]),
          ),
        );
      },
    );
  }

  /// WhatsApp call controls — one translucent rounded pill with 5 circles:
  /// more · camera · speaker · mic · end. Share / Record / Flip live in the
  /// `_showMore` sheet to keep the bar uncluttered.
  Widget _callControls({bool compact = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ctrlCircle(
            icon: _sharing
                ? Icons.stop_screen_share_rounded
                : Icons.screen_share_rounded,
            onTap: _toggleShare,
            active: _sharing,
            size: compact ? 42 : 52,
            iconSize: compact ? 18 : 22,
          ),
          _ctrlCircle(
            icon: (!_videoEnabled || _cameraOff)
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            onTap: _toggleCamera,
            active: !_videoEnabled || _cameraOff,
            size: compact ? 42 : 52,
            iconSize: compact ? 18 : 22,
          ),
          if (_isVideo && !_cameraOff)
            _ctrlCircle(
              icon: Icons.cameraswitch_rounded,
              onTap: _flipCamera,
              size: compact ? 42 : 52,
              iconSize: compact ? 18 : 22,
            ),
          _ctrlCircle(
            icon: _audioRouteIcon(_route),
            onTap: _cycleAudioRoute,
            active: _route != CallAudioRoute.earpiece,
            size: compact ? 42 : 52,
            iconSize: compact ? 18 : 22,
          ),
          _ctrlCircle(
            icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            onTap: _toggleMute,
            active: _muted,
            size: compact ? 42 : 52,
            iconSize: compact ? 18 : 22,
          ),
          _ctrlCircle(
            icon: Icons.call_end_rounded,
            onTap: _hangup,
            background: BestieTokens.cDanger,
            size: compact ? 48 : 52,
            iconSize: compact ? 20 : 22,
          ),
        ]),
      ),
    );
  }

  /// Google Meet meeting controls — six circles in a row: mic · camera ·
  /// share · raise hand · more · leave.
  Widget _meetingControls({bool compact = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 6,
          vertical: compact ? 8 : 10,
        ),
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
            size: compact ? 42 : 52,
            iconSize: compact ? 18 : 22,
          ),
          _ctrlCircle(
            icon: (!_videoEnabled || _cameraOff)
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            onTap: _toggleCamera,
            active: !_videoEnabled || _cameraOff,
            size: compact ? 42 : 52,
            iconSize: compact ? 18 : 22,
          ),
          if (_isVideo && !_cameraOff)
            _ctrlCircle(
              icon: Icons.cameraswitch_rounded,
              onTap: _flipCamera,
              size: compact ? 42 : 52,
              iconSize: compact ? 18 : 22,
            ),
          _ctrlCircle(
            icon: _sharing
                ? Icons.stop_screen_share_rounded
                : Icons.present_to_all_rounded,
            onTap: _toggleShare,
            active: _sharing,
            size: compact ? 42 : 52,
            iconSize: compact ? 18 : 22,
          ),
          _ctrlCircle(
            icon: _handRaised
                ? Icons.front_hand_rounded
                : Icons.front_hand_outlined,
            onTap: _toggleRaiseHand,
            active: _handRaised,
            size: compact ? 42 : 52,
            iconSize: compact ? 18 : 22,
          ),
          _ctrlCircle(
            icon: Icons.more_vert_rounded,
            onTap: _showMore,
            size: compact ? 42 : 52,
            iconSize: compact ? 18 : 22,
          ),
          _ctrlCircle(
            icon: Icons.call_end_rounded,
            onTap: _hangup,
            background: BestieTokens.cDanger,
            size: compact ? 48 : 56,
            iconSize: compact ? 20 : 24,
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

/// Dark blue voice-call backdrop, matching the manual premium design.
class _FuturisticCallBackdrop extends StatefulWidget {
  const _FuturisticCallBackdrop();

  @override
  State<_FuturisticCallBackdrop> createState() =>
      _FuturisticCallBackdropState();
}

class _FuturisticCallBackdropState extends State<_FuturisticCallBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  CallScreenUiColors.backgroundTop,
                  CallScreenUiColors.backgroundMid,
                  CallScreenUiColors.backgroundBottom,
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _BackdropSmokePainter(progress: _controller.value),
          ),
        ),
      ]),
    );
  }
}

class _BackdropSmokePainter extends CustomPainter {
  final double progress;
  const _BackdropSmokePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final phase = progress * pi * 2;
    void cloud(Offset center, double radius, Color color, double blur) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }

    cloud(
      Offset(
        size.width * 0.16 + sin(phase * 0.9) * 16,
        size.height * 0.20 + cos(phase * 0.72) * 20,
      ),
      size.shortestSide * 0.46,
      const Color(0x3D1C5DFF),
      72,
    );
    cloud(
      Offset(
        size.width * 0.82 + cos(phase * 0.7) * 18,
        size.height * 0.32 + sin(phase * 0.76) * 18,
      ),
      size.shortestSide * 0.40,
      const Color(0x36C91C7D),
      80,
    );
    cloud(
      Offset(
        size.width * 0.60 + cos(phase * 0.58) * 20,
        size.height * 0.82 + sin(phase * 0.68) * 16,
      ),
      size.shortestSide * 0.36,
      const Color(0x34B11CF3),
      82,
    );
  }

  @override
  bool shouldRepaint(covariant _BackdropSmokePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _CallUiAvatarStage extends StatefulWidget {
  final String name;
  final String? imageUrl;
  final bool connected;
  final double height;
  final List<({String name, String? imageUrl})> companions;
  const _CallUiAvatarStage({
    required this.name,
    required this.imageUrl,
    required this.connected,
    required this.height,
    this.companions = const [],
  });

  @override
  State<_CallUiAvatarStage> createState() => _CallUiAvatarStageState();
}

class _CallUiAvatarStageState extends State<_CallUiAvatarStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ringOuter = widget.height * 0.92;
    final ringInner = widget.height * 0.84;
    final avatarSize = ringInner - 18;
    final miniSize = max(24.0, min(34.0, widget.height * 0.18));
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final rotation = _controller.value * pi * 2;
        final companionOffsets = <Offset>[
          Offset(ringInner * 0.42, -ringInner * 0.18),
          Offset(-ringInner * 0.42, -ringInner * 0.18),
          Offset(ringInner * 0.36, ringInner * 0.28),
          Offset(-ringInner * 0.36, ringInner * 0.28),
          Offset(0, -ringInner * 0.50),
        ];
        return SizedBox(
          width: double.infinity,
          height: widget.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: ringOuter,
                height: ringOuter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          CallScreenUiColors.neonBlue.withValues(alpha: 0.12),
                      blurRadius: 36,
                      spreadRadius: 6,
                    ),
                    BoxShadow(
                      color:
                          CallScreenUiColors.neonPurple.withValues(alpha: 0.18),
                      blurRadius: 44,
                      spreadRadius: 10,
                    ),
                    BoxShadow(
                      color: CallScreenUiColors.neonMagenta
                          .withValues(alpha: 0.10),
                      blurRadius: 52,
                      spreadRadius: 14,
                    ),
                  ],
                ),
              ),
              Transform.rotate(
                angle: rotation,
                child: CustomPaint(
                  size: Size(ringInner, ringInner),
                  painter: CallUiSmokyRingPainter(rotation: rotation * 0.35),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: ringInner - 12,
                    height: ringInner - 12,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: CallScreenUiColors.backgroundTop,
                    ),
                    padding: const EdgeInsets.all(3),
                    child: ClipOval(
                      child: BestieAvatar(
                        name: widget.name,
                        imageUrl: widget.imageUrl,
                        size: avatarSize,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.connected
                            ? CallScreenUiColors.neonGreen
                            : const Color(0xFF22C55E),
                        border: Border.all(
                          color: CallScreenUiColors.backgroundTop,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: CallScreenUiColors.neonGreen
                                .withValues(alpha: 0.6),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.call,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              for (var i = 0;
                  i < widget.companions.length && i < companionOffsets.length;
                  i++)
                Align(
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: companionOffsets[i],
                    child: _CallUiMiniAvatarBubble(
                      name: widget.companions[i].name,
                      imageUrl: widget.companions[i].imageUrl,
                      size: miniSize,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DesktopMeshAvatarStage extends StatefulWidget {
  final String name;
  final String? imageUrl;
  final bool connected;
  final double height;
  final List<({String name, String? imageUrl})> companions;
  const _DesktopMeshAvatarStage({
    required this.name,
    required this.imageUrl,
    required this.connected,
    required this.height,
    this.companions = const [],
  });

  @override
  State<_DesktopMeshAvatarStage> createState() =>
      _DesktopMeshAvatarStageState();
}

class _DesktopMeshAvatarStageState extends State<_DesktopMeshAvatarStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatarSize = min(widget.height * 0.74, 160.0).toDouble();
    final miniSize = max(22.0, min(32.0, widget.height * 0.14));
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final companionOffsets = <Offset>[
          Offset(78, -56),
          Offset(-78, -56),
          Offset(88, 52),
          Offset(-88, 52),
          Offset(0, -98),
        ];
        return SizedBox(
          width: double.infinity,
          height: widget.height + 112,
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ProfileWavePainter(progress: _controller.value),
                ),
              ),
              Align(
                alignment: const Alignment(0, -0.12),
                child: SizedBox(
                  width: 184,
                  height: 184,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: _controller.value * pi * 2,
                        child: Container(
                          width: 178,
                          height: 178,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const SweepGradient(
                              colors: [
                                Color(0xFF00F2FF),
                                Color(0xFF1677FF),
                                Color(0xFFFF00EA),
                                Color(0xFF7B00FF),
                                Color(0xFF00F2FF),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00F2FF)
                                    .withValues(alpha: 0.88),
                                blurRadius: 32,
                                spreadRadius: 4,
                              ),
                              BoxShadow(
                                color: const Color(0xFFFF00EA)
                                    .withValues(alpha: 0.72),
                                blurRadius: 52,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 166,
                        height: 166,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 1,
                          ),
                        ),
                        child: ClipOval(
                          child: BestieAvatar(
                            name: widget.name,
                            imageUrl: widget.imageUrl,
                            size: avatarSize,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 7,
                        bottom: 7,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: widget.connected
                                ? const Color(0xFF12D15E)
                                : const Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF071426),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF12D15E)
                                    .withValues(alpha: 0.8),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.call_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                      ),
                      for (var i = 0;
                          i < widget.companions.length &&
                              i < companionOffsets.length;
                          i++)
                        Transform.translate(
                          offset: companionOffsets[i],
                          child: _CallUiMiniAvatarBubble(
                            name: widget.companions[i].name,
                            imageUrl: widget.companions[i].imageUrl,
                            size: miniSize,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CallUiMiniAvatarBubble extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  const _CallUiMiniAvatarBubble({
    required this.name,
    required this.imageUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const SweepGradient(
          colors: [
            CallScreenUiColors.neonBlue,
            CallScreenUiColors.neonMagenta,
            CallScreenUiColors.neonBlue,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: CallScreenUiColors.neonBlue.withValues(alpha: 0.45),
            blurRadius: 14,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: CallScreenUiColors.neonMagenta.withValues(alpha: 0.35),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: BestieAvatar(
          name: name,
          imageUrl: imageUrl,
          size: size - 4,
        ),
      ),
    );
  }
}

class _ProfileWavePainter extends CustomPainter {
  final double progress;
  const _ProfileWavePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final topEdge = size.height * 0.10;
    final bottomEdge = size.height * 0.70;
    final centerX = size.width * 0.50;
    final blurPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final crispPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const horizontalLineCount = 38;
    const verticalLineCount = 34;
    const horizontalAmplitude = 18.0;

    double horizontalY(double x, double baseY, double phase) {
      final position = x / size.width;
      return baseY +
          sin(position * pi * 2 + phase) * horizontalAmplitude +
          sin(position * pi * 3 - phase * 0.65) * 5;
    }

    Path horizontalPath(
      double startX,
      double endX,
      double baseY,
      double phase,
    ) {
      const segments = 28;
      final path = Path()..moveTo(startX, horizontalY(startX, baseY, phase));
      for (var step = 1; step <= segments; step++) {
        final x = startX + (endX - startX) * step / segments;
        path.lineTo(x, horizontalY(x, baseY, phase));
      }
      return path;
    }

    for (var i = 0; i < horizontalLineCount; i++) {
      final t = i / (horizontalLineCount - 1);
      final phase = progress * pi * 2 + t * pi * 1.30;
      final y = topEdge + (bottomEdge - topEdge) * t;
      final leftPath = horizontalPath(0, centerX, y, phase);
      final rightPath = horizontalPath(size.width, centerX, y, phase);

      const leftColor = Color(0xFFFF00EA);
      const rightColor = Color(0xFF00CFFF);

      blurPaint
        ..strokeWidth = 2.1
        ..color = leftColor.withValues(alpha: 0.36);
      canvas.drawPath(leftPath, blurPaint);
      blurPaint.color = rightColor.withValues(alpha: 0.40);
      canvas.drawPath(rightPath, blurPaint);

      crispPaint
        ..strokeWidth = 0.95
        ..color = leftColor.withValues(alpha: 0.70);
      canvas.drawPath(leftPath, crispPaint);
      crispPaint.color = rightColor.withValues(alpha: 0.76);
      canvas.drawPath(rightPath, crispPaint);
    }

    final topPhase = progress * pi * 2;
    final bottomPhase = progress * pi * 2 + pi * 1.30;
    final meshBounds = Path()..moveTo(0, horizontalY(0, topEdge, topPhase));
    const boundarySegments = 56;
    for (var step = 1; step <= boundarySegments; step++) {
      final x = size.width * step / boundarySegments;
      meshBounds.lineTo(x, horizontalY(x, topEdge, topPhase));
    }
    for (var step = boundarySegments; step >= 0; step--) {
      final x = size.width * step / boundarySegments;
      meshBounds.lineTo(x, horizontalY(x, bottomEdge, bottomPhase));
    }
    meshBounds.close();

    canvas.save();
    canvas.clipPath(meshBounds);
    for (var i = 0; i < verticalLineCount; i++) {
      final t = i / (verticalLineCount - 1);
      final phase = progress * pi * 2 + t * pi * 1.20;
      final x = size.width * t;
      final verticalTop = horizontalY(x, topEdge, topPhase);
      final verticalBottom = horizontalY(x, bottomEdge, bottomPhase);
      final verticalPath = Path()
        ..moveTo(x, verticalTop)
        ..cubicTo(
          x - 30 - sin(phase) * 13,
          verticalTop + (verticalBottom - verticalTop) * 0.32,
          x + 34 + cos(phase) * 13,
          verticalTop + (verticalBottom - verticalTop) * 0.68,
          x + sin(phase) * 3,
          verticalBottom,
        );

      final color =
          x <= centerX ? const Color(0xFFFF00EA) : const Color(0xFF00CFFF);

      blurPaint
        ..strokeWidth = 2.0
        ..color = color.withValues(alpha: 0.34);
      canvas.drawPath(verticalPath, blurPaint);

      crispPaint
        ..strokeWidth = 0.90
        ..color = color.withValues(alpha: 0.68);
      canvas.drawPath(verticalPath, crispPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ProfileWavePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _PrototypeReconnectBanner extends StatelessWidget {
  const _PrototypeReconnectBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFB45309).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Colors.white),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Reconnecting... check your internet connection',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: BestieTokens.fwSemibold,
            ),
          ),
        ),
      ]),
    );
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

class _ConnectingDots extends StatefulWidget {
  const _ConnectingDots();

  @override
  State<_ConnectingDots> createState() => _ConnectingDotsState();
}

class _ConnectingDotsState extends State<_ConnectingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 24,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: List.generate(3, (i) {
              final phase = (_ctrl.value + i * 0.2) % 1.0;
              final opacity =
                  0.35 + 0.65 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Opacity(
                  opacity: opacity.clamp(0.35, 1.0),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.white70,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _VideoRingingIdentity extends StatelessWidget {
  const _VideoRingingIdentity({
    required this.name,
    required this.status,
    this.subtitle,
    this.headOffice,
  });

  final String name;
  final String status;
  final String? subtitle;
  final String? headOffice;

  static const _shadow = [
    Shadow(color: Colors.black87, blurRadius: 10),
    Shadow(color: Colors.black54, blurRadius: 18),
  ];

  @override
  Widget build(BuildContext context) {
    final cleanSubtitle = subtitle?.trim();
    final cleanHeadOffice = headOffice?.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            shadows: _shadow,
          ),
        ),
        if (cleanSubtitle != null && cleanSubtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            cleanSubtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              shadows: _shadow,
            ),
          ),
        ],
        if (cleanHeadOffice != null && cleanHeadOffice.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            cleanHeadOffice,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              shadows: _shadow,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            shadows: _shadow,
          ),
        ),
      ],
    );
  }
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

/// Animated audio bars shown under a participant avatar while they speak.
class _SpeakingWaveform extends StatefulWidget {
  final Color color;
  final bool compact;

  const _SpeakingWaveform({
    required this.color,
    this.compact = false,
  });

  @override
  State<_SpeakingWaveform> createState() => _SpeakingWaveformState();
}

class _SpeakingWaveformState extends State<_SpeakingWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barW = widget.compact ? 2.0 : 3.0;
    final maxH = widget.compact ? 12.0 : 16.0;
    final minH = widget.compact ? 3.0 : 4.0;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(5, (i) {
            final phase = (_ctrl.value + i * 0.18) % 1.0;
            final h =
                minH + (maxH - minH) * (0.35 + 0.65 * sin(phase * pi * 2));
            return Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: widget.compact ? 1 : 1.5),
              child: Container(
                width: barW,
                height: h,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
