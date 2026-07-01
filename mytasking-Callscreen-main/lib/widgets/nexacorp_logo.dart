import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class NexacorpLogo extends StatelessWidget {
  const NexacorpLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.neonBlue,
            AppColors.neonPurple,
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x6600D2FF),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.55, size * 0.62),
          painter: _ShieldNPainter(),
        ),
      ),
    );
  }
}

class _ShieldNPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final shieldPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final path = Path()
      ..moveTo(size.width * 0.5, size.height * 0.02)
      ..lineTo(size.width * 0.95, size.height * 0.18)
      ..lineTo(size.width * 0.82, size.height * 0.88)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 1.02,
        size.width * 0.18,
        size.height * 0.88,
      )
      ..lineTo(size.width * 0.05, size.height * 0.18)
      ..close();

    canvas.drawPath(path, shieldPaint);

    final letterPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final nPath = Path()
      ..moveTo(size.width * 0.28, size.height * 0.78)
      ..lineTo(size.width * 0.28, size.height * 0.28)
      ..lineTo(size.width * 0.42, size.height * 0.58)
      ..lineTo(size.width * 0.56, size.height * 0.28)
      ..lineTo(size.width * 0.56, size.height * 0.78)
      ..lineTo(size.width * 0.48, size.height * 0.78)
      ..lineTo(size.width * 0.48, size.height * 0.42)
      ..lineTo(size.width * 0.36, size.height * 0.72)
      ..lineTo(size.width * 0.36, size.height * 0.78)
      ..close();

    canvas.drawPath(nPath, letterPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
