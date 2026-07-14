import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../colors.dart';
import '../tokens.dart';
import '../motion.dart';

/// MyTaskKing — Flutter primitives. Mirrors the React design system so the same
/// design vocabulary (Badge, EmptyState, ConfirmDialog, Spinner, Tabs,
/// SuccessCheck, BottomSheet, Modal, SegmentedControl, ProgressRing, Toast)
/// is available on every surface.

// ---------------------------------------------------------------------------
// BADGE — tone × variant × size pill, mirrors web `<Badge>`.
// ---------------------------------------------------------------------------

enum BestieTone { neutral, brand, success, warning, danger, info, client, accent }
enum BestieVariant { soft, solid, outline }

class BestieBadge extends StatelessWidget {
  final Widget child;
  final BestieTone tone;
  final BestieVariant variant;
  final bool dot;
  final bool small;
  const BestieBadge({
    super.key,
    required this.child,
    this.tone = BestieTone.neutral,
    this.variant = BestieVariant.soft,
    this.dot = false,
    this.small = true,
  });

  Color _bg() {
    if (variant == BestieVariant.outline) return Colors.transparent;
    if (variant == BestieVariant.solid) return _solid(tone);
    return _soft(tone);
  }
  Color _fg() {
    if (variant == BestieVariant.solid) return BestieTokens.cTextInvert;
    return _solid(tone);
  }
  static Color _solid(BestieTone t) {
    switch (t) {
      case BestieTone.brand:   return BestieTokens.cBrandStrong;
      case BestieTone.success: return BestieTokens.cSuccess;
      case BestieTone.warning: return BestieTokens.cWarning;
      case BestieTone.danger:  return BestieTokens.cDanger;
      case BestieTone.info:    return BestieTokens.cInfo;
      case BestieTone.client:  return BestieTokens.cClient;
      case BestieTone.accent:  return BestieTokens.cAccent;
      default:                 return BestieTokens.cTextMuted;
    }
  }
  static Color _soft(BestieTone t) {
    switch (t) {
      case BestieTone.brand:   return BestieTokens.cBrandSoft;
      case BestieTone.success: return const Color(0xFFD9F5E8);
      case BestieTone.warning: return const Color(0xFFFDF1D6);
      case BestieTone.danger:  return const Color(0xFFFDE2E2);
      case BestieTone.info:    return const Color(0xFFD9EEFB);
      case BestieTone.client:  return BestieTokens.cClientSoft;
      case BestieTone.accent:  return const Color(0xFFECE5FF);
      default:                 return BestieTokens.cSurface2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = _fg();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 3 : 4),
      decoration: BoxDecoration(
        color: _bg(),
        borderRadius: BorderRadius.circular(BestieTokens.rPill),
        border: variant == BestieVariant.outline ? Border.all(color: fg) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          DefaultTextStyle.merge(
            style: TextStyle(
              color: fg,
              fontSize: small ? 10 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Auto-toned by workflow status word. Pairs with the same string the API uses.
class BestieStatusBadge extends StatelessWidget {
  final String status;
  final bool pulse;
  const BestieStatusBadge({super.key, required this.status, this.pulse = false});

  BestieTone get _tone {
    final k = status.toUpperCase();
    if (['ACTIVE', 'DONE', 'WON', 'SEEN', 'ACCEPTED'].contains(k))      return BestieTone.success;
    if (['IN_PROGRESS', 'REVIEW', 'CONTACTED', 'DELIVERED'].contains(k)) return BestieTone.info;
    if (['TODO', 'NEW', 'BACKLOG', 'RINGING'].contains(k))               return BestieTone.brand;
    if (['INTERESTED', 'FOLLOWUP', 'SENDING'].contains(k))               return BestieTone.warning;
    if (['CANCELLED','LOST','FAILED','MISSED','DECLINED','EXPIRED','SUSPENDED'].contains(k)) return BestieTone.danger;
    if (k == 'CLIENT')                                                   return BestieTone.client;
    return BestieTone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final dotChild = BestieBadge(tone: _tone, dot: true, child: Text(status.toUpperCase()));
    if (!pulse) return dotChild;
    return _wrapWithPulse(child: dotChild, color: BestieBadge._solid(_tone));
  }
}

// A tiny helper that adds a soft pulse glow around any widget — used by
// StatusBadge when pulse=true. Free function instead of a static extension
// (Dart doesn't support static methods on extensions of other types).
Widget _wrapWithPulse({required Widget child, required Color color}) {
  return Stack(alignment: Alignment.center, children: [
    Positioned.fill(
      child: Center(
        child: SizedBox(
          width: 40, height: 22,
          child: PulseDot(color: color.withOpacity(0.35), size: 22),
        ),
      ),
    ),
    child,
  ]);
}

// ---------------------------------------------------------------------------
// SPINNER — ring + dots + bars
// ---------------------------------------------------------------------------

enum BestieSpinnerVariant { ring, dots, bars }

class BestieSpinner extends StatefulWidget {
  final BestieSpinnerVariant variant;
  final double size;
  final Color? color;
  const BestieSpinner({super.key, this.variant = BestieSpinnerVariant.ring, this.size = 22, this.color});

  @override
  State<BestieSpinner> createState() => _BestieSpinnerState();
}

class _BestieSpinnerState extends State<BestieSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? BestieTokens.cBrand;
    if (widget.variant == BestieSpinnerVariant.dots) {
      return SizedBox(
        width: widget.size, height: widget.size * 0.4,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              final phase = ((_c.value + i * 0.15) % 1.0);
              final scale = 0.5 + math.sin(phase * math.pi).abs() * 0.5;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.size * 0.22,
                  height: widget.size * 0.22,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              );
            }),
          ),
        ),
      );
    }
    if (widget.variant == BestieSpinnerVariant.bars) {
      return SizedBox(
        width: widget.size, height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(4, (i) {
              final h = (0.3 + math.sin((_c.value + i * 0.1) * math.pi * 2).abs() * 0.7);
              return Container(
                width: widget.size * 0.18,
                height: widget.size * h,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              );
            }),
          ),
        ),
      );
    }
    return SizedBox(
      width: widget.size, height: widget.size,
      child: RotationTransition(
        turns: _c,
        child: CustomPaint(painter: _RingSpinnerPainter(color: color)),
      ),
    );
  }
}

