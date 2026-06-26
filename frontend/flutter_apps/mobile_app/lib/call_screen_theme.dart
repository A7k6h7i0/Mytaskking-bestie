import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Call-screen-only light/dark toggle for Mute–Buzzer button borders.
/// `false` (default) = blue neon borders; `true` = white borders.
final callScreenLightControlsProvider = StateProvider<bool>((_) => false);
