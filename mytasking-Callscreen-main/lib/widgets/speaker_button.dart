import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'gradient_icon.dart';

class SpeakerButton extends StatelessWidget {
  const SpeakerButton({
    super.key,
    this.isSelected = false,
    this.onTap,
  });

  final bool isSelected;
  final VoidCallback? onTap;

  static const _radius = 18.0;
  static const _innerRadius = 16.2;

  static const _idleFaceGradient = RadialGradient(
    center: Alignment(-0.15, -0.25),
    radius: 1.05,
    colors: [
      AppColors.speakerFaceHighlight,
      AppColors.speakerBackground,
      AppColors.speakerFaceShadow,
    ],
    stops: [0.0, 0.55, 1.0],
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
                    blurRadius: 14,
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: AppColors.speakerGlowSoft,
                    blurRadius: 26,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_radius),
                child: Container(
                  padding: const EdgeInsets.all(1.8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.speakerActiveBorder,
                        AppColors.speakerBorderSide,
                        AppColors.speakerBorderDim,
                        AppColors.speakerBorderSide,
                      ],
                      stops: [0.0, 0.35, 0.7, 1.0],
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_innerRadius),
                    child: Container(
                      decoration: _innerDecoration,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GradientIcon(
                            icon: Icons.volume_up_rounded,
                            size: 34,
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                            colors: const [
                              AppColors.textPrimary,
                              AppColors.speakerIconShadow,
                              AppColors.textPrimary,
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Speaker',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.0,
                              letterSpacing: 0.15,
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
            'Speaker',
            style: TextStyle(fontSize: 9.5, height: 1.1),
          ),
        ),
      ],
    );
  }
}
