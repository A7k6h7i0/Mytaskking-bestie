import 'package:flutter/material.dart';

/// Bestie — motion contract.
///
/// Mirrors the React motion.css naming so cross-platform UX feels identical:
///   m-fade-up  → BestieMotion.fadeUp
///   m-pop      → BestieMotion.pop
///   m-shake    → BestieMotion.shake
///   m-stagger  → StaggeredColumn / StaggeredWrap
///
/// Curves and durations come from [BestieTokens] so swapping the design
/// language flips both web and Flutter together. Reduced-motion respects
/// `MediaQuery.disableAnimationsOf(context)` and resolves animations to a
/// single frame.
class BestieMotion {
  // ----- durations -----
  static const fast    = Duration(milliseconds: 120);
  static const base    = Duration(milliseconds: 200);
  static const slow    = Duration(milliseconds: 360);
  static const slower  = Duration(milliseconds: 600);

  // ----- curves -----
  static const ease       = Cubic(0.2, 0.8, 0.2, 1.0);     // matches --ease
  static const easeSpring = Cubic(0.34, 1.56, 0.64, 1.0);  // matches --ease-spring
  static const easeEmphasized = Cubic(0.4, 0.0, 0.2, 1.0);
}

/// Honors the system "reduce motion" toggle. Wrap entrance animations with
/// `BestieMotion.respect(context, () => ...)` to skip them when the user
/// has reduced-motion on.
extension BestieMotionContext on BuildContext {
  bool get reduceMotion => MediaQuery.maybeOf(this)?.disableAnimations ?? false;
}

/// Plays [child] in with a fade + small upward translate. Cheap, premium-
/// looking entrance — use for first-paint of cards, list rows, panels.
class FadeIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Offset from;
  const FadeIn({
    super.key,
    required this.child,
    this.duration = BestieMotion.base,
    this.delay = Duration.zero,
    this.from = const Offset(0, 8),
  });

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () { if (mounted) _c.forward(); });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;
    final eased = CurvedAnimation(parent: _c, curve: BestieMotion.ease);
    return AnimatedBuilder(
      animation: eased,
      builder: (_, child) {
        final t = eased.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(widget.from.dx * (1 - t), widget.from.dy * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Bouncy scale-in. Use for success badges, modal entrances, attention pops.
class PopIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  const PopIn({ super.key, required this.child, this.duration = BestieMotion.slow });

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)..forward();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;
    return ScaleTransition(
      scale: CurvedAnimation(parent: _c, curve: BestieMotion.easeSpring),
      child: FadeTransition(opacity: _c, child: widget.child),
    );
  }
}

/// Sequenced fade-up for children of a column. Match React's `.m-stagger`.
///
///   StaggeredColumn(
///     children: [...],   // each child gets a 60ms-staggered fade-up
///   )
class StaggeredColumn extends StatelessWidget {
  final List<Widget> children;
  final Duration stagger;
  final Duration duration;
  final CrossAxisAlignment crossAxisAlignment;
  const StaggeredColumn({
    super.key,
    required this.children,
    this.stagger = const Duration(milliseconds: 60),
    this.duration = BestieMotion.base,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: List.generate(children.length, (i) {
        return FadeIn(
          duration: duration,
          delay: stagger * i,
          child: children[i],
        );
      }),
    );
  }
}

/// Pulsing dot — used for "live" indicators and unread badges. Honors
/// reduced motion by rendering a static colored dot.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({ super.key, required this.color, this.size = 8 });

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size, height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (context.reduceMotion) return dot;
    return Stack(alignment: Alignment.center, children: [
      AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return Opacity(
            opacity: (1 - _c.value) * 0.7,
            child: Container(
              width: widget.size * (1 + _c.value),
              height: widget.size * (1 + _c.value),
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
            ),
          );
        },
      ),
      dot,
    ]);
  }
}

/// Tweens an integer counter from its previous value to the new one. Mirrors
/// the React `<AnimatedNumber>`.
class AnimatedCounter extends StatefulWidget {
  final num value;
  final TextStyle? style;
  final Duration duration;
  final String Function(num)? format;
  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 800),
    this.format,
  });

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  num _prev = 0;

  @override
  void initState() {
    super.initState();
    _prev = widget.value;
    _c = AnimationController(vsync: this, duration: widget.duration);
    _a = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant AnimatedCounter old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _prev = old.value;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) {
      return Text(_render(widget.value), style: widget.style);
    }
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) {
        final v = _prev + (widget.value - _prev) * _a.value;
        return Text(_render(v), style: widget.style);
      },
    );
  }

  String _render(num v) =>
      widget.format != null ? widget.format!(v) : v.round().toString();
}

/// Shake animation — for error states. Call `controller.forward(from: 0)` to
/// trigger. Honors reduced motion (resolves to a no-op).
class ShakeAnimation extends StatelessWidget {
  final Animation<double> controller;
  final Widget child;
  final double amplitude;
  const ShakeAnimation({
    super.key,
    required this.controller,
    required this.child,
    this.amplitude = 6,
  });

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    return AnimatedBuilder(
      animation: controller,
      builder: (_, c) {
        // 4 horizontal oscillations over the curve.
        final dx = amplitude * (1 - controller.value) *
            (controller.value == 0 ? 0 : (controller.value * 12).remainder(1) - 0.5) * 2;
        return Transform.translate(offset: Offset(dx, 0), child: c);
      },
      child: child,
    );
  }
}
