// Re-exports the shared Riverpod providers, API types and extensions, plus
// app-level constants so screens can `import 'state.dart'` and get everything
// they need to call providers and BestieApi methods in one shot.
//
// We export the mytaskking_core library wholesale (no `show` filter) so that the
// `BestieApiExt` extension on `BestieApi` is visible at call sites — Dart
// extensions only resolve when both the type AND the extension are in scope.

import 'dart:io' show Platform;

export 'package:mytaskking_core/mytaskking_core.dart';

/// Default base URL for the backend.
///
/// Android emulators map the host machine to `10.0.2.2`, not `localhost`
/// (which would resolve to the emulator itself). iOS simulators and desktop
/// builds reach the host directly via `localhost`. CI/production builds set
/// `--dart-define=API_URL=https://api.example.com` to bypass this entirely.
String _defaultHost() {
  const overridden = bool.hasEnvironment('API_URL');
  if (overridden) return 'http://localhost:4000'; // unused when override set
  try {
    if (Platform.isAndroid) return 'http://10.0.2.2:4000';
  } catch (_) {
    // Platform isn't available on web; fall through.
  }
  return 'http://localhost:4000';
}

final String kApiBaseUrl = const bool.hasEnvironment('API_URL')
    ? const String.fromEnvironment('API_URL')
    : _defaultHost();

final String kSocketUrl = const bool.hasEnvironment('SOCKET_URL')
    ? const String.fromEnvironment('SOCKET_URL')
    : _defaultHost();
