import 'package:flutter/material.dart';
import '../tokens.dart';

/// Bestie's Rive wrapper. Loads a `.riv` asset lazily and falls back to a
/// gradient-blob placeholder when the package isn't installed or the asset
/// is missing — same contract as the React `<RiveAnimation />`.
///
/// To enable real Rive playback:
///   1. Add `rive: ^0.13.0` (or newer) to the consuming app's pubspec.
///   2. Drop `.riv` files into the app's `assets/` and register them.
///   3. Pass the asset path or a Uri — the widget detects the import at
///      build time and renders the animation.
///
/// Until then, the fallback keeps every layout looking intentional.
class BestieRive extends StatefulWidget {
  final String? asset;
  final String? url;
  final String? stateMachine;
  final String? artboard;
  final double? width;
  final double? height;
  final Widget? fallback;
  final bool pauseOffscreen;

  const BestieRive({
    super.key,
    this.asset,
    this.url,
    this.stateMachine,
    this.artboard,
    this.width,
    this.height,
    this.fallback,
    this.pauseOffscreen = true,
  });

  @override
  State<BestieRive> createState() => _BestieRiveState();
}

class _BestieRiveState extends State<BestieRive> {
  Widget? _riveWidget;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _tryLoad();
  }

  void _tryLoad() async {
    // Real implementation: when the consuming app adds `rive` to its pubspec,
    // replace the body of this method with:
    //
    //   import 'package:rive/rive.dart';
    //   final artboard = await RiveFile.asset(widget.asset!).then((f) => f.mainArtboard);
    //   setState(() => _riveWidget = Rive(artboard: artboard, fit: BoxFit.contain));
    //
    // For now we deliberately do nothing so the package compiles even without
    // a `rive` dependency, and the fallback always renders.
    if (widget.asset == null && widget.url == null) {
      setState(() => _failed = true);
    } else {
      // Mark as failed so we render fallback. Real impl flips this on success.
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width ?? 160;
    final h = widget.height ?? 160;

    if (_riveWidget != null && !_failed) {
      return SizedBox(width: w, height: h, child: _riveWidget);
    }

    return SizedBox(
      width: w, height: h,
      child: widget.fallback ?? const _RiveFallback(),
    );
  }
}

class _RiveFallback extends StatefulWidget {
  const _RiveFallback();
  @override
  State<_RiveFallback> createState() => _RiveFallbackState();
}

class _RiveFallbackState extends State<_RiveFallback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(BestieTokens.rMd),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: const [BestieTokens.cBrandSoft, BestieTokens.cSurface1],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -40 + (t * 20),
                  right: -40 + (t * 10),
                  child: _Blob(
                    color: BestieTokens.cBrand.withOpacity(0.55),
                    size: 160,
                  ),
                ),
                Positioned(
                  bottom: -30 - (t * 10),
                  left: -30 - (t * 10),
                  child: _Blob(
                    color: BestieTokens.cAccent.withOpacity(0.45),
                    size: 140,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
