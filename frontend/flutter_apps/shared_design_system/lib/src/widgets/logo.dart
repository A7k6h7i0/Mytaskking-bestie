import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../tokens.dart';

/// MyTaskKing — premium animated brand mark for Flutter.
///
/// A rounded gradient square with a stylized "checklist" mark — three white
/// task lines + a bold check on the first row — to match the MyTaskKing
/// productivity identity. Animated stroke-on for the lines, a corner accent
/// dot with a pulsing ring. `withWordmark` adds the MyTaskKing wordmark next
/// to the mark.
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
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
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
          SizedBox(width: widget.size * 0.30),
          DefaultTextStyle.merge(
            // Slightly tighter than before because "MyTaskKing" is longer
            // than "Bestie" — keep it from crowding the mark on small sizes.
            style: TextStyle(
              fontSize: widget.size * 0.42,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.015 * widget.size,
              height: 1.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (rect) => const LinearGradient(
                    colors: [BestieTokens.cAccent, BestieTokens.cBrand, Color(0xFF3AA1FF)],
                  ).createShader(rect),
                  child: const Text('MyTaskKing'),
                ),
                SizedBox(height: widget.size * 0.04),
                Text(
                  'Productivity',
                  style: TextStyle(
                    fontSize: widget.size * 0.22,
                    fontWeight: FontWeight.w600,
                    color: BestieTokens.cTextMuted,
                    letterSpacing: 0.06 * widget.size * 0.22,
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

    final sx = s / 48; // scale factor from our 48-unit canvas

    final stroke = Paint()
      ..color = Colors.white
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // ---- Checklist mark — three task rows with a bold check on the first ----
    Path topLine()    => Path()..moveTo(22 * sx, 15 * sx)..lineTo(36 * sx, 15 * sx);
    Path middleLine() => Path()..moveTo(22 * sx, 24 * sx)..lineTo(36 * sx, 24 * sx);
    Path bottomLine() => Path()..moveTo(22 * sx, 33 * sx)..lineTo(36 * sx, 33 * sx);
    // Checkmark for the first row, drawn as two strokes.
    Path checkBase() => Path()
      ..moveTo(11 * sx, 16 * sx)
      ..lineTo(15 * sx, 19 * sx);
    Path checkTip() => Path()
      ..moveTo(15 * sx, 19 * sx)
      ..lineTo(20 * sx, 12 * sx);
    // Empty bullets for rows 2 and 3 (small circles).
    void drawBullet(Offset c, double radius, double t) {
      if (t <= 0) return;
      canvas.drawCircle(
        c, radius,
        Paint()
          ..color = Colors.white.withOpacity(t)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.055,
      );
    }

    void drawSlice(Path p, double from, double to) {
      final t = ((draw - from) / (to - from)).clamp(0.0, 1.0);
      if (t == 0) return;
      for (final m in p.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * t), stroke);
      }
    }

    drawSlice(checkBase(),  0.05, 0.30);
    drawSlice(checkTip(),   0.20, 0.55);
    drawSlice(topLine(),    0.25, 0.55);
    drawBullet(Offset(13 * sx, 24 * sx), 2.4 * sx,
        ((draw - 0.45) / 0.20).clamp(0.0, 1.0));
    drawSlice(middleLine(), 0.50, 0.75);
    drawBullet(Offset(13 * sx, 33 * sx), 2.4 * sx,
        ((draw - 0.65) / 0.20).clamp(0.0, 1.0));
    drawSlice(bottomLine(), 0.70, 0.95);

    // Accent dot + ping ring (top-right corner).
    final dotCenter = Offset(40 * sx, 11 * sx);
    final dotRadius = 2.8 * sx;
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