class _RingSpinnerPainter extends CustomPainter {
  final Color color;
  _RingSpinnerPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.12;
    final rect = Offset.zero & size;
    final bg = Paint()..color = color.withOpacity(0.16)..style = PaintingStyle.stroke..strokeWidth = stroke;
    final fg = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round;
    canvas.drawCircle(rect.center, (size.shortestSide - stroke) / 2, bg);
    canvas.drawArc(
      Rect.fromCircle(center: rect.center, radius: (size.shortestSide - stroke) / 2),
      -math.pi / 2, math.pi * 1.4, false, fg,
    );
  }
  @override
  bool shouldRepaint(covariant _RingSpinnerPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// PROGRESS RING — circular percentage indicator
// ---------------------------------------------------------------------------

class BestieProgressRing extends StatelessWidget {
  final double value;        // 0..1
  final double size;
  final double thickness;
  final Color? color;
  final Widget? label;
  const BestieProgressRing({
    super.key,
    required this.value,
    this.size = 64,
    this.thickness = 6,
    this.color,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? BestieTokens.cBrand;
    return SizedBox(
      width: size, height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size.square(size),
          painter: _ProgressRingPainter(value: value.clamp(0, 1), color: c, thickness: thickness),
        ),
        if (label != null) DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          child: label!,
        ),
      ]),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double value;
  final Color color;
  final double thickness;
  _ProgressRingPainter({required this.value, required this.color, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - thickness) / 2,
    );
    canvas.drawCircle(rect.center, rect.shortestSide / 2,
        Paint()..color = BestieTokens.cSurface2..style = PaintingStyle.stroke..strokeWidth = thickness);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false,
        Paint()..color = color..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = thickness);
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter old) =>
      old.value != value || old.color != color || old.thickness != thickness;
}

// ---------------------------------------------------------------------------
// SUCCESS CHECK — drawn circle + check stroke
// ---------------------------------------------------------------------------

class BestieSuccessCheck extends StatefulWidget {
  final double size;
  final Color color;
  const BestieSuccessCheck({super.key, this.size = 64, this.color = BestieTokens.cSuccess});

  @override
  State<BestieSuccessCheck> createState() => _BestieSuccessCheckState();
}

class _BestieSuccessCheckState extends State<BestieSuccessCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 950))..forward();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size, height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final ring = (t * 1.7).clamp(0.0, 1.0);
          final tick = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
          return CustomPaint(painter: _CheckPainter(ring: ring, tick: tick, color: widget.color));
        },
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double ring, tick;
  final Color color;
  _CheckPainter({required this.ring, required this.tick, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.07;
    final radius = (size.shortestSide - stroke) / 2;
    final center = size.center(Offset.zero);
    final p = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, math.pi * 2 * ring, false, p);
    if (tick > 0) {
      final tickPath = Path()
        ..moveTo(size.width * 0.30, size.height * 0.55)
        ..lineTo(size.width * 0.46, size.height * 0.72)
        ..lineTo(size.width * 0.72, size.height * 0.42);
      for (final m in tickPath.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * tick), p);
      }
    }
  }
  @override
  bool shouldRepaint(covariant _CheckPainter old) =>
      old.ring != ring || old.tick != tick || old.color != color;
}

// ---------------------------------------------------------------------------
// EMPTY STATE
// ---------------------------------------------------------------------------

