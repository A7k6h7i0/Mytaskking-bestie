import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class SmokyRingPainter extends CustomPainter {
  SmokyRingPainter({required this.rotation});

  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const colors = [
      AppColors.neonBlue,
      AppColors.neonPurple,
      AppColors.neonMagenta,
    ];

    for (var i = 0; i < 10; i++) {
      final startAngle = rotation + (i * math.pi / 5);
      final smokePaint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius + 6),
        startAngle,
        math.pi / 3.5,
        false,
        smokePaint,
      );
    }

    final ringRect = Rect.fromCircle(center: center, radius: radius);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..shader = SweepGradient(
        startAngle: rotation,
        endAngle: rotation + math.pi * 2,
        colors: const [
          AppColors.neonBlue,
          AppColors.neonPurple,
          AppColors.neonMagenta,
          AppColors.neonBlue,
        ],
      ).createShader(ringRect);

    canvas.drawCircle(center, radius, ringPaint);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = AppColors.neonPurple.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius, glowPaint);
  }

  @override
  bool shouldRepaint(covariant SmokyRingPainter oldDelegate) {
    return oldDelegate.rotation != rotation;
  }
}
