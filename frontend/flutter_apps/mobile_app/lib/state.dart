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
/// Release builds ship with the production hosted API so users get a working
/// app out of the box. Local dev overrides the value via
/// `--dart-define=API_URL=http://10.0.2.2:4000` (Android emulator → host) or
/// `http://localhost:4000` (iOS sim / desktop).
// NOTE: BestieApi appends `/api/v1` to whatever it's handed, so the API
// host here is the bare origin — `https://mytaskking.com`, not
// `https://mytaskking.com/api/v1`.
const String _kDefaultApiUrl = 'https://mytaskking.com';
const String _kDefaultSocketUrl = 'https://mytaskking.com';

String _devFallback() {
  try {
    if (Platform.isAndroid) return 'http://10.0.2.2:4000';
  } catch (_) {
    // Platform isn't available on web; fall through.
  }
  return 'http://localhost:4000';
}

/// In debug mode prefer the dev fallback (local backend at port 4000) so
/// `flutter run` Just Works without a dart-define; release builds use the
/// production URL. Either can be overridden via `--dart-define=API_URL=…`.
bool get _kIsDebug {
  bool isDebug = false;
  assert(isDebug = true);
  return isDebug;
}

final String kApiBaseUrl = const bool.hasEnvironment('API_URL')
    ? const String.fromEnvironment('API_URL')
    : (_kIsDebug ? _devFallback() : _kDefaultApiUrl);

final String kSocketUrl = const bool.hasEnvironment('SOCKET_URL')
    ? const String.fromEnvironment('SOCKET_URL')
    : (_kIsDebug ? _devFallback() : _kDefaultSocketUrl);
