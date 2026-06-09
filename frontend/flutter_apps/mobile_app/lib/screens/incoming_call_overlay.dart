import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../active_call_state.dart';
import '../router.dart';
import '../state.dart';
import 'call_screen.dart';

final _incomingCallPushEvents =
    StreamController<Map<String, dynamic>>.broadcast();

void showIncomingCallFromPush(Map<String, dynamic> data) {
  _incomingCallPushEvents.add(data);
}

/// Mounted once at the top of the router (inside [MaterialApp.router] via a
/// global [Overlay]), listens for `call.incoming` / `call.invited` socket
/// events from the backend and shows a full-screen ringer with Accept /
/// Decline buttons. This is what makes a "ringing" call actually ring on the
/// recipient's device.
class IncomingCallOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const IncomingCallOverlay({super.key, required this.child});

  @override
  ConsumerState<IncomingCallOverlay> createState() =>
      _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends ConsumerState<IncomingCallOverlay>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _pending;
  Map<String, dynamic>? _emergency;
  Timer? _autoMiss;
  Timer? _emergencyHaptic;
  StreamSubscription<Map<String, dynamic>>? _pushInviteSub;
  final List<void Function()> _unsubs = [];
  String? _lastUserId;
  final _ringtone = FlutterRingtonePlayer();
  final _customRingtone = AudioPlayer();
  final _tts = FlutterTts();
  bool _appResumed = true;
  String? _ringingSoundUrl;

  @override
  void initState() {
    super.initState();
    _appResumed = WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.paused &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.detached;
    WidgetsBinding.instance.addObserver(this);
    _pushInviteSub = _incomingCallPushEvents.stream.listen(_onPushInvite);
  }

  @override
  void dispose() {
    _autoMiss?.cancel();
    _hapticTimer?.cancel();
    _emergencyHaptic?.cancel();
    _bannerTimer?.cancel();
    _pushInviteSub?.cancel();
    _ringtone.stop();
    _customRingtone.dispose();
    _tts.stop();
    for (final u in _unsubs) {
      u();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (!_appResumed) {
      _autoMiss?.cancel();
      _hapticTimer?.cancel();
      _ringtone.stop();
      _customRingtone.stop();
      if (mounted && _pending != null) setState(() => _pending = null);
    }
  }

  /// (Re)bind socket listeners whenever the auth user changes — login,
  /// logout, or a token refresh. Without this the listeners attach once at
  /// boot to a socket that doesn't yet have an auth token, and the recipient
  /// never sees a ringer when someone calls them.
  void _subscribeFor(String? userId) {
    if (_lastUserId == userId) return;
    _lastUserId = userId;
    for (final u in _unsubs) {
      u();
    }
    _unsubs.clear();
    if (userId == null) return; // logged out — clear listeners only

    final rt = ref.read(realtimeProvider);
    _unsubs.add(rt.onAny('call.incoming', ([data]) => _onIncoming(data)));
    _unsubs.add(rt.onAny('call.invited', ([data]) => _onIncoming(data)));
    _unsubs.add(rt.onAny('call.waiting', ([data]) => _onWaiting(data)));
    _unsubs.add(rt.onAny('call.buzzer', ([data]) => _onCallBuzzer(data)));
    _unsubs.add(rt.onAny('call.waiting.accepted', ([data]) {
      if (data is! Map) return;
      final callId = (data['call'] as Map?)?['id']?.toString();
      if (callId == null || callId.isEmpty) return;
      _ringtone.stop();
      _customRingtone.stop();
      _speak('Your call was accepted. Joining the conference.');
      ref.read(routerProvider).go(
          '/call/$callId?mode=${(data['mode'] ?? 'VOICE').toString().toLowerCase()}');
    }));
    _unsubs.add(rt.onAny('call.waiting.rejected', ([data]) {
      if (data is! Map || !mounted) return;
      _ringtone.stop();
      _customRingtone.stop();
      final name = (data['userName'] ?? 'The person').toString();
      _speak('$name rejected the waiting call.');
      setState(() => _banner = {
            'title': 'Call declined',
            'body': '$name could not accept your waiting call.',
            'kind': 'CALL',
          });
    }));
    // Meeting invites get the same ringer treatment as a call so the user
    // can Accept and land directly inside the meeting room.
    _unsubs
        .add(rt.onAny('meeting.invited', ([data]) => _onMeetingInvited(data)));
    // Default OS notification tone whenever the server pushes a new
    // notification (chat message, mention, task assignment, etc). The
    // backend already filters out muted / off-channel events via
    // notify(), so we ring whenever this fires.
    _unsubs.add(
        rt.onAny('notification.created', ([data]) => _onNotification(data)));
    _unsubs.add(rt.onAny('call.declined', ([data]) {
      // Caller side: another participant declined. We dismiss our ringer if
      // it was the same call (some race conditions on group calls).
      if (_pending != null &&
          data is Map &&
          data['callId'] == _pending!['call']?['id']) {
        _dismiss();
      }
      _clearEndedOngoingCall(data);
    }));
    // Global call-end cleanup. The CallScreen also handles call.ended, but it
    // unsubscribes on dispose — so when the user backgrounds a call to the
    // "ongoing call" pill and the call then ends remotely, nothing cleared the
    // pill and it lingered as "tap to join". This always-mounted listener
    // guarantees the pill is cleared whenever the active call ends.
    _unsubs
        .add(rt.onAny('call.ended', ([data]) => _clearEndedOngoingCall(data)));
    // Emergency siren (#11): admin-triggered loud alarm that blares until the
    // recipient acknowledges. Also fired on escalation.
    _unsubs.add(rt.onAny('emergency.alert', ([data]) => _onEmergency(data)));
    _unsubs.add(rt.onAny('call.participant.joined', ([data]) {
      // Only dismiss if *this* user joined the call from somewhere else
      // (e.g. accepted on another device). If we kill the ringer for any
      // participant join, the caller's own auto-join immediately yanks the
      // ringer off the recipient's screen — that's the "1-second flash"
      // the user was seeing.
      if (data is! Map) return;
      if (data['userId'] != userId) return;
      _dismiss();
    }));
  }

  /// Clears the "ongoing call" pill when the matching call ends, even if the
  /// CallScreen widget is already disposed (user backgrounded to the pill).
  void _clearEndedOngoingCall(dynamic data) {
    if (data is! Map) return;
    final endedId = data['callId']?.toString();
    final active = ActiveCallState.current.value;
    if (active == null) return;
    if (endedId == null || endedId.isEmpty || endedId == active.callId) {
      ActiveCallState.clear();
    }
  }

  /// Emergency siren (#11): blare a looping alarm + heavy haptics and show a
  /// full-screen alert until the user acknowledges.
  void _onEmergency(dynamic data) {
    if (data is! Map) return;
    if (!mounted) return;
    setState(() => _emergency = Map<String, dynamic>.from(data));
    HapticFeedback.heavyImpact();
    _emergencyHaptic?.cancel();
    _emergencyHaptic = Timer.periodic(const Duration(milliseconds: 900), (_) {
      HapticFeedback.heavyImpact();
    });
    _playAlarm();
  }

  Future<void> _onCallBuzzer(dynamic data) async {
    if (data is! Map) return;
    if (CallSession.onCallScreen) return;
    HapticFeedback.heavyImpact();
    try {
      var url = data['audioUrl']?.toString();
      if (url == null || url.isEmpty) {
        final settings =
            await ref.read(apiProvider).settingsScope(scope: 'calls');
        final calls = (settings['calls'] as Map?)?.cast<String, dynamic>();
        url = calls?['emergencyBuzzerSoundUrl']?.toString();
      }
      if (url != null && url.isNotEmpty) {
        await _customRingtone.setReleaseMode(ReleaseMode.release);
        await _customRingtone.play(UrlSource(url), volume: 1);
      } else {
        await _ringtone.play(
          android: AndroidSounds.alarm,
          ios: IosSounds.alarm,
          looping: false,
          volume: 1,
          asAlarm: true,
        );
      }
      if (mounted) {
        setState(() => _banner = {
              'title': 'Emergency buzzer',
              'body':
                  '${data['fromName'] ?? 'A participant'} needs your attention.',
              'kind': 'CALL',
            });
      }
    } catch (_) {}
  }

  Future<void> _playAlarm() async {
    try {
      await _ringtone.play(
        android: AndroidSounds.alarm,
        ios: IosSounds.alarm,
        looping: true,
        volume: 1.0,
        asAlarm: true, // plays even in silent mode
      );
    } catch (_) {/* best-effort */}
  }

  Future<void> _ackEmergency() async {
    final id = _emergency?['alertId']?.toString();
    _emergencyHaptic?.cancel();
    _ringtone.stop();
    _customRingtone.stop();
    if (mounted) setState(() => _emergency = null);
    if (id == null) return;
    try {
      await ref.read(apiProvider).post('/emergency/$id/ack');
    } catch (_) {/* server keeps the record either way */}
  }

  Timer? _hapticTimer;

  /// Reshape a `meeting.invited` payload into the same `_pending` schema as
  /// an incoming call so the ringer screen can render it without a second
  /// code path. Accept navigates to /meeting/:slug instead of /call/:id —
  /// handled in `_accept` by checking for `meetingSlug`.
  void _onMeetingInvited(dynamic data) {
    if (data is! Map) return;
    final meeting = (data['meeting'] as Map?)?.cast<String, dynamic>();
    if (meeting == null) return;
    _onIncoming({
      'call': {
        // Synthetic call object so the ringer screen reuses its layout.
        'id': null,
        'kind': 'MEETING',
        'mode': meeting['mode'] ?? 'VIDEO',
        'initiator': meeting['host'],
        'name': meeting['name'],
      },
      'mode': meeting['mode'] ?? 'VIDEO',
      'meetingSlug': meeting['slug'],
      'meetingName': meeting['name'],
    });
  }

  void _onPushInvite(Map<String, dynamic> data) {
    if (!_appResumed) return;
    final type = data['type']?.toString();
    final mode = (data['mode'] ?? 'VIDEO').toString().toUpperCase();
    final fromName =
        (data['fromName'] ?? data['title'] ?? 'Someone').toString();

    if (type == 'call.incoming') {
      final callId = data['callId']?.toString();
      if (callId == null || callId.isEmpty) return;
      _onIncoming({
        'call': {
          'id': callId,
          'kind': 'ONE_TO_ONE',
          'mode': mode,
          'initiator': {'name': fromName},
        },
        'mode': mode,
      });
      return;
    }

    if (type == 'meeting.invited') {
      final slug = data['meetingSlug']?.toString();
      if (slug == null || slug.isEmpty) return;
      final meetingName = (data['body'] ?? '').toString();
      _onIncoming({
        'call': {
          'id': null,
          'kind': 'MEETING',
          'mode': mode,
          'initiator': {'name': fromName},
          'name': meetingName,
        },
        'mode': mode,
        'meetingSlug': slug,
        'meetingName': meetingName,
      });
    }
  }

  void _onIncoming(dynamic data) {
    if (!_appResumed) return;
    if (data is! Map) return;
    final me = ref.read(authStoreProvider).user;
    final call = (data['call'] as Map?)?.cast<String, dynamic>();
    if (call == null) return;
    final nextCallId = call['id']?.toString();
    final nextSlug = data['meetingSlug']?.toString();
    final currentCallId = _pending?['call']?['id']?.toString();
    final currentSlug = _pending?['meetingSlug']?.toString();
    final isSameCall = nextCallId != null &&
        nextCallId.isNotEmpty &&
        nextCallId == currentCallId;
    final isSameMeeting =
        nextSlug != null && nextSlug.isNotEmpty && nextSlug == currentSlug;
    if (isSameCall || isSameMeeting) return;
    if (CallSession.isActive && nextCallId != null && nextCallId.isNotEmpty) {
      _onWaiting({...Map<String, dynamic>.from(data), 'waiting': true});
      return;
    }
    if (_pending != null) {
      _autoMiss?.cancel();
      _hapticTimer?.cancel();
      _ringtone.stop();
      _customRingtone.stop();
    }
    // Don't ring myself for outbound calls / meetings I'm hosting.
    if (call['initiator']?['id'] == me?.id) return;
    if ((call['host'] as Map?)?['id'] == me?.id) return;
    setState(() => _pending = Map<String, dynamic>.from(data));
    // Auto-decline shortly after the backend's 60s RINGING TTL so the server
    // is the source of truth for "missed" and the two don't fight at 45s.
    _autoMiss?.cancel();
    _autoMiss = Timer(const Duration(seconds: 62), _decline);

    // Buzz the device every second so the user notices even with the screen
    // off. Pair it with a looping synthesized ringtone (no asset needed —
    // we build the WAV bytes in `_buildRingtoneBytes`) so the call also
    // actually *rings* the way users expect.
    HapticFeedback.heavyImpact();
    _hapticTimer?.cancel();
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      HapticFeedback.heavyImpact();
    });
    _playRingtone();
    final caller = (call['initiator']?['name'] ?? 'Someone').toString();
    _speak('$caller is calling you. Please attend the call.');
  }

  void _onWaiting(dynamic data) {
    if (data is! Map || !mounted) return;
    final call = (data['call'] as Map?)?.cast<String, dynamic>();
    final callId = data['callId']?.toString() ?? call?['id']?.toString();
    if (callId == null || callId.isEmpty) return;
    final caller =
        (data['callerName'] ?? call?['initiator']?['name'] ?? 'Someone')
            .toString();
    setState(() => _pending = {
          ...Map<String, dynamic>.from(data),
          'waiting': true,
          'call': call ??
              {
                'id': callId,
                'kind': 'ONE_TO_ONE',
                'initiator': {'id': data['callerId'], 'name': caller},
              },
        });
    _playRingtone();
    _speak(
        '$caller is calling. Accept to add them to your current call, or reject the call.');
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setPitch(1.02);
      await _tts.setSpeechRate(0.36);
      await _tts.speak(text);
    } catch (_) {}
  }

  DateTime? _lastNotifChime;
  Map<String, dynamic>? _banner;
  Timer? _bannerTimer;
  final Set<String> _shownNotificationIds = {};

  /// Fired on every realtime `notification.created` (task assigned, chat,
  /// mention, etc). Plays the chime AND shows a tappable in-app banner so the
  /// notification is actually visible while the app is open — not just audible.
  void _onNotification(dynamic data) {
    if (data is Map) {
      final id = data['id']?.toString();
      if (id != null && id.isNotEmpty && !_shownNotificationIds.add(id)) return;
      if (_shownNotificationIds.length > 200) _shownNotificationIds.clear();
    }
    _playNotificationTone();
    if (!_appResumed || data is! Map) return;
    final title = (data['title'] ?? '').toString();
    final body = (data['body'] ?? '').toString();
    if (title.isEmpty && body.isEmpty) return;
    if (!mounted) return;
    setState(() => _banner = Map<String, dynamic>.from(data));
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  void _openBanner() {
    final n = _banner;
    _bannerTimer?.cancel();
    if (mounted) setState(() => _banner = null);
    if (n == null) return;
    final route = _routeForNotification(n);
    if (route != null) ref.read(routerProvider).go(route);
  }

  /// Maps a notification's inner `data` to an in-app route. Mirrors the push
  /// deep-link logic in main.dart so a tap lands on the same screen.
  String? _routeForNotification(Map n) {
    final inner = (n['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final taskId = inner['taskId']?.toString();
    if (taskId != null && taskId.isNotEmpty) return '/tasks/$taskId';
    final channelId = inner['channelId']?.toString();
    if (channelId != null && channelId.isNotEmpty) return '/chat/$channelId';
    final kind = (n['kind'] ?? '').toString();
    if (kind == 'LEAD_FOLLOWUP') return '/telecaller';
    return '/notifications';
  }

  /// Plays a single OS-default notification chime — used for incoming chat
  /// messages + non-call notifications. Rate-limited to one chime per 800 ms
  /// so a flurry of arrivals (e.g. backfill on reconnect) doesn't turn into
  /// a machine-gun ding.
  Future<void> _playNotificationTone() async {
    if (!_appResumed) return;
    final now = DateTime.now();
    if (_lastNotifChime != null &&
        now.difference(_lastNotifChime!).inMilliseconds < 800) {
      return;
    }
    _lastNotifChime = now;
    try {
      await _ringtone.play(
        android: AndroidSounds.notification,
        ios: IosSounds.glass,
        looping: false,
        volume: 0.9,
        asAlarm: false,
      );
    } catch (_) {/* best effort */}
  }

  Future<void> _playRingtone() async {
    try {
      if (_ringingSoundUrl == null) {
        final settings =
            await ref.read(apiProvider).settingsScope(scope: 'calls');
        final calls = (settings['calls'] as Map?)?.cast<String, dynamic>();
        _ringingSoundUrl = calls?['ringingSoundUrl']?.toString();
      }
      final url = _ringingSoundUrl;
      if (url != null && url.isNotEmpty) {
        await _ringtone.stop();
        await _customRingtone.setReleaseMode(ReleaseMode.loop);
        await _customRingtone.play(UrlSource(url), volume: 1);
        return;
      }
      // Loop the *device's* default ringtone — what the user expects, vs
      // a generic synth tone. flutter_ringtone_player wraps RingtoneManager
      // on Android and AudioServicesPlay on iOS so it respects volume +
      // silent mode automatically.
      await _ringtone.play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.electronic,
        looping: true,
        volume: 1.0,
        asAlarm: false,
      );
    } catch (_) {/* best-effort — silent fall back to haptics */}
  }

  void _dismiss() {
    _autoMiss?.cancel();
    _hapticTimer?.cancel();
    _ringtone.stop();
    _customRingtone.stop();
    _tts.stop();
    if (mounted) setState(() => _pending = null);
  }

  Future<void> _decline() async {
    final id = _pending?['call']?['id']?.toString();
    final waiting = _pending?['waiting'] == true;
    _dismiss();
    if (id == null) return;
    try {
      await ref
          .read(apiProvider)
          .post(waiting ? '/calls/$id/waiting/reject' : '/calls/$id/decline');
    } catch (_) {/* server still records timeout */}
  }

  Future<void> _accept() async {
    final meetingSlug = _pending?['meetingSlug']?.toString();
    final callId = _pending?['call']?['id']?.toString();
    final mode = _modeFor(_pending);
    final waiting = _pending?['waiting'] == true;
    if (meetingSlug == null && callId == null) {
      _dismiss();
      return;
    }
    if (waiting && callId != null) {
      _dismiss();
      try {
        await ref.read(apiProvider).post('/calls/$callId/waiting/accept',
            body: {'mode': mode.toUpperCase()});
        if (mounted) {
          bestieToast(context, 'Caller added',
              body: 'The waiting caller can now join this conference.',
              kind: BestieToastKind.success);
        }
      } catch (e) {
        if (mounted) {
          bestieToast(context, 'Could not accept waiting call',
              body: formatApiError(e), kind: BestieToastKind.error);
        }
      }
      return;
    }
    // Stop the ringtone + haptic immediately so the user gets instant
    // feedback the tap landed, but leave _pending alone so the overlay
    // stays painted until GoRouter has actually mounted the destination
    // screen. Tearing the overlay down *before* navigation has occasionally
    // left the user back on /chat — this ordering is the bullet-proof
    // version.
    _autoMiss?.cancel();
    _hapticTimer?.cancel();
    _ringtone.stop();
    _customRingtone.stop();
    final target = meetingSlug != null
        ? '/meeting/$meetingSlug?mode=$mode'
        : '/call/$callId?mode=$mode';
    ref.read(routerProvider).go(target);
    // One frame after navigation has taken effect, wipe the ringer state
    // so a stale _pending doesn't leak into the next incoming call.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _pending = null);
    });
  }

  String _modeFor(Map<String, dynamic>? p) {
    final m =
        (p?['call']?['mode'] ?? p?['mode'] ?? 'VIDEO').toString().toUpperCase();
    return m == 'VOICE' ? 'voice' : 'video';
  }

  @override
  Widget build(BuildContext context) {
    // Keep realtime alive at boot so events fire even when no screen watches
    // the provider explicitly. The kick provider only reads — it never
    // rebuilds this widget on socket churn.
    ref.watch(realtimeBootProvider);

    // (Re)subscribe whenever the authenticated user changes — login, logout,
    // token refresh. Without this the ringer was attaching to a token-less
    // socket and the recipient never saw an incoming-call screen.
    final user = ref.watch(currentUserProvider).asData?.value ??
        ref.watch(authStoreProvider).user;
    final uid = user?.id;
    if (uid != _lastUserId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeFor(uid));
    }

    return Stack(children: [
      widget.child,
      // In-app notification banner (task assigned, mention, etc) — only when
      // there's no full-screen ringer up.
      if (_banner != null && _pending == null)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _NotificationBanner(
            payload: _banner!,
            onTap: _openBanner,
            onDismiss: () {
              _bannerTimer?.cancel();
              if (mounted) setState(() => _banner = null);
            },
          ),
        ),
      if (_pending != null)
        Positioned.fill(
            child: _RingerScreen(
          payload: _pending!,
          onAccept: _accept,
          onDecline: _decline,
        )),
      // Emergency siren sits above everything (incl. an active ringer).
      if (_emergency != null)
        Positioned.fill(
            child: _EmergencyScreen(
          payload: _emergency!,
          onAck: _ackEmergency,
        )),
    ]);
  }
}

