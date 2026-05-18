import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bestie_design/bestie_design.dart';
import 'package:bestie_core/bestie_core.dart';

import 'router.dart';
import 'state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = BestieAuthStore();
  await auth.load();

  final api = BestieApi(baseUrl: kApiBaseUrl, auth: auth);
  final socket = BestieSocket(url: kSocketUrl, auth: auth);

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
      title: 'Bestie',
      debugShowCheckedModeBanner: false,
      theme: BestieTheme.light(),
      darkTheme: BestieTheme.light(),
      themeMode: switch (mode) {
        ThemeMode.light  => ThemeMode.light,
        ThemeMode.dark   => ThemeMode.dark,
        ThemeMode.system => ThemeMode.system,
      },
      routerConfig: ref.watch(routerProvider),
    );
  }
}
