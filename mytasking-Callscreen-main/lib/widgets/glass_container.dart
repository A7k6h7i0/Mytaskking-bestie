import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 16,
    this.borderColor,
    this.borderWidth = 1,
    this.glowColor,
    this.glowBlur = 0,
    this.glowSpread = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? borderColor;
  final double borderWidth;
  final Color? glowColor;
  final double glowBlur;
  final double glowSpread;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.glassFill,
                AppColors.glassFillDeep,
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ?? AppColors.glassBorder,
              width: borderWidth,
            ),
            boxShadow: glowColor != null && glowBlur > 0
                ? [
                    BoxShadow(
                      color: glowColor!,
                      blurRadius: glowBlur,
                      spreadRadius: glowSpread,
                    ),
                    BoxShadow(
                      color: glowColor!.withValues(alpha: 0.35),
                      blurRadius: glowBlur * 1.8,
                      spreadRadius: glowSpread + 1,
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