/// Full-screen blaring emergency alert. Stays until the user acknowledges.
class _EmergencyScreen extends StatelessWidget {
  final Map<String, dynamic> payload;
  final VoidCallback onAck;
  const _EmergencyScreen({required this.payload, required this.onAck});

  @override
  Widget build(BuildContext context) {
    final fromName = (payload['fromName'] ?? 'Admin').toString();
    final message = (payload['message'] ?? '').toString().trim();
    final escalation =
        payload['escalation'] == true || payload['escalation'] == '1';
    return Material(
      color: const Color(0xFFB91C1C),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              _Pulse(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(Icons.notifications_active_rounded,
                      color: Colors.white, size: 60),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                escalation ? 'URGENT — RESPOND NOW' : 'EMERGENCY ALERT',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message.isNotEmpty
                    ? message
                    : '$fromName needs your immediate attention',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 17, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text('From $fromName',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onAck,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFB91C1C),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("I'M RESPONDING",
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.92, end: 1.08)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// A compact, tappable banner that slides in from the top for a new realtime
/// notification. Tapping opens the target; the X dismisses it.
class _NotificationBanner extends StatelessWidget {
  final Map<String, dynamic> payload;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  const _NotificationBanner(
      {required this.payload, required this.onTap, required this.onDismiss});

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'TASK':
        return Icons.checklist_rounded;
      case 'CHAT':
      case 'MENTION':
        return Icons.chat_bubble_rounded;
      case 'LEAD_FOLLOWUP':
        return Icons.phone_in_talk_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BestieColors.of(context);
    final title = (payload['title'] ?? 'Notification').toString();
    final body = (payload['body'] ?? '').toString();
    final kind = (payload['kind'] ?? '').toString();
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.brand.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_iconFor(kind), color: colors.brand, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: BestieTokens.fwSemibold,
                          fontSize: 14,
                        ),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: colors.textSoft, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: colors.textMuted, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: onDismiss,
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingerScreen extends ConsumerWidget {
  final Map<String, dynamic> payload;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _RingerScreen(
      {required this.payload, required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = (payload['call'] as Map?)?.cast<String, dynamic>() ?? const {};
    final initiator =
        (call['initiator'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = (initiator['name'] ?? 'Someone').toString();
    final isClient = initiator['isClient'] == true;
    final kind = (call['kind'] ?? 'ONE_TO_ONE').toString();
    // Mode (voice / video) lives at the top of the socket payload — the DB
    // doesn't persist it. Fall back to call.mode for backwards-compat and
    // VIDEO as the historic default.
    final mode =
        (call['mode'] ?? payload['mode'] ?? 'VIDEO').toString().toUpperCase();
    final participantCount = ((call['participants'] as List?)?.length ?? 0);
    final isMeeting = kind == 'MEETING' || payload['meetingSlug'] != null;
    final meetingName =
        (payload['meetingName'] ?? call['name'] ?? '').toString();

    final subtitle = isMeeting
        ? (meetingName.isEmpty ? 'Meeting invite' : 'Meeting · $meetingName')
        : (mode == 'VOICE' ? 'MyTaskKing voice call' : 'MyTaskKing video call');
    return Material(
      color: const Color(0xFF0B1220),
      child: SafeArea(
        child: Column(children: [
          const SizedBox(height: 56),
          // Single slim status line at the top — WhatsApp shows just the
          // service name, no chip + no mode toggle on the right.
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: BestieTokens.fwSemibold,
                letterSpacing: BestieTokens.lsWide,
              ),
            ),
          ]),
          const Spacer(),
          _RingingAvatar(
              name: name,
              imageUrl: initiator['avatarUrl']?.toString(),
              isClient: isClient),
          const SizedBox(height: 24),
          BestieUserName(
            name: name,
            isClient: isClient,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: BestieTokens.fwBold,
              letterSpacing: BestieTokens.lsTight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            kind == 'GROUP'
                ? 'Group call · $participantCount'
                : (isMeeting ? 'invited you' : 'incoming call…'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const Spacer(),
          // Two big circles, no labels — pure WhatsApp.
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 56, 64),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RingerButton(
                    icon: Icons.call_end_rounded,
                    label: '',
                    color: BestieTokens.cDanger,
                    onTap: onDecline,
                  ),
                  _RingerButton(
                    icon: mode == 'VOICE'
                        ? Icons.call_rounded
                        : Icons.videocam_rounded,
                    label: '',
                    color: BestieTokens.cSuccess,
                    onTap: onAccept,
                    bounce: true,
                  ),
                ]),
          ),
        ]),
      ),
    );
  }
}

class _RingerButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool bounce;
  const _RingerButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap,
      this.bounce = false});

  @override
  State<_RingerButton> createState() => _RingerButtonState();
}

