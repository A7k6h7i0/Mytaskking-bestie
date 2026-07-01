import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

abstract final class CallScreenUiColors {
  static const backgroundTop = Color(0xFF050A18);
  static const backgroundMid = Color(0xFF0B1530);
  static const backgroundBottom = Color(0xFF1A0B2E);

  static const neonBlue = Color(0xFF00D2FF);
  static const speakerActiveBorder = Color(0xFF00E5FF);
  static const speakerBorderSide = Color(0x5500E5FF);
  static const speakerBorderDim = Color(0x3300E5FF);
  static const speakerBackground = Color(0xFF0A192F);
  static const speakerFaceHighlight = Color(0xFF152847);
  static const speakerFaceShadow = Color(0xFF050A14);
  static const speakerIconShadow = Color(0xFF8FA3BC);
  static const speakerGlowStrong = Color(0x8000E5FF);
  static const speakerGlowSoft = Color(0x4400D4FF);
  static const neonPurple = Color(0xFF9D50BB);
  static const neonMagenta = Color(0xFFB24BF3);
  static const neonGreen = Color(0xFF2ECC71);
  static const endCallRed = Color(0xFFFF4B5C);
  static const recordRed = Color(0xFFFF2D55);
  static const recordMagenta = Color(0xFFE91E63);
  static const recordBackground = Color(0xFF050A1E);
  static const recordBorderFaded = Color(0x33FF2D55);
  static const recordBorderMid = Color(0x88FF2D55);
  static const recordGlowStrong = Color(0x66FF2D55);
  static const recordGlowSoft = Color(0x44FF2D55);
  static const verifiedBlue = Color(0xFF4DA3FF);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB8C4D9);
  static const textMuted = Color(0xFF7A8BA8);

  static const glassFill = Color(0x1AFFFFFF);
  static const glassFillDeep = Color(0x0DFFFFFF);
  static const glassBorder = Color(0x33FFFFFF);

  static const buttonSelectedFillTop = Color(0x7000E5FF);
  static const buttonSelectedFillBottom = Color(0x4500E5FF);
  static const recordSelectedFillTop = Color(0x70FF2D55);
  static const recordSelectedFillBottom = Color(0x45E91E63);
}

class CallUiGradientIcon extends StatelessWidget {
  const CallUiGradientIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  final IconData icon;
  final double size;
  final List<Color> colors;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: begin,
        end: end,
        colors: colors,
      ).createShader(bounds),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }
}

