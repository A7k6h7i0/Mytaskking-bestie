import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';
import '../telecaller_recording_setup.dart';
import 'front_selfie_capture.dart';
import 'telecaller_onboarding_screen.dart';
import 'organization_registration_wizard.dart';
import 'organization_register_sheet.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _tenantSlug = TextEditingController();
  final _userId = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  bool _success = false;
  String? _error;
  Uint8List? _selfie;

  bool get _skipSelfieOnDesktop {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  void dispose() {
    _tenantSlug.dispose();
    _userId.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _openRegister() async {
    final api = ref.read(apiProvider);
    if (!mounted) return;
    await showOrgRegistrationFlow(
      context,
      onRegister: (data) => api.registerOrganization(data),
      api: (
        sendOtp: ({required email, required phone}) =>
            api.sendRegistrationOtp(email: email, phone: phone),
        verifyOtp: ({required email, required code}) =>
            api.verifyRegistrationOtp(email: email, code: code),
        uploadFile: ({required bytes, required filename, required mimeType}) =>
            api.registerUploadDocument(
              bytes: bytes,
              filename: filename,
              mimeType: mimeType,
            ),
        requestTrial: (tenantId) => api.requestOrgTrial(tenantId),
      ),
    );
  }

  Future<void> _submit() async {
    if (_loading) return;
    final userId = _userId.text.trim();
    final tenantSlug = _tenantSlug.text.trim();
    if (userId.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your User ID and password to continue.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final requiresSelfie = await api.loginRequiresSelfie(userId,
          tenantSlug: tenantSlug.isEmpty ? null : tenantSlug);
      if (!mounted) return;
      final shouldCaptureSelfie = requiresSelfie && !_skipSelfieOnDesktop;
      if (shouldCaptureSelfie && _selfie == null) {
        final photo = await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute(builder: (_) => const FrontSelfieCapture()),
        );
        if (photo == null) {
          throw 'A live selfie is required for employee sign-in.';
        }
        _selfie = photo;
        if (mounted) setState(() {});
      }
      double? latitude;
      double? longitude;
      String? address;
      if (requiresSelfie && !_skipSelfieOnDesktop) {
        final enabled = await Geolocator.isLocationServiceEnabled();
        if (!enabled) throw 'Turn on location to complete employee sign-in.';
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          throw 'Location permission is required for employee sign-in.';
        }
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
        latitude = position.latitude;
        longitude = position.longitude;
        try {
          final places = await placemarkFromCoordinates(latitude, longitude);
          if (places.isNotEmpty) {
            final p = places.first;
            address = [
              p.subLocality,
              p.locality,
              p.subAdministrativeArea,
              p.administrativeArea,
              p.postalCode,
              p.country,
            ].where((v) => v != null && v.trim().isNotEmpty).join(', ');
          }
        } catch (_) {
          address = '$latitude, $longitude';
        }
      }
      await api.login(
        userId: userId,
        password: _password.text,
        loginSource: _skipSelfieOnDesktop ? 'web' : 'mobile',
        tenantSlug: tenantSlug.isEmpty ? null : tenantSlug,
        selfieBase64: _selfie == null ? null : base64Encode(_selfie!),
        selfieMimeType: _selfie == null ? null : 'image/jpeg',
        latitude: latitude,
        longitude: longitude,
        address: address,
      );
      if (!mounted) return;
      final user = ref.read(authStoreProvider).user;
      if (defaultTargetPlatform == TargetPlatform.windows &&
          (user?.isClient ?? false)) {
        await api.logout();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Desktop sign-in not available'),
            content: const Text(
              'Client accounts can only sign in on the MyTaskKing mobile app. '
              'Please use your phone or tablet to access your account.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        setState(() {
          _error =
              'Client accounts cannot sign in on Windows. Use the mobile app instead.';
        });
        return;
      }
      setState(() => _success = true);
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) {
        await TelecallerRecordingSetup.load();
        final role = ref.read(authStoreProvider).user?.role;
        context.go(telecallerPostLoginRoute(
          role: role,
          isDesktop: _skipSelfieOnDesktop,
        ));
      }
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    final size = MediaQuery.sizeOf(context);
    final desktopLogin = _skipSelfieOnDesktop && size.width >= 900;

    if (_success) {
      return Scaffold(
        backgroundColor: c.surface,
        body: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BestieSuccessCheck(size: 84),
                  const SizedBox(height: 16),
                  Text('Welcome back',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: c.text)),
                  const SizedBox(height: 4),
                  Text('Loading MyTaskKing…',
                      style: TextStyle(color: c.textMuted)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (desktopLogin) {
      return _DesktopLoginShell(
        tenantSlug: _tenantSlug,
        userId: _userId,
        password: _password,
        passwordFocus: _passwordFocus,
        error: _error,
        loading: _loading,
        onSubmit: _submit,
        onRegister: _openRegister,
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Same animated mesh / spider-web backdrop as Windows login.
          const Positioned.fill(child: _LoginBackdrop()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(BestieTokens.s5),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: PopIn(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(BestieTokens.s5,
                          BestieTokens.s6, BestieTokens.s5, BestieTokens.s5),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(BestieTokens.rXl),
                        border: Border.all(color: c.borderSoft),
                        boxShadow: const [
                          BoxShadow(
                              blurRadius: 40,
                              color: Color(0x33000000),
                              offset: Offset(0, 18)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Logo inside a brand-tinted rounded badge.
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: c.brandSoft,
                                borderRadius:
                                    BorderRadius.circular(BestieTokens.rLg),
                              ),
                              child: const BestieLogo(size: 40),
                            ),
                          ),
                          const SizedBox(height: BestieTokens.s4),
                          Text(
                            'Welcome back',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: c.text),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sign in with the credentials your admin assigned.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.textMuted, height: 1.4),
                          ),
                          const SizedBox(height: BestieTokens.s5),
                          StaggeredColumn(
                            stagger: const Duration(milliseconds: 60),
                            children: [
                              BestieTextField(
                                label: 'Organisation ID',
                                controller: _tenantSlug,
                                icon: Icons.business_outlined,
                                hint: 'default or digital-links',
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) =>
                                    FocusScope.of(context).nextFocus(),
                              ),
                              BestieTextField(
                                label: 'User ID',
                                controller: _userId,
                                icon: Icons.person_outline,
                                autofocus: true,
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                              ),
                              if (_selfie != null) ...[
                                const SizedBox(height: BestieTokens.s3),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: c.brandSoft,
                                    borderRadius:
                                        BorderRadius.circular(BestieTokens.rMd),
                                  ),
                                  child: Row(children: [
                                    ClipOval(
                                      child: Image.memory(
                                        _selfie!,
                                        width: 42,
                                        height: 42,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Live login selfie ready',
                                        style: TextStyle(
                                          color: c.text,
                                          fontWeight: BestieTokens.fwSemibold,
                                        ),
                                      ),
                                    ),
                                    Icon(Icons.verified_rounded,
                                        color: c.success),
                                  ]),
                                ),
                              ],
                              const SizedBox(height: BestieTokens.s3),
                              BestieTextField(
                                label: 'Password',
                                controller: _password,
                                focusNode: _passwordFocus,
                                icon: Icons.lock_outline,
                                obscure: true,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submit(),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: BestieTokens.s3),
                                _ErrorBanner(message: _error!, colors: c),
                              ],
                              const SizedBox(height: BestieTokens.s4),
                              SizedBox(
                                width: double.infinity,
                                child: BestiePrimaryButton(
                                    label: 'Sign in',
                                    onPressed: _submit,
                                    loading: _loading),
                              ),
                            ],
                          ),
                          const SizedBox(height: BestieTokens.s4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 13, color: c.textFaint),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Forgot your credentials? Contact your administrator.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12, color: c.textFaint),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: _loading ? null : _openRegister,
                            icon: const Icon(Icons.add_business_outlined, size: 18),
                            label: const Text('Register organisation'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated mesh / spider-web backdrop — matches Windows login panel art.
class _LoginBackdrop extends StatefulWidget {
  const _LoginBackdrop();

  @override
  State<_LoginBackdrop> createState() => _LoginBackdropState();
}

class _LoginBackdropState extends State<_LoginBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _DesktopLoginMeshPainter(_controller.value),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DesktopLoginShell extends StatefulWidget {
  final TextEditingController tenantSlug;
  final TextEditingController userId;
  final TextEditingController password;
  final FocusNode passwordFocus;
  final String? error;
  final bool loading;
  final VoidCallback onSubmit;
  final VoidCallback onRegister;

  const _DesktopLoginShell({
    required this.tenantSlug,
    required this.userId,
    required this.password,
    required this.passwordFocus,
    required this.error,
    required this.loading,
    required this.onSubmit,
    required this.onRegister,
  });

  @override
  State<_DesktopLoginShell> createState() => _DesktopLoginShellState();
}

class _DesktopLoginShellState extends State<_DesktopLoginShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FC),
      body: Row(
        children: [
          Expanded(
            flex: 5,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const BestieLogo(size: 48),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'MyTaskKing',
                                    style: TextStyle(
                                      color: Color(0xFF4C7DFF),
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.8,
                                    ),
                                  ),
                                  Text(
                                    'WORKSPACE',
                                    style: TextStyle(
                                      color: Color(0xFF7C879A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                color: Color(0xFF0D1320),
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.1,
                                height: 1.05,
                              ),
                              children: [
                                TextSpan(text: 'Welcome '),
                                TextSpan(
                                  text: 'back',
                                  style: TextStyle(color: Color(0xFF6868FF)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Sign in with the credentials your admin assigned.',
                            style: TextStyle(
                              color: Color(0xFF4B5567),
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 28),
                          _DesktopLoginField(
                            label: 'Organisation ID',
                            controller: widget.tenantSlug,
                            icon: Icons.business_outlined,
                            hint: 'default or digital-links',
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                          ),
                          const SizedBox(height: 16),
                          _DesktopLoginField(
                            label: 'User ID',
                            controller: widget.userId,
                            icon: Icons.person_outline_rounded,
                            hint: 'e.g. priya.k',
                            autofocus: true,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => widget.passwordFocus.requestFocus(),
                          ),
                          const SizedBox(height: 16),
                          _DesktopLoginField(
                            label: 'Password',
                            controller: widget.password,
                            focusNode: widget.passwordFocus,
                            icon: Icons.key_rounded,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => widget.onSubmit(),
                          ),
                          if (widget.error != null) ...[
                            const SizedBox(height: 12),
                            _ErrorBanner(message: widget.error!, colors: c),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: widget.loading ? null : widget.onSubmit,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF3F6DF4),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: widget.loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Sign in',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(Icons.arrow_forward_rounded),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: widget.loading ? null : widget.onRegister,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: const BorderSide(color: Color(0xFFDDE4F1)),
                            ),
                            icon: const Icon(Icons.add_business_outlined, size: 18),
                            label: const Text(
                              'Register organisation',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'New company? Register and wait for platform approval before signing in.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF8A94A8),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            flex: 5,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _DesktopLoginMeshPainter(_controller.value),
                child: Stack(
                  children: [
                    Positioned(
                      top: 26,
                      left: 32,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x332D5BFF),
                              blurRadius: 28,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const BestieLogo(size: 52),
                      ),
                    ),
                    const Positioned(
                      left: 56,
                      bottom: 38,
                      child: Text(
                        'Your team, one workspace.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          shadows: [
                            Shadow(
                              color: Color(0x66000000),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopLoginField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final IconData icon;
  final String? hint;
  final bool obscureText;
  final bool autofocus;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _DesktopLoginField({
    required this.label,
    required this.controller,
    required this.icon,
    this.focusNode,
    this.hint,
    this.obscureText = false,
    this.autofocus = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF3E4657),
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          obscureText: obscureText,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFF7C879A)),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDDE4F1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3F6DF4), width: 2),
            ),
          ),
          style: const TextStyle(
            color: Color(0xFF0D1320),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DesktopLoginMeshPainter extends CustomPainter {
  final double t;
  const _DesktopLoginMeshPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF8EA7FF),
          Color(0xFF6FA3ED),
          Color(0xFF8D80D1),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.58),
          Colors.white.withValues(alpha: 0.10),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.48, size.height * 0.48),
          radius: size.shortestSide * 0.44,
        ),
      );
    canvas.drawRect(rect, glowPaint);

    final points = <Offset>[
      Offset(size.width * 0.10, size.height * 0.10),
      Offset(size.width * 0.24,
          size.height * (0.08 + 0.02 * math.sin(t * math.pi * 2))),
      Offset(size.width * 0.36, size.height * 0.14),
      Offset(size.width * 0.80, size.height * 0.03),
      Offset(size.width * 0.93, size.height * 0.18),
      Offset(size.width * 0.86, size.height * 0.30),
      Offset(size.width * 0.60, size.height * 0.36),
      Offset(size.width * 0.50, size.height * 0.72),
      Offset(size.width * 0.70, size.height * 0.76),
      Offset(size.width * 0.76, size.height * 0.94),
      Offset(size.width * 0.18, size.height * 0.88),
      Offset(size.width * 0.02, size.height * 0.78),
    ];
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.1;
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.62);
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      canvas.drawLine(a, b, line);
      if (i % 2 == 0 && i + 2 < points.length) {
        canvas.drawLine(a, points[i + 2],
            line..color = Colors.white.withValues(alpha: 0.10));
        line.color = Colors.white.withValues(alpha: 0.18);
      }
    }
    for (final p in points) {
      final pulse = 1.0 + 0.35 * math.sin((t * math.pi * 2) + p.dx / 90);
      canvas.drawCircle(p, 2.4 * pulse, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _DesktopLoginMeshPainter oldDelegate) =>
      oldDelegate.t != t;
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final BestieColors colors;
  const _ErrorBanner({required this.message, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.dangerSoft,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: colors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: colors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  color: colors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
