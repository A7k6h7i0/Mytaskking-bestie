import 'dart:math' as math;

import 'package:flutter/material.dart';

class AudioWavePainter extends CustomPainter {
  AudioWavePainter({
    required this.color,
    required this.flip,
    this.phase = 0,
  });

  final Color color;
  final bool flip;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 16;
    const barWidth = 4.0;
    const gap = 3.5;
    final centerY = size.height / 2;

    for (var i = 0; i < barCount; i++) {
      final index = flip ? (barCount - 1 - i) : i;
      final progress = index / (barCount - 1);
      final wave = math.sin((progress * math.pi * 1.8) + phase);
      final pulse = 0.55 + (0.45 * ((wave + 1) / 2));
      final heightFactor = (0.18 + (0.82 * progress)) * pulse;
      final barHeight = size.height * heightFactor.clamp(0.12, 1.0);

      final x = i * (barWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, centerY),
          width: barWidth,
          height: barHeight,
        ),
        const Radius.circular(2),
      );

      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawRRect(rect, glowPaint);

      final barPaint = Paint()..color = color;
      canvas.drawRRect(rect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant AudioWavePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.color != color ||
        oldDelegate.flip != flip;
  }
}
