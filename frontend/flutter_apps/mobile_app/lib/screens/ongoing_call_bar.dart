import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import 'call_screen.dart';

/// Wraps a [child] and overlays a slim "Ongoing call — tap to return" pill
/// at the top whenever there's a live [CallSession] and the user is NOT on
/// the call screen itself. Lets the user pop out of /call/:id while keeping
/// the audio playing and still have a one-tap way back in.
class OngoingCallBar extends StatefulWidget {
  final Widget child;
  const OngoingCallBar({super.key, required this.child});

  @override
  State<OngoingCallBar> createState() => _OngoingCallBarState();
}

class _OngoingCallBarState extends State<OngoingCallBar> {
  @override
  void initState() {
    super.initState();
    CallSession.revision.addListener(_onRevisionChanged);
  }

  @override
  void dispose() {
    CallSession.revision.removeListener(_onRevisionChanged);
    super.dispose();
  }

  void _onRevisionChanged() => setState(() {});

  bool _onCallRoute(BuildContext context) {
    try {
      final state = GoRouterState.of(context);
      final loc = state.uri.toString();
      return loc.startsWith('/call/') || loc.startsWith('/meeting/');
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showPill = CallSession.isActive && !_onCallRoute(context);
    return Stack(children: [
      widget.child,
      if (showPill)
        Positioned(
          top: MediaQuery.of(context).padding.top + 6,
          left: 12,
          right: 12,
          child: _Pill(
            onTap: () {
              final callId = CallSession.activeCallId;
              final slug = CallSession.activeMeetingSlug;
              final mode = CallSession.videoEnabled ? 'video' : 'voice';
              if (callId != null) {
                GoRouter.of(context).go('/call/$callId?mode=$mode');
              } else if (slug != null) {
                GoRouter.of(context).go('/meeting/$slug?mode=$mode');
              }
            },
          ),
        ),
    ]);
  }
}

class _Pill extends StatefulWidget {
  final VoidCallback onTap;
  const _Pill({required this.onTap});

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(BestieTokens.rPill),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (ctx, _) {
            final glow = 0.40 + 0.40 * _ctrl.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [BestieTokens.cBrand, BestieTokens.cAccent],
                ),
                borderRadius: BorderRadius.circular(BestieTokens.rPill),
                boxShadow: [
                  BoxShadow(
                    color: BestieTokens.cBrand.withOpacity(glow * 0.45),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(glow),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Ongoing call · tap to return',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: BestieTokens.fwBold,
                      letterSpacing: BestieTokens.lsSnug,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white, size: 14),
              ]),
            );
          },
        ),
      ),
    );
  }
}
