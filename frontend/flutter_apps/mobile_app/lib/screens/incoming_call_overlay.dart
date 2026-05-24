import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Mounted once at the top of the router (inside [MaterialApp.router] via a
/// global [Overlay]), listens for `call.incoming` / `call.invited` socket
/// events from the backend and shows a full-screen ringer with Accept /
/// Decline buttons. This is what makes a "ringing" call actually ring on the
/// recipient's device.
class IncomingCallOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const IncomingCallOverlay({super.key, required this.child});

  @override
  ConsumerState<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends ConsumerState<IncomingCallOverlay> {
  Map<String, dynamic>? _pending;
  Timer? _autoMiss;
  final List<void Function()> _unsubs = [];
  String? _lastUserId;
  // Looping audio + lazily-built ringtone bytes. Generated on first call so
  // we don't pay the synthesis cost at app boot.
  final AudioPlayer _ringer = AudioPlayer(playerId: 'incoming_ringer');
  Uint8List? _ringtoneBytes;

  @override
  void dispose() {
    _autoMiss?.cancel();
    _hapticTimer?.cancel();
    _ringer.stop();
    _ringer.dispose();
    for (final u in _unsubs) { u(); }
    super.dispose();
  }

  /// (Re)bind socket listeners whenever the auth user changes — login,
  /// logout, or a token refresh. Without this the listeners attach once at
  /// boot to a socket that doesn't yet have an auth token, and the recipient
  /// never sees a ringer when someone calls them.
  void _subscribeFor(String? userId) {
    if (_lastUserId == userId) return;
    _lastUserId = userId;
    for (final u in _unsubs) { u(); }
    _unsubs.clear();
    if (userId == null) return; // logged out — clear listeners only

    final rt = ref.read(realtimeProvider);
    _unsubs.add(rt.onAny('call.incoming', ([data]) => _onIncoming(data)));
    _unsubs.add(rt.onAny('call.invited',  ([data]) => _onIncoming(data)));
    _unsubs.add(rt.onAny('call.declined', ([data]) {
      // Caller side: another participant declined. We dismiss our ringer if
      // it was the same call (some race conditions on group calls).
      if (_pending != null && data is Map && data['callId'] == _pending!['call']?['id']) {
        _dismiss();
      }
    }));
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

  Timer? _hapticTimer;

  void _onIncoming(dynamic data) {
    if (data is! Map) return;
    final me = ref.read(authStoreProvider).user;
    final call = (data['call'] as Map?)?.cast<String, dynamic>();
    if (call == null) return;
    // Don't ring myself for outbound calls.
    if (call['initiator']?['id'] == me?.id) return;
    setState(() => _pending = Map<String, dynamic>.from(data));
    // Auto-miss after 45s if the user ignores it (matches backend RINGING TTL).
    _autoMiss?.cancel();
    _autoMiss = Timer(const Duration(seconds: 45), _decline);

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
  }

  Future<void> _playRingtone() async {
    try {
      _ringtoneBytes ??= _buildRingtoneBytes();
      await _ringer.setReleaseMode(ReleaseMode.loop);
      await _ringer.setVolume(1.0);
      await _ringer.play(BytesSource(_ringtoneBytes!, mimeType: 'audio/wav'));
    } catch (_) { /* best-effort — silent fall back to haptics */ }
  }

  void _dismiss() {
    _autoMiss?.cancel();
    _hapticTimer?.cancel();
    _ringer.stop();
    if (mounted) setState(() => _pending = null);
  }

  Future<void> _decline() async {
    final id = _pending?['call']?['id']?.toString();
    _dismiss();
    if (id == null) return;
    try { await ref.read(apiProvider).post('/calls/$id/decline'); } catch (_) { /* server still records timeout */ }
  }

  Future<void> _accept() async {
    final id = _pending?['call']?['id']?.toString();
    final mode = _modeFor(_pending);
    _dismiss();
    if (id == null) return;
    if (context.mounted) context.go('/call/$id?mode=$mode');
  }

  String _modeFor(Map<String, dynamic>? p) {
    final m = (p?['call']?['mode'] ?? p?['mode'] ?? 'VIDEO').toString().toUpperCase();
    return m == 'VOICE' ? 'voice' : 'video';
  }

  /// Synthesizes a simple two-beat ringtone WAV in-memory so we don't have
  /// to ship a binary audio asset. 8 kHz mono 16-bit, 880 Hz tone for
  /// 0.35 s + 0.65 s silence — looped indefinitely by the player. ~16 kB.
  Uint8List _buildRingtoneBytes() {
    const sampleRate = 8000;
    const beepHz = 880;
    const beepSec = 0.35;
    const silenceSec = 0.65;
    final beepSamples = (sampleRate * beepSec).round();
    final silenceSamples = (sampleRate * silenceSec).round();
    final dataSize = (beepSamples + silenceSamples) * 2;
    final buf = BytesBuilder();
    void le16(int v) { buf.add([v & 0xFF, (v >> 8) & 0xFF]); }
    void le32(int v) {
      buf.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    }
    // RIFF/WAVE header.
    buf.add('RIFF'.codeUnits);
    le32(36 + dataSize);
    buf.add('WAVE'.codeUnits);
    buf.add('fmt '.codeUnits);
    le32(16);          // PCM chunk size
    le16(1);           // PCM format
    le16(1);           // mono
    le32(sampleRate);
    le32(sampleRate * 2);
    le16(2);
    le16(16);
    buf.add('data'.codeUnits);
    le32(dataSize);
    // Tone — gentle envelope so the start/stop doesn't pop.
    for (int i = 0; i < beepSamples; i++) {
      final t = i / sampleRate;
      // Linear attack/release on the first/last 10 ms.
      final envelope = t < 0.01
          ? t / 0.01
          : (t > beepSec - 0.01 ? (beepSec - t) / 0.01 : 1.0);
      final v = (math.sin(2 * math.pi * beepHz * t) * 0x6000 * envelope).round();
      le16(v & 0xFFFF);
    }
    for (int i = 0; i < silenceSamples; i++) { le16(0); }
    return buf.toBytes();
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
    final user = ref.watch(currentUserProvider).asData?.value
        ?? ref.watch(authStoreProvider).user;
    final uid = user?.id;
    if (uid != _lastUserId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeFor(uid));
    }

    return Stack(children: [
      widget.child,
      if (_pending != null)
        Positioned.fill(child: _RingerScreen(
          payload: _pending!,
          onAccept: _accept,
          onDecline: _decline,
        )),
    ]);
  }
}

class _RingerScreen extends ConsumerWidget {
  final Map<String, dynamic> payload;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _RingerScreen({required this.payload, required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = (payload['call'] as Map?)?.cast<String, dynamic>() ?? const {};
    final initiator = (call['initiator'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = (initiator['name'] ?? 'Someone').toString();
    final isClient = initiator['isClient'] == true;
    final kind = (call['kind'] ?? 'ONE_TO_ONE').toString();
    // Mode (voice / video) lives at the top of the socket payload — the DB
    // doesn't persist it. Fall back to call.mode for backwards-compat and
    // VIDEO as the historic default.
    final mode = (call['mode'] ?? payload['mode'] ?? 'VIDEO')
        .toString().toUpperCase();
    final participantCount = ((call['participants'] as List?)?.length ?? 0);

    return Material(
      color: const Color(0xFF0B1220),
      child: SafeArea(
        child: Column(children: [
          const SizedBox(height: 36),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const _PulseDot(),
                  const SizedBox(width: 6),
                  Text(
                    kind == 'GROUP' ? 'Group ringing · $participantCount' : 'Incoming ${mode.toLowerCase()} call',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: BestieTokens.fwSemibold, letterSpacing: BestieTokens.lsWide),
                  ),
                ]),
              ),
              const Spacer(),
              Text(
                mode == 'VOICE' ? '🎙️ Voice' : '🎥 Video',
                style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: BestieTokens.fwSemibold),
              ),
            ]),
          ),
          const Spacer(),
          // Avatar with concentric pulse rings.
          _RingingAvatar(name: name, imageUrl: initiator['avatarUrl']?.toString(), isClient: isClient),
          const SizedBox(height: 22),
          BestieUserName(
            name: name,
            isClient: isClient,
            style: const TextStyle(
              color: Colors.white, fontSize: 26,
              fontWeight: BestieTokens.fwBold,
              letterSpacing: BestieTokens.lsTight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            kind == 'GROUP' ? 'is calling the team' : 'is calling…',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 56),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _RingerButton(
                icon: Icons.call_end_rounded,
                label: 'Decline',
                color: BestieTokens.cDanger,
                onTap: onDecline,
              ),
              _RingerButton(
                icon: mode == 'VOICE' ? Icons.call_rounded : Icons.videocam_rounded,
                label: 'Accept',
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
  const _RingerButton({required this.icon, required this.label, required this.color, required this.onTap, this.bounce = false});

  @override
  State<_RingerButton> createState() => _RingerButtonState();
}

class _RingerButtonState extends State<_RingerButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.bounce) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (ctx, _) {
            final t = widget.bounce ? (1 + 0.06 * (1 - (_ctrl.value - 0.5).abs() * 2)) : 1.0;
            return Transform.scale(
              scale: t,
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: widget.color.withOpacity(0.45), blurRadius: 24, spreadRadius: 1),
                  ],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 32),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      Text(widget.label, style: const TextStyle(color: Colors.white, fontWeight: BestieTokens.fwSemibold)),
    ]);
  }
}

class _RingingAvatar extends StatefulWidget {
  final String name;
  final String? imageUrl;
  final bool isClient;
  const _RingingAvatar({required this.name, required this.imageUrl, required this.isClient});

  @override
  State<_RingingAvatar> createState() => _RingingAvatarState();
}

class _RingingAvatarState extends State<_RingingAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        return SizedBox(
          width: 200, height: 200,
          child: Stack(alignment: Alignment.center, children: [
            for (int i = 0; i < 3; i++) ...[
              _ring((_ctrl.value + i / 3) % 1.0),
            ],
            BestieAvatar(name: widget.name, imageUrl: widget.imageUrl, isClient: widget.isClient, size: 124),
          ]),
        );
      },
    );
  }

  Widget _ring(double t) {
    final size = 130 + 80 * t;
    final opacity = (1 - t).clamp(0.0, 1.0) * 0.45;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: BestieTokens.cBrand.withOpacity(opacity), width: 2),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override
  State<_PulseDot> createState() => _PulseDotState();
}
class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 6, height: 6,
        decoration: BoxDecoration(
          color: BestieTokens.cSuccess.withOpacity(0.6 + 0.4 * _ctrl.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
