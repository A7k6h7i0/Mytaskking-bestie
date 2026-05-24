// Re-exports the shared Riverpod providers, API types and extensions, plus
// app-level constants so screens can `import 'state.dart'` and get everything
// they need to call providers and BestieApi methods in one shot.
//
// We export the mytaskking_core library wholesale (no `show` filter) so that the
// `BestieApiExt` extension on `BestieApi` is visible at call sites — Dart
// extensions only resolve when both the type AND the extension are in scope.

export 'package:mytaskking_core/mytaskking_core.dart';

const kApiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:4000',
);
const kSocketUrl = String.fromEnvironment(
  'SOCKET_URL',
  defaultValue: 'http://localhost:4000',
);
