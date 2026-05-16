import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bestie_design/bestie_design.dart';

import '../state.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userId = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(apiProvider).login(
            userId: _userId.text.trim(),
            password: _password.text,
          );
      if (mounted) context.go('/');
    } catch (e) {
      setState(() => _error = 'Sign-in failed. Check your credentials.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BestieTokens.s5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [BestieTokens.cAccent, BestieTokens.cBrand],
                      ),
                    ),
                  ),
                  const SizedBox(height: BestieTokens.s4),
                  const Text('Welcome back',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('Sign in with the credentials your admin assigned.',
                      style: TextStyle(color: BestieTokens.cTextMuted)),
                  const SizedBox(height: BestieTokens.s5),
                  BestieTextField(
                    label: 'User ID',
                    controller: _userId,
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: BestieTokens.s3),
                  BestieTextField(
                    label: 'Password',
                    controller: _password,
                    icon: Icons.lock_outline,
                    obscure: true,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: BestieTokens.s3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: BestieTokens.cClientSoft,
                        borderRadius: BorderRadius.circular(BestieTokens.rSm),
                      ),
                      child: Text(_error!, style: const TextStyle(color: BestieTokens.cDanger)),
                    ),
                  ],
                  const SizedBox(height: BestieTokens.s4),
                  SizedBox(
                    width: double.infinity,
                    child: BestiePrimaryButton(
                      label: 'Sign in',
                      onPressed: _submit,
                      loading: _loading,
                    ),
                  ),
                  const SizedBox(height: BestieTokens.s5),
                  const Text(
                    'No public registration. Contact your administrator for access.',
                    style: TextStyle(fontSize: 12, color: BestieTokens.cTextMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
