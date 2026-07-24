import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../state.dart';
import '../telecaller_call_settings.dart';
import '../telecaller_recording_setup.dart';
import '../telecaller_recording_storage.dart';

/// First-run setup for telecallers: OEM call-record settings → test call →
/// link recordings folder → welcome.
class TelecallerOnboardingScreen extends ConsumerStatefulWidget {
  const TelecallerOnboardingScreen({super.key});

  @override
  ConsumerState<TelecallerOnboardingScreen> createState() =>
      _TelecallerOnboardingScreenState();
}

class _TelecallerOnboardingScreenState
    extends ConsumerState<TelecallerOnboardingScreen>
    with WidgetsBindingObserver {
  static const _textGrey = Color(0xFF8E8E93);
  static const _bgLight = Color(0xFFF2F7FB);

  int _step = 0;
  bool _awaitingTestCallReturn = false;
  String? _linkedFolder;
  int _linkedFileCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(TelecallerRecordingSetup.load().then((_) {
      if (mounted) {
        setState(() {
          _linkedFolder = TelecallerRecordingSetup.folderLabel ??
              TelecallerRecordingSetup.treeUri ??
              TelecallerRecordingSetup.folderUri;
          _linkedFileCount = TelecallerRecordingSetup.audioCount;
        });
      }
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _awaitingTestCallReturn &&
        _step == 1 &&
        mounted) {
      _awaitingTestCallReturn = false;
      setState(() => _step = 2);
    }
  }

  String? get _testPhone {
    final phone = ref.read(authStoreProvider).user?.phone?.toString().trim();
    if (phone != null && phone.isNotEmpty) return phone;
    return null;
  }

  Future<void> _openCallSettings() async {
    if (!Platform.isAndroid) {
      bestieToast(context, 'Use your iPhone Phone app settings',
          kind: BestieToastKind.info);
      return;
    }
    final ok = await TelecallerCallSettings.openCallRecordingSettings();
    if (!mounted) return;
    if (!ok) {
      bestieToast(context, 'Could not open settings',
          body: 'Open Phone app → Settings → Call recording manually.',
          kind: BestieToastKind.warning);
    }
  }

  Future<void> _launchTestCall() async {
    final phone = _testPhone;
    if (phone == null) {
      bestieToast(context, 'Add your phone in Profile first',
          kind: BestieToastKind.warning);
      return;
    }
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final launched = await launchUrl(
      Uri(scheme: 'tel', path: digits),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      if (mounted) {
        bestieToast(context, 'Could not open phone app',
            kind: BestieToastKind.error);
      }
      return;
    }
    _awaitingTestCallReturn = true;
  }

  Future<void> _pickRecordingFolder() async {
    try {
      if (Platform.isAndroid) {
        final granted = await TelecallerRecordingStorage.ensureAudioAccess();
        if (!granted && mounted) {
          bestieToast(context, 'Storage permission needed',
              body: 'Allow audio access to scan call recordings.',
              kind: BestieToastKind.warning);
        }
        final picked = await TelecallerRecordingStorage.pickFolder();
        if (picked == null) return;
        final treeUri = picked['treeUri'] as String?;
        final name = picked['displayName'] as String? ?? 'Recordings folder';
        final count = (picked['audioCount'] as num?)?.toInt() ?? 0;
        if (treeUri == null || treeUri.isEmpty) return;
        await TelecallerRecordingSetup.setLinkedFolder(
          treeUri: treeUri,
          displayName: name,
          audioCount: count,
        );
        if (mounted) {
          setState(() {
            _linkedFolder = name;
            _linkedFileCount = count;
          });
          bestieToast(context, 'Folder linked',
              body: count > 0
                  ? 'Found $count audio file(s). Ready for auto-upload.'
                  : 'No audio files yet — place a test call first.',
              kind: BestieToastKind.success);
        }
        return;
      }

      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose call recordings folder',
      );
      if (path == null || path.isEmpty) return;
      await TelecallerRecordingSetup.setFolderUri(path);
      if (mounted) {
        setState(() {
          _linkedFolder = path;
          _linkedFileCount = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        bestieToast(context, 'Could not link folder',
            body: e.toString(), kind: BestieToastKind.error);
      }
    }
  }

  void _back() {
    if (_step <= 0) return;
    setState(() => _step -= 1);
  }

  void _nextFromStep0() => setState(() => _step = 1);

  void _nextFromStep2() {
    if (!TelecallerRecordingSetup.hasLinkedFolder) {
      bestieToast(
        context,
        'Choose the recordings folder',
        body: 'Pick the folder where your phone saves call recordings.',
        kind: BestieToastKind.warning,
      );
      return;
    }
    setState(() => _step = 3);
  }

  void _getStarted() async {
    await TelecallerRecordingSetup.markComplete();
    if (mounted) context.go('/telecaller');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_step >= 3) {
      return const SizedBox(height: 10);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          if (_step > 0)
            _RoundIconButton(icon: Icons.chevron_left, onTap: _back)
          else
            const SizedBox(width: 35),
          Expanded(
            child: Text(
              '${_step + 1} of 3',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 35),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final brand = BestieColors.of(context).brand;
    switch (_step) {
      case 0:
        return _stepContent(
          icon: Icons.touch_app_rounded,
          title: 'Turn On Auto Call Record',
          description:
              'Open your Phone app settings and enable automatic call recording. This lets your device save both sides of the conversation.',
          bullets: const [
            'Samsung: Phone → ⋮ → Settings → Call recording',
            'Xiaomi: Settings → System apps → Calls → Call recording',
            'Other: Phone app → Settings → search "call recording"',
          ],
          extra: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _openCallSettings,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Open Phone Settings'),
              style: OutlinedButton.styleFrom(
                foregroundColor: brand,
                side: BorderSide(color: brand),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
          fullWidthBelow: const Padding(
            padding: EdgeInsets.only(top: 16),
            child: _CallRecordGuideVideo(),
          ),
        );
      case 1:
        final phone = _testPhone;
        return _stepContent(
          icon: Icons.call_rounded,
          title: 'Test Auto Recording',
          description: phone == null
              ? 'Add your mobile number in Profile, then place a short test call to confirm recordings are saved on your phone.'
              : 'Call your number below, speak for a few seconds, hang up, then return here. We\'ll link your recording next.',
          bullets: phone == null
              ? const [
                  'Profile → Phone number → Save',
                  'Then come back and run this test',
                ]
              : [
                  'Tap the button below to open the dialer',
                  'After the call, press Back to return to MyTaskKing',
                  'Test number: $phone',
                ],
          extra: phone != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    onPressed: _launchTestCall,
                    icon: const Icon(Icons.phone_outlined, size: 18),
                    label: Text('Call $phone'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: brand,
                      side: BorderSide(color: brand),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                )
              : null,
        );
      case 2:
        return _stepContent(
          icon: Icons.folder_open_rounded,
          title: 'Link Recordings Storage',
          description:
              'Choose the folder where your phone saves call recordings so future calls upload automatically.',
          bullets: [
            if (_linkedFolder != null) ...[
              'Linked: $_linkedFolder',
              if (_linkedFileCount > 0)
                '$_linkedFileCount audio file(s) detected',
            ] else ...[
              'Tap Choose folder and select where your phone saves call recordings',
              'Samsung: Internal storage → Call or Recordings/Call',
              'Vivo/Xiaomi: MIUI/sound_recorder/call_rec or Recordings',
            ],
          ],
          extra: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: _pickRecordingFolder,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Choose folder'),
              style: OutlinedButton.styleFrom(
                foregroundColor: brand,
                side: BorderSide(color: brand),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
        );
      default:
        return _welcomeContent();
    }
  }

  Widget _stepContent({
    required IconData icon,
    required String title,
    required String description,
    required List<String> bullets,
    Widget? extra,
    Widget? fullWidthBelow,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 35),
            child: Column(
              children: [
                _IconRings(icon: icon),
                const SizedBox(height: 28),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: _textGrey,
                  ),
                ),
                const SizedBox(height: 32),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: bullets
                        .map((text) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _CheckBullet(text: text),
                            ))
                        .toList(),
                  ),
                ),
                if (extra != null) extra,
              ],
            ),
          ),
          if (fullWidthBelow != null) fullWidthBelow,
        ],
      ),
    );
  }

  Widget _welcomeContent() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _IconRings(icon: Icons.shield_rounded, size: 70, ringScale: 1.08),
            const SizedBox(height: 40),
            const Text(
              'Welcome to MyTaskKing',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'Your telecaller workspace is ready. Leads, calls, and recordings will stay linked to your account.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                color: _textGrey,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Dot(active: true),
                const SizedBox(width: 8),
                _Dot(active: false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (_step >= 3) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(25, 12, 25, 32),
        child: _PrimaryButton(
          label: 'Get Started',
          trailing: Icons.arrow_forward_rounded,
          onTap: _getStarted,
        ),
      );
    }

    final labels = ['Next — Step 1', 'I placed the test call', 'Finish setup'];
    final VoidCallback onTap;
    switch (_step) {
      case 0:
        onTap = _nextFromStep0;
        break;
      case 1:
        onTap = () => setState(() => _step = 2);
        break;
      default:
        onTap = _nextFromStep2;
    }
    final icons = [
      Icons.settings_suggest_outlined,
      Icons.arrow_forward_rounded,
      Icons.check_rounded,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 12, 25, 32),
      child: _PrimaryButton(
        label: labels[_step],
        leading: icons[_step],
        onTap: onTap,
      ),
    );
  }
}