class CallUiGlassContainer extends StatelessWidget {
  const CallUiGlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 16,
    this.borderColor,
    this.borderWidth = 1,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                CallScreenUiColors.glassFill,
                CallScreenUiColors.glassFillDeep,
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ?? CallScreenUiColors.glassBorder,
              width: borderWidth,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class CallUiGlassControlButton extends StatelessWidget {
  const CallUiGlassControlButton({
    super.key,
    required this.label,
    required this.icon,
    this.iconGradient,
    this.isSelected = false,
    this.onTap,
    this.iconBegin = Alignment.topCenter,
    this.iconEnd = Alignment.bottomCenter,
    this.lightControls = false,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final List<Color>? iconGradient;
  final bool isSelected;
  final VoidCallback? onTap;
  final AlignmentGeometry iconBegin;
  final AlignmentGeometry iconEnd;
  /// Light app theme: white borders/shadows instead of neon blue on Mute–Buzzer.
  final bool lightControls;
  final bool compact;

  static const _radius = 18.0;
  static const _innerRadius = 16.4;

  static const _borderGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      CallScreenUiColors.speakerActiveBorder,
      CallScreenUiColors.speakerBorderSide,
      CallScreenUiColors.speakerBorderSide,
      CallScreenUiColors.speakerActiveBorder,
    ],
    stops: [0.0, 0.28, 0.72, 1.0],
  );

  static const _lightBorderGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFFFFFF),
      Color(0x99FFFFFF),
      Color(0x99FFFFFF),
      Color(0xFFFFFFFF),
    ],
    stops: [0.0, 0.28, 0.72, 1.0],
  );

  static const _lightGlowShadows = [
    BoxShadow(
      color: Color(0x80FFFFFF),
      blurRadius: 18,
    ),
    BoxShadow(
      color: Color(0x44FFFFFF),
      blurRadius: 28,
      spreadRadius: 1,
    ),
  ];

  static const _idleFaceGradient = RadialGradient(
    center: Alignment(-0.1, -0.15),
    radius: 1.0,
    colors: [
      CallScreenUiColors.speakerFaceHighlight,
      CallScreenUiColors.speakerBackground,
    ],
  );

  static const _selectedFaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      CallScreenUiColors.buttonSelectedFillTop,
      CallScreenUiColors.buttonSelectedFillBottom,
    ],
  );

  BoxDecoration get _innerDecoration => BoxDecoration(
        gradient: isSelected ? _selectedFaceGradient : _idleFaceGradient,
      );

  Widget _buildIcon() {
    if (iconGradient != null) {
      return CallUiGradientIcon(
        icon: icon,
        size: compact ? 24 : 30,
        begin: iconBegin,
        end: iconEnd,
        colors: iconGradient!,
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final outerRadius = compact ? 15.5 : _radius;
    final innerRadius = compact ? 14.2 : _innerRadius;
    final iconSize = compact ? 24.0 : 30.0;
    final labelSize = compact ? 8.5 : (label.length > 12 ? 8.5 : 10.0);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(outerRadius),
                  boxShadow: lightControls
                      ? _lightGlowShadows
                      : const [
                          BoxShadow(
                            color: CallScreenUiColors.speakerGlowStrong,
                            blurRadius: 18,
                          ),
                          BoxShadow(
                            color: CallScreenUiColors.speakerGlowSoft,
                            blurRadius: 28,
                            spreadRadius: 1,
                          ),
                        ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(outerRadius),
                  child: Container(
                    padding: EdgeInsets.all(compact ? 1.2 : 1.6),
                    decoration: BoxDecoration(
                      gradient: lightControls
                          ? _lightBorderGradient
                          : _borderGradient,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(innerRadius),
                      child: Container(
                        decoration: _innerDecoration,
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 3 : 4,
                          vertical: compact ? 4 : 6,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (iconGradient != null)
                              _buildIcon()
                            else
                              CallUiGradientIcon(
                                icon: icon,
                                size: iconSize,
                                begin: iconBegin,
                                end: iconEnd,
                                colors: const [
                                  CallScreenUiColors.textPrimary,
                                  CallScreenUiColors.textSecondary,
                                ],
                              ),
                            SizedBox(height: compact ? 4 : 6),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: TextStyle(
                                  color: CallScreenUiColors.textPrimary,
                                  fontSize: labelSize,
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
          const Opacity(
            opacity: 0,
            child: Text(
              'Spacer',
              style: TextStyle(fontSize: 9.5, height: 1.1),
            ),
          ),
        ],
      ),
    );
  }
}

class CallUiSpeakerButton extends StatelessWidget {
  const CallUiSpeakerButton({
    super.key,
    this.isSelected = false,
    this.onTap,
    this.lightControls = false,
    this.compact = false,
  });

  final bool isSelected;
  final VoidCallback? onTap;
  final bool lightControls;
  final bool compact;

  static const _radius = 18.0;
  static const _innerRadius = 16.2;

  static const _idleFaceGradient = RadialGradient(
    center: Alignment(-0.15, -0.25),
    radius: 1.05,
    colors: [
      CallScreenUiColors.speakerFaceHighlight,
      CallScreenUiColors.speakerBackground,
      CallScreenUiColors.speakerFaceShadow,
    ],
    stops: [0.0, 0.55, 1.0],
  );

  static const _selectedFaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      CallScreenUiColors.buttonSelectedFillTop,
      CallScreenUiColors.buttonSelectedFillBottom,
    ],
  );

  BoxDecoration get _innerDecoration => BoxDecoration(
        gradient: isSelected ? _selectedFaceGradient : _idleFaceGradient,
      );

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final outerRadius = compact ? 15.5 : _radius;
    final innerRadius = compact ? 14.0 : _innerRadius;
    final iconSize = compact ? 28.0 : 34.0;
    final labelSize = compact ? 8.5 : 11.0;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(outerRadius),
                  boxShadow: lightControls
                      ? CallUiGlassControlButton._lightGlowShadows
                      : const [
                          BoxShadow(
                            color: CallScreenUiColors.speakerGlowStrong,
                            blurRadius: 14,
                          ),
                          BoxShadow(
                            color: CallScreenUiColors.speakerGlowSoft,
                            blurRadius: 26,
                            spreadRadius: 1,
                          ),
                        ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(outerRadius),
                  child: Container(
                    padding: EdgeInsets.all(compact ? 1.3 : 1.8),
                    decoration: BoxDecoration(
                      gradient: lightControls
                          ? CallUiGlassControlButton._lightBorderGradient
                          : const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                CallScreenUiColors.speakerActiveBorder,
                                CallScreenUiColors.speakerBorderSide,
                                CallScreenUiColors.speakerBorderDim,
                                CallScreenUiColors.speakerBorderSide,
                              ],
                              stops: [0.0, 0.35, 0.7, 1.0],
                            ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(innerRadius),
                      child: Container(
                        decoration: _innerDecoration,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CallUiGradientIcon(
                              icon: Icons.volume_up_rounded,
                              size: iconSize,
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: const [
                                CallScreenUiColors.textPrimary,
                                CallScreenUiColors.speakerIconShadow,
                                CallScreenUiColors.textPrimary,
                              ],
                            ),
                            SizedBox(height: compact ? 5 : 8),
                            Text(
                              'Speaker',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: CallScreenUiColors.textPrimary,
                                fontSize: labelSize,
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
      ),
    );
  }
}

class CallUiRecordButton extends StatelessWidget {
  const CallUiRecordButton({
    super.key,
    this.isSelected = false,
    this.onTap,
    this.compact = false,
  });

  final bool isSelected;
  final VoidCallback? onTap;
  final bool compact;

  static const _radius = 18.0;
  static const _innerRadius = 16.4;

  static const _idleFaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      CallScreenUiColors.recordBackground,
      Color(0xE6050A1E),
    ],
  );

  static const _selectedFaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      CallScreenUiColors.recordSelectedFillTop,
      CallScreenUiColors.recordSelectedFillBottom,
    ],
  );

  BoxDecoration get _innerDecoration => BoxDecoration(
        gradient: isSelected ? _selectedFaceGradient : _idleFaceGradient,
      );

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final outerRadius = compact ? 15.5 : _radius;
    final innerRadius = compact ? 14.2 : _innerRadius;
    final iconSize = compact ? 28.0 : 34.0;
    final labelSize = compact ? 8.5 : 11.0;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(outerRadius),
                  boxShadow: const [
                    BoxShadow(
                      color: CallScreenUiColors.recordGlowStrong,
                      blurRadius: 16,
                    ),
                    BoxShadow(
                      color: CallScreenUiColors.recordGlowSoft,
                      blurRadius: 28,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(outerRadius),
                  child: Container(
                    padding: EdgeInsets.all(compact ? 1.2 : 1.6),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          CallScreenUiColors.recordBorderFaded,
                          CallScreenUiColors.recordBorderMid,
                          CallScreenUiColors.recordRed,
                          CallScreenUiColors.recordMagenta,
                        ],
                        stops: [0.0, 0.35, 0.72, 1.0],
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(innerRadius),
                      child: Container(
                        decoration: _innerDecoration,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _CallUiRecordIcon(size: iconSize),
                            SizedBox(height: compact ? 5 : 8),
                            Text(
                              'Record Call',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: CallScreenUiColors.textPrimary,
                                fontSize: labelSize,
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
      ),
    );
  }
}

