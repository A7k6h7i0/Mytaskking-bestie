import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mytaskking_core/mytaskking_core.dart';

/// Conversational TTS speed for in-app voice prompts (busy, leave, incoming).
const double kAppTtsSpeechRate = 0.5;

Future<void> applyOrgTtsVoice(
  FlutterTts tts,
  OrgTtsSettings settings,
) async {
  try {
    await tts.setLanguage('en-US');
    await tts.setSpeechRate(kAppTtsSpeechRate);
    final female = settings.voiceGender == 'female';
    await tts.setPitch(female ? 1.05 : 0.9);

    if (kIsWeb) return;
    final voicesRaw = await tts.getVoices;
    if (voicesRaw is! List) return;
    final voices = voicesRaw.cast<Map>().where((voice) {
      final locale = voice['locale']?.toString() ?? '';
      return locale.toLowerCase().startsWith('en');
    }).toList();
    if (voices.isEmpty) return;

    Map? picked;
    for (final voice in voices) {
      final name = voice['name']?.toString().toLowerCase() ?? '';
      if (female && _looksFemaleVoice(name)) {
        picked = voice;
        break;
      }
      if (!female && _looksMaleVoice(name)) {
        picked = voice;
        break;
      }
    }
    picked ??= voices.first;
    await tts.setVoice({
      'name': picked['name'],
      'locale': picked['locale'],
    });
  } catch (_) {}
}

bool _looksFemaleVoice(String name) =>
    name.contains('female') ||
    name.contains('woman') ||
    name.contains('samantha') ||
    name.contains('zira') ||
    name.contains('karen') ||
    name.contains('victoria') ||
    name.contains('susan');

bool _looksMaleVoice(String name) =>
    name.contains('male') ||
    name.contains('man') ||
    name.contains('david') ||
    name.contains('mark') ||
    name.contains('daniel') ||
    name.contains('james') ||
    name.contains('tom');

Future<void> speakAppMessage(
  FlutterTts tts,
  String text, {
  OrgTtsSettings? settings,
}) async {
  try {
    await applyOrgTtsVoice(tts, settings ?? OrgTtsSettings.defaults);
    await tts.speak(text);
  } catch (_) {}
}

Future<void> speakAppMessageFresh(
  String text, {
  OrgTtsSettings? settings,
}) async {
  await speakAppMessage(
    FlutterTts(),
    text,
    settings: settings ?? OrgTtsSettings.defaults,
  );
}
