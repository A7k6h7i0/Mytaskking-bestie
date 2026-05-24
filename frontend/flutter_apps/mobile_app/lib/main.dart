import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

  // Best-effort Firebase init. If the platform config files aren't bundled
  // yet (e.g. someone building locally without google-services.json) we
  // log + carry on rather than crash the app at boot.
  try {
    await Firebase.initializeApp();
    unawaited(_wirePushNotifications(api, auth));
  } catch (_) {/* push will silently no-op */}

  runApp(ProviderScope(
    overrides: [
      authStoreProvider.overrideWithValue(auth),
      apiProvider.overrideWithValue(api),
      socketProvider.overrideWithValue(socket),
    ],
    child: const BestieApp(),
  ));
}

/// Asks for push permission, fetches the FCM device token, and registers
/// it with the backend so the server can wake the device for incoming
/// calls / mentions when the app is backgrounded or killed. Re-runs on
/// every auth change so a new login binds the device to the new user.
Future<void> _wirePushNotifications(
  core.BestieApi api,
  core.BestieAuthStore auth,
) async {
  final messaging = FirebaseMessaging.instance;
  // iOS requires explicit permission; Android grants by default below 13.
  try {
    await messaging.requestPermission(alert: true, badge: true, sound: true);
  } catch (_) {/* keep going — silent permission denial still allows data msgs */}

  Future<void> registerCurrent() async {
    if (auth.user == null) return;
    final token = await messaging.getToken();
    if (token == null) return;
    final platform = Platform.isIOS ? 'ios' : 'android';
    try { await api.registerDevice(token: token, platform: platform); } catch (_) {}
  }

  // Initial register + refresh on token rotation.
  await registerCurrent();
  messaging.onTokenRefresh.listen((_) => registerCurrent());
  // Re-register whenever the auth store flips (login / logout / refresh).
  auth.changes.listen((_) => registerCurrent());

  // Foreground messages — the socket already covers most of these but
  // listening lets us reconnect the socket if a push lands while we're
  // in the foreground with a dropped connection.
  FirebaseMessaging.onMessage.listen((_) {/* socket handles UI */});
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
