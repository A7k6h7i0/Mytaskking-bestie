import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

import '../state.dart';
import 'front_selfie_capture.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userId = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  bool _success = false;
  String? _error;
  Uint8List? _selfie;

  @override
  void dispose() {
    _userId.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final userId = _userId.text.trim();
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
      final requiresSelfie = await api.loginRequiresSelfie(userId);
      if (!mounted) return;
      if (requiresSelfie && _selfie == null) {
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
      if (requiresSelfie) {
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
        selfieBase64: _selfie == null ? null : base64Encode(_selfie!),
        selfieMimeType: _selfie == null ? null : 'image/jpeg',
        latitude: latitude,
        longitude: longitude,
        address: address,
      );
      setState(() => _success = true);
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) context.go('/chat');
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BestieColors.of(context);

    if (_success) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(
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
              Text('Loading MyTaskKing…', style: TextStyle(color: c.textMuted)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Brand gradient backdrop with soft decorative glows.
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

/// Brand gradient + two soft radial glows behind the login card.
class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C5CFF), Color(0xFF5B8CFF), Color(0xFF3AA1FF)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -90,
            left: -60,
            child: _glow(220, const Color(0x33FFFFFF)),
          ),
          Positioned(
            bottom: -120,
            right: -80,
            child: _glow(300, const Color(0x26FFFFFF)),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      );
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