/// Centers [child] vertically inside scrollable / refresh bodies.
Widget bestieEmptyScrollable(BuildContext context, Widget child) {
  return LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(child: child),
      ),
    ),
  );
}

class BestieEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;
  final Color? iconColor;
  const BestieEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(BestieTokens.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: (iconColor ?? BestieTokens.cBrand).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: iconColor ?? BestieTokens.cBrand, size: 32),
          ),
          const SizedBox(height: BestieTokens.s3),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, textAlign: TextAlign.center,
                style: const TextStyle(color: BestieTokens.cTextMuted)),
          ],
          if (action != null) ...[
            const SizedBox(height: BestieTokens.s3),
            action!,
          ],
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        if (h.isFinite && h > 0) {
          return SizedBox(
            width: constraints.maxWidth,
            height: h,
            child: Center(child: content),
          );
        }
        return Center(child: content);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// SEGMENTED CONTROL
// ---------------------------------------------------------------------------

class BestieSegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  const BestieSegmentOption({required this.value, required this.label, this.icon});
}

class BestieSegmentedControl<T> extends StatelessWidget {
  final T value;
  final ValueChanged<T> onChanged;
  final List<BestieSegmentOption<T>> options;
  const BestieSegmentedControl({super.key, required this.value, required this.onChanged, required this.options});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: BestieTokens.cSurface2,
        borderRadius: BorderRadius.circular(BestieTokens.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final active = o.value == value;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Material(
              color: active ? BestieTokens.cSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(BestieTokens.rPill),
              elevation: active ? 1 : 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(BestieTokens.rPill),
                onTap: () => onChanged(o.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (o.icon != null) ...[Icon(o.icon, size: 14, color: active ? BestieTokens.cText : BestieTokens.cTextMuted), const SizedBox(width: 6)],
                      Text(o.label, style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13,
                        color: active ? BestieTokens.cText : BestieTokens.cTextMuted,
                      )),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CONFIRM DIALOG — async confirm() helper
// ---------------------------------------------------------------------------

Future<bool> bestieConfirm(
  BuildContext context, {
  required String title,
  String? description,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool dangerous = true,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BestieTokens.rMd)),
      title: Row(
        children: [
          Icon(
            dangerous ? Icons.warning_rounded : Icons.help_outline_rounded,
            color: dangerous ? BestieTokens.cDanger : BestieTokens.cBrand,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
      content: description != null ? Text(description) : null,
      actions: [
        TextButton(onPressed: () => Navigator.of(_).pop(false), child: Text(cancelLabel)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: dangerous ? BestieTokens.cDanger : BestieTokens.cBrand,
          ),
          onPressed: () => Navigator.of(_).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}

// ---------------------------------------------------------------------------
// TOAST — simple top-anchored snackbar replacement
// ---------------------------------------------------------------------------

enum BestieToastKind { success, error, info, warning }

void bestieToast(BuildContext context, String title, {String? body, BestieToastKind kind = BestieToastKind.info, Duration duration = const Duration(seconds: 3)}) {
  final color = switch (kind) {
    BestieToastKind.success => BestieTokens.cSuccess,
    BestieToastKind.error   => BestieTokens.cDanger,
    BestieToastKind.warning => BestieTokens.cWarning,
    BestieToastKind.info    => BestieTokens.cInfo,
  };
  final icon = switch (kind) {
    BestieToastKind.success => Icons.check_circle,
    BestieToastKind.error   => Icons.error,
    BestieToastKind.warning => Icons.warning_amber_rounded,
    BestieToastKind.info    => Icons.info,
  };
  // Pull theme-aware colors from BestieColors so dark mode renders bold
  // titles in white (not the cText pure-black token, which is invisible).
  final c = BestieColors.of(context);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: c.surface,
    elevation: 8,
    duration: duration,
    margin: const EdgeInsets.all(BestieTokens.s4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BestieTokens.rSm)),
    content: Row(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 14)),
          if (body != null) Text(body, style: TextStyle(color: c.textMuted, fontSize: 12)),
        ],
      )),
    ]),
  ));
}

// ---------------------------------------------------------------------------
// BOTTOM SHEET helper
// ---------------------------------------------------------------------------

Future<T?> bestieBottomSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.86),
        decoration: const BoxDecoration(
          color: BestieTokens.cSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(BestieTokens.rLg)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36, height: 4,
              decoration: BoxDecoration(color: BestieTokens.cBorderStrong, borderRadius: BorderRadius.circular(2)),
            ),
            if (title != null) Padding(
              padding: const EdgeInsets.fromLTRB(BestieTokens.s4, BestieTokens.s2, BestieTokens.s4, BestieTokens.s2),
              child: Row(children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 18)),
              ]),
            ),
            Flexible(child: builder(ctx)),
          ],
        ),
      ),
    ),
  );
}
