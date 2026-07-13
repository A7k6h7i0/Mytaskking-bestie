import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';

/// Wraps [child] and slides a thin amber bar down from the top whenever the
/// realtime socket drops. Auto-hides on reconnect. A short grace delay
/// avoids flashing the bar during the normal connect handshake at boot or
/// brief blips.
class ConnectivityBanner extends ConsumerStatefulWidget {
  final Widget child;
  const ConnectivityBanner({super.key, required this.child});

  @override
  ConsumerState<ConnectivityBanner> createState() =>
      _ConnectivityBannerState();
}

class _ConnectivityBannerState extends ConsumerState<ConnectivityBanner> {
  core.BestieConnState _state = core.BestieConnState.connecting;
  bool _show = false;
  Timer? _grace;
  core.BestieRealtime? _rt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rt = ref.read(realtimeProvider);
      _rt!.connState.addListener(_onStateChanged);
      _onStateChanged();
    });
  }

  @override
  void dispose() {
    _grace?.cancel();
    _rt?.connState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    final next = _rt?.connState.value ?? core.BestieConnState.connecting;
    _state = next;
    if (next == core.BestieConnState.connecting) {
      _grace?.cancel();
      if (_show && mounted) setState(() => _show = false);
      return;
    }
    if (next == core.BestieConnState.connected) {
      _grace?.cancel();
      if (_show && mounted) setState(() => _show = false);
      return;
    }
    // Disconnected / connecting → wait 2.5 s before showing so a normal
    // reconnect handshake doesn't flash the bar.
    _grace?.cancel();
    _grace = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      if (_state != core.BestieConnState.connected) {
        setState(() => _show = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Only meaningful once signed in — the socket only connects with an auth
    // token, so on the login screen it's "disconnected" by design and the
    // offline banner would show falsely. Gate it on having a logged-in user.
    final user = ref.watch(currentUserProvider).asData?.value ??
        ref.read(authStoreProvider).user;
    final visible = _show && user != null;
    return Stack(children: [
      widget.child,
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          offset: visible ? Offset.zero : const Offset(0, -1),
          child: visible ? const _Bar() : const SizedBox.shrink(),
        ),
      ),
    ]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar();

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, topInset + 6, 12, 8),
        color: BestieTokens.cWarning,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          SizedBox(width: 10),
          Text(
            'You\'re offline — reconnecting…',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: BestieTokens.fwSemibold,
            ),
          ),
        ]),
      ),
    );
  }
}
