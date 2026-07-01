import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class RecordCallButton extends StatelessWidget {
  const RecordCallButton({
    super.key,
    this.isSelected = false,
    this.onTap,
  });

  final bool isSelected;
  final VoidCallback? onTap;

  static const _radius = 18.0;
  static const _innerRadius = 16.4;

  static const _idleFaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.recordBackground,
      Color(0xE6050A1E),
    ],
  );

  static const _selectedFaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.recordSelectedFillTop,
      AppColors.recordSelectedFillBottom,
    ],
  );

  BoxDecoration get _innerDecoration => BoxDecoration(
        gradient: isSelected ? _selectedFaceGradient : _idleFaceGradient,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.recordGlowStrong,
                    blurRadius: 16,
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: AppColors.recordGlowSoft,
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_radius),
                child: Container(
                  padding: const EdgeInsets.all(1.6),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.recordBorderFaded,
                        AppColors.recordBorderMid,
                        AppColors.recordRed,
                        AppColors.recordMagenta,
                      ],
                      stops: [0.0, 0.35, 0.72, 1.0],
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_innerRadius),
                    child: Container(
                      decoration: _innerDecoration,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          _RecordIcon(size: 34),
                          SizedBox(height: 8),
                          Text(
                            'Record Call',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.0,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        const Opacity(
          opacity: 0,
          child: Text(
            'Record Call',
            style: TextStyle(fontSize: 9.5, height: 1.1),
          ),
        ),
      ],
    );
  }
}

class _RecordIcon extends StatelessWidget {
  const _RecordIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _RecordIconPainter(),
    );
  }
}

class _RecordIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const color = AppColors.recordRed;

    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, size.width * 0.38, ringPaint);
    canvas.drawCircle(center, size.width * 0.16, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
