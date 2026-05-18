import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../tokens.dart';

/// Bestie — premium animated brand mark for Flutter.
///
/// Mirrors the React [Logo] visually: rounded gradient container, three
/// stroke-drawn ribbons that animate in on mount, a corner accent dot with a
/// pulsing ring. Use [withWordmark] for the brand+tagline layout, [ambient]
/// for the gentle floating hero variant.
class BestieLogo extends StatefulWidget {
  final double size;
  final bool withWordmark;
  final bool ambient;
  final VoidCallback? onTap;
  const BestieLogo({
    super.key,
    this.size = 36,
    this.withWordmark = false,
    this.ambient = false,
    this.onTap,
  });

  @override
  State<BestieLogo> createState() => _BestieLogoState();
}

class _BestieLogoState extends State<BestieLogo> with TickerProviderStateMixin {
  late final AnimationController _draw =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..forward();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);

  @override
  void dispose() {
    _draw.dispose();
    _pulse.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_draw, _pulse, _float]),
        builder: (_, __) {
          final lift = widget.ambient ? math.sin(_float.value * math.pi * 2) * 4 : 0.0;
          return Transform.translate(
            offset: Offset(0, lift),
            child: CustomPaint(painter: _LogoPainter(draw: _draw.value, pulse: _pulse.value)),
          );
        },
      ),
    );

    final inner = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        if (widget.withWordmark) ...[
          const SizedBox(width: 12),
          DefaultTextStyle.merge(
            style: TextStyle(fontSize: widget.size * 0.5, fontWeight: FontWeight.w800, letterSpacing: -0.02 * widget.size),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (rect) => const LinearGradient(
                    colors: [BestieTokens.cAccent, BestieTokens.cBrand, Color(0xFF3AA1FF)],
                  ).createShader(rect),
                  child: const Text('Bestie'),
                ),
                Text(
                  'Workspace',
                  style: TextStyle(
                    fontSize: widget.size * 0.24,
                    fontWeight: FontWeight.w600,
                    color: BestieTokens.cTextMuted,
                    letterSpacing: 0.04 * widget.size * 0.24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (widget.onTap == null) return inner;
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(padding: const EdgeInsets.all(2), child: inner),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double draw;     // 0..1 progress of the stroke-on
  final double pulse;    // 0..1 looping pulse (for ring)
  _LogoPainter({required this.draw, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final r = s * 0.25;
    // Rounded gradient container.
    final containerRect = Rect.fromLTWH(0, 0, s, s);
    final containerRRect = RRect.fromRectAndRadius(containerRect, Radius.circular(r));
    final gradient = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF7C5CFF), Color(0xFF5B8CFF), Color(0xFF3AA1FF)],
    ).createShader(containerRect);
    canvas.drawRRect(containerRRect, Paint()..shader = gradient);

    // Soft top-left gloss.
    final gloss = Path()
      ..moveTo(s * 0.04, s * 0.25)
      ..cubicTo(s * 0.04, s * 0.12, s * 0.12, s * 0.04, s * 0.25, s * 0.04)
      ..lineTo(s * 0.62, s * 0.04)
      ..quadraticBezierTo(s * 0.46, s * 0.29, s * 0.38, s * 0.54)
      ..quadraticBezierTo(s * 0.20, s * 0.62, s * 0.04, s * 0.46)
      ..close();
    canvas.drawPath(gloss, Paint()..color = Colors.white.withOpacity(0.14));

    // Ribbon strokes — stem, top loop, bottom loop, drawn sequentially.
    final stroke = Paint()
      ..color = Colors.white
      ..strokeWidth = s * 0.073
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final sx = s / 48; // scale factor from our 48-unit canvas
    Path stem() => Path()..moveTo(14 * sx, 13 * sx)..lineTo(14 * sx, 35 * sx);
    Path top()  => Path()
      ..moveTo(14 * sx, 13 * sx)
      ..lineTo(26 * sx, 13 * sx)
      ..arcToPoint(Offset(26 * sx, 23 * sx), radius: Radius.circular(5 * sx))
      ..lineTo(14 * sx, 23 * sx);
    Path bot()  => Path()
      ..moveTo(14 * sx, 23 * sx)
      ..lineTo(28 * sx, 23 * sx)
      ..arcToPoint(Offset(28 * sx, 33 * sx), radius: Radius.circular(5 * sx))
      ..lineTo(14 * sx, 33 * sx);

    void drawSlice(Path p, double from, double to) {
      // Animate by clamping the drawn fraction of the metric.
      final t = ((draw - from) / (to - from)).clamp(0.0, 1.0);
      if (t == 0) return;
      for (final m in p.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * t), stroke);
      }
    }

    drawSlice(stem(), 0.12, 0.40);
    drawSlice(top(),  0.30, 0.65);
    drawSlice(bot(),  0.50, 0.90);

    // Accent dot + ping ring.
    final dotCenter = Offset(37 * sx, 11 * sx);
    final dotRadius = 3 * sx;
    canvas.drawCircle(dotCenter, dotRadius, Paint()..color = Colors.white);

    final ringRadius = (5 * sx) * (0.7 + pulse * 1.3);
    final ringAlpha = (1 - pulse).clamp(0.0, 1.0);
    canvas.drawCircle(
      dotCenter,
      ringRadius,
      Paint()
        ..color = Colors.white.withOpacity(ringAlpha * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.draw != draw || old.pulse != pulse;
}
