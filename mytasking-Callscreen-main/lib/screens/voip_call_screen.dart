import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/call_control.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_control_button.dart';
import '../widgets/glass_container.dart';
import '../widgets/nexacorp_logo.dart';
import '../widgets/record_call_button.dart';
import '../widgets/smoky_ring_painter.dart';
import '../widgets/speaker_button.dart';

const _kControlGridWidth = 354.0;
const _kControlColumnGap = 10.0;

class VoipCallScreen extends StatefulWidget {
  const VoipCallScreen({super.key});

  @override
  State<VoipCallScreen> createState() => _VoipCallScreenState();
}

class _VoipCallScreenState extends State<VoipCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;
  Timer? _timer;
  int _elapsedSeconds = 46;
  CallControl? _selectedControl = CallControl.speaker;
  static const int _participantsJoined = 3;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedTimer {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.backgroundTop,
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.backgroundTop,
                    AppColors.backgroundMid,
                    AppColors.backgroundBottom,
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: 390,
                    height: 844,
                    child: _CallScreenBody(
                      waveController: _waveController,
                      formattedTimer: _formattedTimer,
                      selectedControl: _selectedControl,
                      participantsJoined: _participantsJoined,
                      onControlSelected: (control) {
                        setState(() {
                          _selectedControl =
                              _selectedControl == control ? null : control;
                        });
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CallScreenBody extends StatelessWidget {
  const _CallScreenBody({
    required this.waveController,
    required this.formattedTimer,
    required this.selectedControl,
    required this.participantsJoined,
    required this.onControlSelected,
  });

  final AnimationController waveController;
  final String formattedTimer;
  final CallControl? selectedControl;
  final int participantsJoined;
  final ValueChanged<CallControl> onControlSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _HeaderSection(
            participantsJoined: participantsJoined,
          ),
          const SizedBox(height: 12),
          const _MetricsRow(),
          const SizedBox(height: 6),
          Text(
            formattedTimer,
            style: const TextStyle(
              color: AppColors.neonGreen,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          _ProfileSection(
            waveController: waveController,
            height: 218,
          ),
          const SizedBox(height: 3),
          const _CallerInfoSection(),
          const SizedBox(height: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: SizedBox(
                width: _kControlGridWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ControlGrid(
                      selectedControl: selectedControl,
                      onControlSelected: onControlSelected,
                    ),
                    const _BottomActions(),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.participantsJoined,
  });

  final int participantsJoined;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          _IconSquareButton(
            icon: Icons.keyboard_arrow_down_rounded,
            onTap: () {},
          ),
          const Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NexacorpLogo(size: 34),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Addphonebook',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                SizedBox(width: 4),
                Icon(
                  Icons.verified,
                  color: AppColors.verifiedBlue,
                  size: 16,
                ),
              ],
            ),
          ),
          _ParticipantsCountButton(
            count: participantsJoined,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: const [
          Expanded(
            child: _MetricCard(
              icon: Icons.graphic_eq,
              iconColor: AppColors.neonBlue,
              title: 'HD Voice',
              subtitle: 'Crystal Clear',
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: _MetricCard(
              icon: Icons.signal_cellular_alt,
              iconColor: AppColors.neonGreen,
              title: 'Network',
              subtitle: 'Excellent',
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: _MetricCard(
              icon: Icons.shield_outlined,
              iconColor: AppColors.textPrimary,
              title: 'Security',
              subtitle: 'AES-256',
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      borderRadius: 14,
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.waveController,
    required this.height,
  });

  final AnimationController waveController;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ringOuter = height * 0.92;
    final ringInner = height * 0.84;
    final avatarSize = ringInner - 10;

    return SizedBox(
      height: height,
      child: AnimatedBuilder(
        animation: waveController,
        builder: (context, child) {
          final rotation = waveController.value * math.pi * 2;

          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: ringOuter,
                height: ringOuter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonBlue.withValues(alpha: 0.12),
                      blurRadius: 36,
                      spreadRadius: 6,
                    ),
                    BoxShadow(
                      color: AppColors.neonPurple.withValues(alpha: 0.18),
                      blurRadius: 44,
                      spreadRadius: 10,
                    ),
                    BoxShadow(
                      color: AppColors.neonMagenta.withValues(alpha: 0.1),
                      blurRadius: 52,
                      spreadRadius: 14,
                    ),
                  ],
                ),
              ),
              Transform.rotate(
                angle: rotation,
                child: CustomPaint(
                  size: Size(ringInner, ringInner),
                  painter: SmokyRingPainter(rotation: rotation * 0.35),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: ringInner - 12,
                    height: ringInner - 12,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.backgroundTop,
                    ),
                    padding: const EdgeInsets.all(3),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/profile.jpg',
                        width: avatarSize,
                        height: avatarSize,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: avatarSize,
                          height: avatarSize,
                          color: const Color(0xFF2A3550),
                          child: const Icon(
                            Icons.person,
                            size: 56,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.neonGreen,
                        border: Border.all(
                          color: AppColors.backgroundTop,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.neonGreen.withValues(alpha: 0.6),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.call,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CallerInfoSection extends StatelessWidget {
  const _CallerInfoSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Sarah Reynolds',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Senior Product Manager',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'HQ India',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _ControlGrid extends StatelessWidget {
  const _ControlGrid({
    required this.selectedControl,
    required this.onControlSelected,
  });

  final CallControl? selectedControl;
  final ValueChanged<CallControl> onControlSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlRow(
          selectedControl: selectedControl,
          onControlSelected: onControlSelected,
          controls: const [
            _ControlItem(
              control: CallControl.mute,
              icon: Icons.mic_off_outlined,
              iconGradient: [AppColors.neonPurple, AppColors.neonMagenta],
            ),
            _ControlItem(
              control: CallControl.speaker,
              icon: Icons.volume_up_rounded,
              isSpeaker: true,
            ),
            _ControlItem(
              control: CallControl.keypad,
              icon: Icons.dialpad,
            ),
            _ControlItem(
              control: CallControl.bluetooth,
              icon: Icons.bluetooth,
              iconGradient: [AppColors.neonBlue, AppColors.verifiedBlue],
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ControlRow(
          selectedControl: selectedControl,
          onControlSelected: onControlSelected,
          controls: const [
            _ControlItem(
              control: CallControl.hold,
              icon: Icons.pause,
              iconGradient: [Color(0xFFFFD166), Color(0xFFFF9F43)],
            ),
            _ControlItem(
              control: CallControl.transfer,
              icon: Icons.swap_horiz,
              iconGradient: [Color(0xFF2ECC71), AppColors.neonBlue],
            ),
            _ControlItem(
              control: CallControl.addParticipant,
              icon: Icons.person_add_outlined,
              iconGradient: [AppColors.neonBlue, AppColors.neonPurple],
            ),
            _ControlItem(
              control: CallControl.recordCall,
              icon: Icons.fiber_manual_record,
              isRecord: true,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(child: SizedBox()),
            Expanded(
              child: GlassControlButton(
                icon: Icons.voicemail,
                label: CallControl.voicemail.label,
                isSelected: selectedControl == CallControl.voicemail,
                onTap: () => onControlSelected(CallControl.voicemail),
              ),
            ),
            const SizedBox(width: _kControlColumnGap),
            Expanded(
              child: GlassControlButton(
                icon: Icons.edit_note_outlined,
                label: CallControl.callNotes.label,
                isSelected: selectedControl == CallControl.callNotes,
                onTap: () => onControlSelected(CallControl.callNotes),
              ),
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }
}

class _ControlItem {
  const _ControlItem({
    required this.control,
    required this.icon,
    this.iconGradient,
    this.isSpeaker = false,
    this.isRecord = false,
  });

  final CallControl control;
  final IconData icon;
  final List<Color>? iconGradient;
  final bool isSpeaker;
  final bool isRecord;
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.controls,
    required this.selectedControl,
    required this.onControlSelected,
  });

  final List<_ControlItem> controls;
  final CallControl? selectedControl;
  final ValueChanged<CallControl> onControlSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < controls.length; i++) ...[
          if (i > 0) const SizedBox(width: _kControlColumnGap),
          Expanded(
            child: controls[i].isRecord
                ? RecordCallButton(
                    isSelected: selectedControl == controls[i].control,
                    onTap: () => onControlSelected(controls[i].control),
                  )
                : controls[i].isSpeaker
                    ? SpeakerButton(
                        isSelected: selectedControl == controls[i].control,
                        onTap: () => onControlSelected(controls[i].control),
                      )
                    : GlassControlButton(
                        label: controls[i].control.label,
                        icon: controls[i].icon,
                        iconGradient: controls[i].iconGradient,
                        isSelected: selectedControl == controls[i].control,
                        onTap: () => onControlSelected(controls[i].control),
                      ),
          ),
        ],
      ],
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: _CircleActionButton(
                      icon: Icons.chat_bubble_outline,
                      size: 48,
                      onTap: () {},
                    ),
                  ),
                ),
                const SizedBox(width: _kControlColumnGap),
                const Expanded(child: SizedBox()),
                const SizedBox(width: _kControlColumnGap),
                const Expanded(child: SizedBox()),
                const SizedBox(width: _kControlColumnGap),
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: const Offset(6, 0),
                      child: _CircleActionButton(
                        icon: Icons.videocam_outlined,
                        size: 48,
                        onTap: () {},
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.endCallRed,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.endCallRed.withValues(alpha: 0.55),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: AppColors.endCallRed.withValues(alpha: 0.35),
                    blurRadius: 40,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {},
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }
}

class _ParticipantsCountButton extends StatelessWidget {
  const _ParticipantsCountButton({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: GlassContainer(
          borderRadius: 12,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.group_outlined,
                color: AppColors.textPrimary,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;

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

  static const _faceGradient = RadialGradient(
    center: Alignment(-0.1, -0.15),
    radius: 1.0,
    colors: [
      AppColors.speakerFaceHighlight,
      AppColors.speakerBackground,
    ],
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
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
        child: ClipOval(
          child: Container(
            padding: const EdgeInsets.all(1.6),
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
                    color: AppColors.textPrimary,
                    size: size * 0.42,
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

class _IconSquareButton extends StatelessWidget {
  const _IconSquareButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: GlassContainer(
          borderRadius: 12,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: SizedBox(
            width: 34,
            height: 18,
            child: Center(
              child: Icon(icon, color: AppColors.textPrimary, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}
