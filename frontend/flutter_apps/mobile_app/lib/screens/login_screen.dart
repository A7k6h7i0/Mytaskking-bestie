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
  bool _success = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(apiProvider).login(userId: _userId.text.trim(), password: _password.text);
      setState(() => _success = true);
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) context.go('/dashboard');
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BestieSuccessCheck(size: 84),
              SizedBox(height: 16),
              Text('Welcome back', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text('Loading MyTaskKing…', style: TextStyle(color: BestieTokens.cTextMuted)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF7C5CFF), Color(0xFF5B8CFF), Color(0xFF3AA1FF)],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BestieTokens.s5),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: PopIn(
                  child: Container(
                    padding: const EdgeInsets.all(BestieTokens.s5),
                    decoration: BoxDecoration(
                      color: BestieTokens.cSurface,
                      borderRadius: BorderRadius.circular(BestieTokens.rLg),
                      boxShadow: const [
                        BoxShadow(blurRadius: 30, color: Color(0x33000000), offset: Offset(0, 10)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const BestieLogo(size: 44, withWordmark: true),
                        const SizedBox(height: BestieTokens.s4),
                        const Text('Welcome back',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        const Text(
                          'Sign in with the credentials your admin assigned.',
                          style: TextStyle(color: BestieTokens.cTextMuted),
                        ),
                        const SizedBox(height: BestieTokens.s4),
                        StaggeredColumn(
                          stagger: const Duration(milliseconds: 60),
                          children: [
                            BestieTextField(label: 'User ID', controller: _userId, icon: Icons.person_outline),
                            const SizedBox(height: BestieTokens.s2),
                            BestieTextField(label: 'Password', controller: _password, icon: Icons.lock_outline, obscure: true),
                            if (_error != null) ...[
                              const SizedBox(height: BestieTokens.s2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: BestieTokens.cClientSoft,
                                  borderRadius: BorderRadius.circular(BestieTokens.rSm),
                                ),
                                child: Text(_error!, style: const TextStyle(color: BestieTokens.cDanger)),
                              ),
                            ],
                            const SizedBox(height: BestieTokens.s3),
                            SizedBox(
                              width: double.infinity,
                              child: BestiePrimaryButton(label: 'Sign in', onPressed: _submit, loading: _loading),
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
        ]),
      ),
    );
  }
}
