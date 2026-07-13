import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../active_call_state.dart';
import '../router.dart';
import 'call_screen.dart';

/// Wraps a [child] and overlays a WhatsApp-style floating call bubble
/// (avatar + name + live timer) whenever a [CallSession] is live and the
/// user has minimized out of /call/:id.
class OngoingCallBar extends ConsumerStatefulWidget {
  final Widget child;
  const OngoingCallBar({super.key, required this.child});

  @override
  ConsumerState<OngoingCallBar> createState() => _OngoingCallBarState();
}

class _OngoingCallBarState extends ConsumerState<OngoingCallBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    CallSession.revision.addListener(_onRevisionChanged);
    ActiveCallState.current.addListener(_onRevisionChanged);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (CallSession.isActive && !CallSession.onCallScreen) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    CallSession.revision.removeListener(_onRevisionChanged);
    ActiveCallState.current.removeListener(_onRevisionChanged);
    super.dispose();
  }

  void _onRevisionChanged() {
    if (mounted) setState(() {});
  }

  void _returnToCall() {
    CallSession.onCallScreen = true;
    CallSession.notifyRevision();
    final active = ActiveCallState.current.value;
    if (active != null) {
      ref.read(routerProvider).go(active.route);
      return;
    }
    final callId = CallSession.activeCallId;
    final slug = CallSession.activeMeetingSlug;
    final mode = CallSession.videoEnabled ? 'video' : 'voice';
    if (callId != null) {
      ref.read(routerProvider).go('/call/$callId?mode=$mode');
    } else if (slug != null) {
      ref.read(routerProvider).go('/meeting/$slug?mode=$mode');
    }
  }

  /// True when the user is on /call/:id or /meeting/:slug.
  /// Must not use [GoRouter.state] here — at cold start the match list can be
  /// empty and `.state` throws `Bad state: No element` (see go_router delegate).
  bool _onCallRoute(WidgetRef ref) {
    try {
      final config =
          ref.read(routerProvider).routerDelegate.currentConfiguration;
      final loc = config.uri.path;
      if (loc.isEmpty) return false;
      return loc.startsWith('/call/') || loc.startsWith('/meeting/');
    } catch (_) {
      return false;
    }
  }

  bool _showBubble(WidgetRef ref) {
    if (CallSession.onCallScreen || _onCallRoute(ref)) return false;
    final active = ActiveCallState.current.value;
    // Engine alive is enough — `joined` can briefly flicker during reconnects
    // and was hiding the return bubble on 3+ participant calls.
    return CallSession.isActive &&
        active != null &&
        (active.callId != null || active.meetingSlug != null);
  }

  bool get _isGroupBubble {
    final active = ActiveCallState.current.value;
    if (active == null) return false;
    return active.participants.length > 1 ||
        active.title.contains(',') ||
        active.title.contains('+');
  }

  String get _displayName {
    final active = ActiveCallState.current.value;
    if (_isGroupBubble &&
        active != null &&
        active.title.isNotEmpty &&
        active.title != 'Call') {
      return active.title;
    }
    final cached = CallSession.remotePeerName;
    if (cached != null &&
        cached.isNotEmpty &&
        cached != 'Call' &&
        cached != 'Connecting…') {
      return cached;
    }
    if (active != null && active.title.isNotEmpty && active.title != 'Call') {
      return active.title;
    }
    if (CallSession.remoteNames.isNotEmpty) {
      for (final n in CallSession.remoteNames.values) {
        if (n.isNotEmpty) return n;
      }
    }
    if (active != null && active.participants.isNotEmpty) {
      return active.participants.first;
    }
    return active?.title ?? 'Call';
  }

  String? get _bubbleAvatarUrl =>
      _isGroupBubble ? null : CallSession.remotePeerAvatarUrl;

  String get _elapsedLabel {
    final started = CallSession.connectedAt ??
        ActiveCallState.current.value?.connectedAt;
    if (started == null) return 'Ringing…';
    return _formatElapsed(DateTime.now().difference(started));
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(routerProvider);
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final showBubble = _showBubble(ref);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (showBubble)
          Positioned(
            left: 12,
            bottom: bottomPad + 88,
            child: _FloatingCallBubble(
              name: _displayName,
              imageUrl: _bubbleAvatarUrl,
              elapsed: _elapsedLabel,
              isVideo: CallSession.videoEnabled,
              onTap: _returnToCall,
            ),
          ),
      ],
    );
  }
}

class _FloatingCallBubble extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final String elapsed;
  final bool isVideo;
  final VoidCallback onTap;

  const _FloatingCallBubble({
    required this.name,
    this.imageUrl,
    required this.elapsed,
    required this.isVideo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 92,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2332),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  BestieAvatar(name: name, imageUrl: imageUrl, size: 52),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: BestieTokens.cSuccess,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF1A2332), width: 2),
                      ),
                      child: Icon(
                        isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: BestieTokens.fwBold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                elapsed,
                style: TextStyle(
                  color: BestieTokens.cSuccess.withValues(alpha: 0.95),
                  fontSize: 11,
                  fontWeight: BestieTokens.fwSemibold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
