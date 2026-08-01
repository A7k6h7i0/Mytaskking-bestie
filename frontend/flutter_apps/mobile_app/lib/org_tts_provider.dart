import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_core/mytaskking_core.dart';

import 'app_tts.dart';
import 'state.dart';

/// Org-wide TTS prompts from workspace settings (calls scope).
final orgTtsSettingsProvider = FutureProvider<OrgTtsSettings>((ref) async {
  ref.keepAlive();
  try {
    final data = await ref.watch(apiProvider).settingsScope(scope: 'calls');
    final calls = (data['calls'] as Map?)?.cast<String, dynamic>();
    final settings = OrgTtsSettings.fromCallsMap(calls);
    unawaited(warmAppTts(settings));
    return settings;
  } catch (_) {
    unawaited(warmAppTts(OrgTtsSettings.defaults));
    return OrgTtsSettings.defaults;
  }
});

OrgTtsSettings _resolveOrgTts(WidgetRef? ref) {
  if (ref == null) return OrgTtsSettings.defaults;
  return ref.read(orgTtsSettingsProvider).valueOrNull ??
      OrgTtsSettings.defaults;
}

Future<void> speakOrgMessage(
  WidgetRef ref,
  String text,
) async {
  final settings = _resolveOrgTts(ref);
  await AppTts.instance.speak(text, settings: settings);
}

Future<void> speakOrgPresence(
  WidgetRef ref,
  String name,
  Map<String, dynamic> presence,
) async {
  final settings = _resolveOrgTts(ref);
  await AppTts.instance.speak(
    settings.unavailableMessage(name, presence),
    settings: settings,
  );
}