/// Step 1 guide video — full screen width, natural height, auto-plays.
class _CallRecordGuideVideo extends StatefulWidget {
  const _CallRecordGuideVideo();

  @override
  State<_CallRecordGuideVideo> createState() => _CallRecordGuideVideoState();
}

class _CallRecordGuideVideoState extends State<_CallRecordGuideVideo> {
  static const _asset = 'assets/video/call_record_guide.mp4';

  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(_asset)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        unawaited(_controller.setLooping(true));
        unawaited(_controller.setVolume(1));
        unawaited(_controller.play());
      }).catchError((_) {
        if (mounted) setState(() => _ready = false);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || !_controller.value.isInitialized) {
      return const SizedBox(
        width: double.infinity,
        height: 180,
        child: Center(child: BestieSpinner()),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: VideoPlayer(_controller),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF9F9F9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 35,
          height: 35,
          child: Icon(icon, size: 20, color: Color(0xFF666666)),
        ),
      ),
    );
  }
}

class _IconRings extends StatelessWidget {
  const _IconRings({
    required this.icon,
    this.size = 80,
    this.ringScale = 1.0,
  });

  final IconData icon;
  final double size;
  final double ringScale;

  static const _circleBorder = Color(0xFFBCDFFF);

  @override
  Widget build(BuildContext context) {
    final brand = BestieColors.of(context).brand;
    return SizedBox(
      width: 120 * ringScale,
      height: 120 * ringScale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _Ring(size: 60 * ringScale, opacity: 1),
          _Ring(size: 85 * ringScale, opacity: 0.6),
          _Ring(size: 110 * ringScale, opacity: 0.3),
          Icon(icon, size: size, color: brand),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.opacity});
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border:
            Border.all(color: _IconRings._circleBorder.withOpacity(opacity)),
      ),
    );
  }
}

class _CheckBullet extends StatelessWidget {
  const _CheckBullet({required this.text});
  final String text;

  static const _textGrey = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    final brand = BestieColors.of(context).brand;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: brand,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 11, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style:
                const TextStyle(fontSize: 14, color: _textGrey, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.leading,
    this.trailing,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? leading;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final brand = BestieColors.of(context).brand;
    return Material(
      color: brand,
      borderRadius: BorderRadius.circular(28),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: brand.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[
                Icon(leading, color: Colors.white, size: 18),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                Icon(trailing, color: Colors.white, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final brand = BestieColors.of(context).brand;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? brand : const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

/// Returns the post-login route for the current user role + setup state.
String telecallerPostLoginRoute(
    {required String? role, required bool isDesktop}) {
  if (role == 'TELECALLER') {
    if (!TelecallerRecordingSetup.isComplete) {
      return '/telecaller/setup';
    }
    return '/telecaller';
  }
  if (isDesktop) return '/dashboard';
  return '/chat';
}
