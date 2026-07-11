import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WhatsApp-style seamless doodle wallpaper for chat threads.
/// Drawn with [CustomPainter] so there are no image tiles or seams.
class BestieChatWallpaper extends StatelessWidget {
  const BestieChatWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.white),
        const CustomPaint(painter: _ChatDoodlePainter()),
        child,
      ],
    );
  }
}

class _ChatDoodlePainter extends CustomPainter {
  const _ChatDoodlePainter();

  static const _bg = Colors.white;
  static const _ink = Color(0xFF8D8178);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    final stroke = Paint()
      ..color = _ink.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const stepX = 78.0;
    const stepY = 74.0;
    const doodleSize = 17.0;

    for (var row = -1; row * stepY < size.height + stepY; row++) {
      final yBase = row * stepY + (row.isOdd ? stepY * 0.42 : stepY * 0.12);
      for (var col = -1; col * stepX < size.width + stepX; col++) {
        final xBase = col * stepX + (row.isOdd ? stepX * 0.38 : stepX * 0.08);
        final seed = row * 31 + col * 17;
        final jitterX = _hash(seed, 0) * 14 - 7;
        final jitterY = _hash(seed, 1) * 12 - 6;
        final rotation = (_hash(seed, 2) - 0.5) * 0.85;
        final kind = seed.abs() % 12;

        canvas.save();
        canvas.translate(xBase + jitterX, yBase + jitterY);
        canvas.rotate(rotation);
        _drawDoodle(canvas, stroke, kind, doodleSize);
        canvas.restore();
      }
    }
  }

  double _hash(int seed, int salt) {
    final n = math.sin((seed + salt * 97) * 12.9898) * 43758.5453;
    return n - n.floor();
  }

  void _drawDoodle(Canvas canvas, Paint paint, int kind, double s) {
    switch (kind) {
      case 0:
        _bubble(canvas, paint, s);
      case 1:
        _phone(canvas, paint, s);
      case 2:
        _clock(canvas, paint, s);
      case 3:
        _calendar(canvas, paint, s);
      case 4:
        _star(canvas, paint, s);
      case 5:
        _heart(canvas, paint, s);
      case 6:
        _camera(canvas, paint, s);
      case 7:
        _pin(canvas, paint, s);
      case 8:
        _pencil(canvas, paint, s);
      case 9:
        _plane(canvas, paint, s);
      case 10:
        _mic(canvas, paint, s);
      default:
        _smiley(canvas, paint, s);
    }
  }

  void _bubble(Canvas canvas, Paint paint, double s) {
    final r = Rect.fromCenter(center: Offset.zero, width: s * 1.5, height: s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(s * 0.22)),
      paint,
    );
    final tail = Path()
      ..moveTo(-s * 0.45, s * 0.42)
      ..lineTo(-s * 0.62, s * 0.72)
      ..lineTo(-s * 0.18, s * 0.48);
    canvas.drawPath(tail, paint);
  }

  void _phone(Canvas canvas, Paint paint, double s) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0, 1), width: s * 0.95, height: s * 1.45),
      Radius.circular(s * 0.22),
    );
    canvas.drawRRect(body, paint);
    canvas.drawLine(Offset(-s * 0.22, -s * 0.55), Offset(s * 0.22, -s * 0.55), paint);
    canvas.drawLine(Offset(-s * 0.22, s * 0.62), Offset(s * 0.22, s * 0.62), paint);
  }

  void _clock(Canvas canvas, Paint paint, double s) {
    canvas.drawCircle(Offset.zero, s * 0.72, paint);
    canvas.drawLine(Offset.zero, Offset(0, -s * 0.35), paint);
    canvas.drawLine(Offset.zero, Offset(s * 0.28, s * 0.12), paint);
  }

  void _calendar(Canvas canvas, Paint paint, double s) {
    final r = Rect.fromCenter(center: Offset.zero, width: s * 1.35, height: s * 1.2);
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(s * 0.12)), paint);
    canvas.drawLine(Offset(-s * 0.55, -s * 0.2), Offset(s * 0.55, -s * 0.2), paint);
    canvas.drawLine(Offset(-s * 0.28, -s * 0.55), Offset(-s * 0.28, -s * 0.32), paint);
    canvas.drawLine(Offset(s * 0.28, -s * 0.55), Offset(s * 0.28, -s * 0.32), paint);
  }

  void _star(Canvas canvas, Paint paint, double s) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final outer = i * math.pi * 2 / 5 - math.pi / 2;
      final inner = outer + math.pi / 5;
      path.lineTo(math.cos(outer) * s * 0.72, math.sin(outer) * s * 0.72);
      path.lineTo(math.cos(inner) * s * 0.3, math.sin(inner) * s * 0.3);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _heart(Canvas canvas, Paint paint, double s) {
    final path = Path()
      ..moveTo(0, s * 0.35)
      ..cubicTo(-s * 0.9, -s * 0.15, -s * 0.55, -s * 0.75, 0, -s * 0.35)
      ..cubicTo(s * 0.55, -s * 0.75, s * 0.9, -s * 0.15, 0, s * 0.35);
    canvas.drawPath(path, paint);
  }

  void _camera(Canvas canvas, Paint paint, double s) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0, 0.5), width: s * 1.5, height: s),
      Radius.circular(s * 0.15),
    );
    canvas.drawRRect(body, paint);
    canvas.drawCircle(const Offset(0, 0.5), s * 0.28, paint);
    canvas.drawLine(Offset(-s * 0.35, -s * 0.05), Offset(s * 0.35, -s * 0.05), paint);
  }

  void _pin(Canvas canvas, Paint paint, double s) {
    final path = Path()
      ..moveTo(0, -s * 0.75)
      ..cubicTo(s * 0.55, -s * 0.35, s * 0.55, s * 0.35, 0, s * 0.75)
      ..cubicTo(-s * 0.55, s * 0.35, -s * 0.55, -s * 0.35, 0, -s * 0.75);
    canvas.drawPath(path, paint);
    canvas.drawCircle(Offset.zero, s * 0.22, paint);
  }

  void _pencil(Canvas canvas, Paint paint, double s) {
    canvas.drawLine(Offset(-s * 0.55, s * 0.55), Offset(s * 0.55, -s * 0.55), paint);
    final tip = Path()
      ..moveTo(s * 0.55, -s * 0.55)
      ..lineTo(s * 0.72, -s * 0.72)
      ..lineTo(s * 0.38, -s * 0.72);
    canvas.drawPath(tip, paint);
  }

  void _plane(Canvas canvas, Paint paint, double s) {
    final path = Path()
      ..moveTo(-s * 0.7, 0)
      ..lineTo(s * 0.75, -s * 0.15)
      ..lineTo(s * 0.2, 0)
      ..lineTo(s * 0.75, s * 0.15)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _mic(Canvas canvas, Paint paint, double s) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, -s * 0.1), width: s * 0.45, height: s * 0.85),
        Radius.circular(s * 0.22),
      ),
      paint,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(0, s * 0.2), width: s * 0.9, height: s * 0.9),
      0,
      math.pi,
      false,
      paint,
    );
    canvas.drawLine(Offset(0, s * 0.65), Offset(0, s * 0.85), paint);
    canvas.drawLine(Offset(-s * 0.25, s * 0.85), Offset(s * 0.25, s * 0.85), paint);
  }

  void _smiley(Canvas canvas, Paint paint, double s) {
    canvas.drawCircle(Offset.zero, s * 0.72, paint);
    final fill = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(-s * 0.22, -s * 0.12), s * 0.06, fill);
    canvas.drawCircle(Offset(s * 0.22, -s * 0.12), s * 0.06, fill);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(0, s * 0.05), width: s * 0.55, height: s * 0.35),
      0.15,
      math.pi - 0.3,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ChatDoodlePainter oldDelegate) => false;
}