class _RingerButtonState extends State<_RingerButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.bounce) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Outer GestureDetector with `behavior: opaque` so the whole 96-px
      // square is tappable (not just the painted 72-px circle) — the
      // bouncing scale animation kept eating taps that just clipped the
      // edge of the visible icon. Inner widget keeps the visual bounce.
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: 96,
          height: 96,
          child: Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (ctx, _) {
                final t = widget.bounce
                    ? (1 + 0.06 * (1 - (_ctrl.value - 0.5).abs() * 2))
                    : 1.0;
                return IgnorePointer(
                  child: Transform.scale(
                    scale: t,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: widget.color.withValues(alpha: 0.45),
                              blurRadius: 24,
                              spreadRadius: 1),
                        ],
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 32),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      if (widget.label.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(widget.label,
            style: const TextStyle(
                color: Colors.white, fontWeight: BestieTokens.fwSemibold)),
      ],
    ]);
  }
}

class _RingingAvatar extends StatefulWidget {
  final String name;
  final String? imageUrl;
  final bool isClient;
  const _RingingAvatar(
      {required this.name, required this.imageUrl, required this.isClient});

  @override
  State<_RingingAvatar> createState() => _RingingAvatarState();
}

class _RingingAvatarState extends State<_RingingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        return SizedBox(
          width: 200,
          height: 200,
          child: Stack(alignment: Alignment.center, children: [
            for (int i = 0; i < 3; i++) ...[
              _ring((_ctrl.value + i / 3) % 1.0),
            ],
            BestieAvatar(
                name: widget.name,
                imageUrl: widget.imageUrl,
                isClient: widget.isClient,
                size: 124),
          ]),
        );
      },
    );
  }

  Widget _ring(double t) {
    final size = 130 + 80 * t;
    final opacity = (1 - t).clamp(0.0, 1.0) * 0.45;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: BestieTokens.cBrand.withValues(alpha: opacity), width: 2),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color:
              BestieTokens.cSuccess.withValues(alpha: 0.6 + 0.4 * _ctrl.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
