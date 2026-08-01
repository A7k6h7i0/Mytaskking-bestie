import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mytaskking_core/mytaskking_core.dart';

import 'state.dart';

/// Org-wide TTS prompts from workspace settings (calls scope).
final orgTtsSettingsProvider = FutureProvider<OrgTtsSettings>((ref) async {
  try {
    final data = await ref.watch(apiProvider).settingsScope(scope: 'calls');
    final calls = (data['calls'] as Map?)?.cast<String, dynamic>();
    return OrgTtsSettings.fromCallsMap(calls);
  } catch (_) {
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
  String text, {
  FlutterTts? tts,
}) async {
  final settings = _resolveOrgTts(ref);
  if (tts != null) {
    await speakAppMessage(tts, text, settings: settings);
  } else {
    await speakAppMessageFresh(text, settings: settings);
  }
}

Future<void> speakOrgPresence(
  WidgetRef ref,
  String name,
  Map<String, dynamic> presence,
) async {
  final settings = _resolveOrgTts(ref);
  await speakAppMessageFresh(
    settings.unavailableMessage(name, presence),
    settings: settings,
  );
}
