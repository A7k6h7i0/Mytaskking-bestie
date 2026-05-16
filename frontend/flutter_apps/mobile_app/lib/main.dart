import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bestie_design/bestie_design.dart';
import 'package:bestie_core/bestie_core.dart';

import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = BestieAuthStore();
  await auth.load();

  runApp(ProviderScope(
    overrides: [authStoreProvider.overrideWithValue(auth)],
    child: const BestieApp(),
  ));
}

class BestieApp extends ConsumerWidget {
  const BestieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStoreProvider);

    final router = GoRouter(
      initialLocation: auth.accessToken == null ? '/login' : '/',
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      ],
      redirect: (ctx, state) {
        final logged = auth.accessToken != null;
        final goingToLogin = state.matchedLocation == '/login';
        if (!logged && !goingToLogin) return '/login';
        if (logged && goingToLogin) return '/';
        return null;
      },
    );

    return MaterialApp.router(
      title: 'Bestie',
      theme: BestieTheme.light(),
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
