import 'package:flutter_tts/flutter_tts.dart';

/// Conversational TTS speed for in-app voice prompts (busy, leave, incoming).
/// Previous 0.36 rate sounded unnaturally slow on most devices.
const double kAppTtsSpeechRate = 0.5;

Future<void> speakAppMessage(FlutterTts tts, String text) async {
  try {
    await tts.setLanguage('en-US');
    await tts.setPitch(1.0);
    await tts.setSpeechRate(kAppTtsSpeechRate);
    await tts.speak(text);
  } catch (_) {}
}

Future<void> speakAppMessageFresh(String text) async {
  await speakAppMessage(FlutterTts(), text);
}
