import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'gradient_icon.dart';

class GlassControlButton extends StatelessWidget {
  const GlassControlButton({
    super.key,
    required this.label,
    required this.icon,
    this.iconGradient,
    this.isSelected = false,
    this.onTap,
    this.iconBegin = Alignment.topCenter,
    this.iconEnd = Alignment.bottomCenter,
  });

  final String label;
  final IconData icon;
  final List<Color>? iconGradient;
  final bool isSelected;
  final VoidCallback? onTap;
  final AlignmentGeometry iconBegin;
  final AlignmentGeometry iconEnd;

  static const _radius = 18.0;
  static const _innerRadius = 16.4;

  static const _borderGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.speakerActiveBorder,
      AppColors.speakerBorderSide,
      AppColors.speakerBorderSide,
      AppColors.speakerActiveBorder,
    ],
    stops: [0.0, 0.28, 0.72, 1.0],
  );

  static const _idleFaceGradient = RadialGradient(
    center: Alignment(-0.1, -0.15),
    radius: 1.0,
    colors: [
      AppColors.speakerFaceHighlight,
      AppColors.speakerBackground,
    ],
  );

  static const _selectedFaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.buttonSelectedFillTop,
      AppColors.buttonSelectedFillBottom,
    ],
  );

  BoxDecoration get _innerDecoration => BoxDecoration(
        gradient: isSelected ? _selectedFaceGradient : _idleFaceGradient,
      );

  Widget _buildIcon() {
    if (iconGradient != null) {
      return GradientIcon(
        icon: icon,
        size: 30,
        begin: iconBegin,
        end: iconEnd,
        colors: iconGradient!,
      );
    }

    return GradientIcon(
      icon: icon,
      size: 30,
      begin: iconBegin,
      end: iconEnd,
      colors: const [
        AppColors.textPrimary,
        AppColors.textSecondary,
      ],
    );
  }

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
                    color: AppColors.speakerGlowStrong,
                    blurRadius: 18,
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: AppColors.speakerGlowSoft,
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
                    gradient: _borderGradient,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_innerRadius),
                    child: Container(
                      decoration: _innerDecoration,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildIcon(),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: label.length > 12 ? 8.5 : 10,
                                fontWeight: FontWeight.w600,
                                height: 1.05,
                                letterSpacing: 0.05,
                              ),
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
        Opacity(
          opacity: 0,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 9.5, height: 1.1),
          ),
        ),
      ],
    );
  }
}