class _CallUiRecordIcon extends StatelessWidget {
  const _CallUiRecordIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _CallUiRecordIconPainter(),
    );
  }
}

class _CallUiRecordIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const color = CallScreenUiColors.recordRed;

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

class CallUiBottomActionButton extends StatelessWidget {
  const CallUiBottomActionButton({
    super.key,
    required this.icon,
    required this.size,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final double size;
  final VoidCallback? onTap;
  final bool compact;

  static const _borderGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      CallScreenUiColors.speakerActiveBorder,
      CallScreenUiColors.speakerBorderSide,
      CallScreenUiColors.speakerBorderSide,
      CallScreenUiColors.speakerActiveBorder,
    ],
    stops: [0.0, 0.28, 0.72, 1.0],
  );

  static const _faceGradient = RadialGradient(
    center: Alignment(-0.1, -0.15),
    radius: 1.0,
    colors: [
      CallScreenUiColors.speakerFaceHighlight,
      CallScreenUiColors.speakerBackground,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final borderPadding = compact ? 1.2 : 1.6;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: CallScreenUiColors.speakerGlowStrong,
                blurRadius: 18,
              ),
              BoxShadow(
                color: CallScreenUiColors.speakerGlowSoft,
                blurRadius: 28,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipOval(
            child: Container(
              padding: EdgeInsets.all(borderPadding),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: _borderGradient,
              ),
              child: ClipOval(
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _faceGradient,
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      color: CallScreenUiColors.textPrimary,
                      size: size * 0.42,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CallUiBrandLogo extends StatelessWidget {
  const CallUiBrandLogo({super.key, this.size = 34});

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
            CallScreenUiColors.neonBlue,
            CallScreenUiColors.neonPurple,
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x6600D2FF),
            blurRadius: 12,
          ),
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.55, size * 0.62),
          painter: _CallUiShieldPainter(),
        ),
      ),
    );
  }
}

class _CallUiShieldPainter extends CustomPainter {
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

class CallUiSmokyRingPainter extends CustomPainter {
  const CallUiSmokyRingPainter({required this.rotation});

  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const colors = [
      CallScreenUiColors.neonBlue,
      CallScreenUiColors.neonPurple,
      CallScreenUiColors.neonMagenta,
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
          CallScreenUiColors.neonBlue,
          CallScreenUiColors.neonPurple,
          CallScreenUiColors.neonMagenta,
          CallScreenUiColors.neonBlue,
        ],
      ).createShader(ringRect);

    canvas.drawCircle(center, radius, ringPaint);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = CallScreenUiColors.neonPurple.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CallUiSmokyRingPainter oldDelegate) {
    return oldDelegate.rotation != rotation;
  }
}
