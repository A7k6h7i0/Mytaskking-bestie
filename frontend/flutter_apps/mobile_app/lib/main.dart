import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_design/mytaskking_design.dart';
import 'package:mytaskking_core/mytaskking_core.dart' as core;

import 'router.dart';
import 'screens/incoming_call_overlay.dart';
import 'state.dart' hide ThemeMode;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = core.BestieAuthStore();
  await auth.load();

  final api = core.BestieApi(baseUrl: kApiBaseUrl, auth: auth);
  final socket = core.BestieSocket(url: kSocketUrl, auth: auth);

  runApp(ProviderScope(
    overrides: [
      authStoreProvider.overrideWithValue(auth),
      apiProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(socket),
    ],
    child: const BestieApp(),
  ));
}

class BestieApp extends ConsumerWidget {
  const BestieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'MyTaskKing',
      debugShowCheckedModeBanner: false,
      theme: BestieTheme.light(),
      darkTheme: BestieTheme.dark(),
      themeMode: switch (mode) {
        core.ThemeMode.light  => ThemeMode.light,
        core.ThemeMode.dark   => ThemeMode.dark,
        core.ThemeMode.system => ThemeMode.system,
      },
      routerConfig: ref.watch(routerProvider),
      // The overlay listens for incoming-call socket events globally and
      // covers whatever screen you're on with an Accept/Decline ringer.
      builder: (ctx, child) => IncomingCallOverlay(child: child ?? const SizedBox.shrink()),
    );
  }
}
