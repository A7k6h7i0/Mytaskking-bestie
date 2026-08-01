import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mytaskking_core/mytaskking_core.dart';

/// Conversational TTS speed for in-app voice prompts (busy, leave, incoming).
const double kAppTtsSpeechRate = 0.5;

const double _kFemalePitch = 1.25;
const double _kMalePitch = 0.75;

/// One shared TTS engine with cached device voices — avoids 2–3s delay per speak.
class AppTts {
  AppTts._();

  static final AppTts instance = AppTts._();

  final FlutterTts _engine = FlutterTts();
  List<Map<String, dynamic>>? _englishVoices;
  String? _appliedGender;
  Future<void>? _warmFuture;

  void invalidateVoice() {
    _appliedGender = null;
    _warmFuture = null;
  }

  Future<void> warm(OrgTtsSettings settings) async {
    final gender = settings.voiceGender;
    if (_appliedGender == gender &&
        _englishVoices != null &&
        _warmFuture != null) {
      return _warmFuture;
    }
    _warmFuture = _warmInternal(settings);
    await _warmFuture;
  }

  Future<void> _warmInternal(OrgTtsSettings settings) async {
    final female = settings.voiceGender == 'female';
    try {
      await _engine.setLanguage('en-US');
      await _engine.setSpeechRate(kAppTtsSpeechRate);
      await _engine.setPitch(female ? _kFemalePitch : _kMalePitch);

      if (!kIsWeb) {
        _englishVoices ??= await _loadEnglishVoices();
        final picked = _pickVoice(_englishVoices!, female: female);
        if (picked != null) {
          await _engine.setVoice({
            'name': picked['name'],
            'locale': picked['locale'],
          });
        }
      }
      _appliedGender = settings.voiceGender;
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadEnglishVoices() async {
    try {
      final raw = await _engine.getVoices;
      if (raw is! List) return const [];
      return raw.cast<Map>().map((voice) {
        return voice.map((key, value) => MapEntry(key.toString(), value));
      }).where((voice) {
        final locale = voice['locale']?.toString().toLowerCase() ?? '';
        return locale.startsWith('en');
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic>? _pickVoice(
    List<Map<String, dynamic>> voices, {
    required bool female,
  }) {
    if (voices.isEmpty) return null;

    for (final voice in voices) {
      if (_voiceMatchesGender(voice, female: female)) return voice;
    }
    for (final voice in voices) {
      if (!_voiceMatchesGender(voice, female: !female)) return voice;
    }
    return voices.first;
  }

  bool _voiceMatchesGender(Map<String, dynamic> voice, {required bool female}) {
    final gender = voice['gender']?.toString().toLowerCase() ?? '';
    if (gender.isNotEmpty) {
      if (female) return gender.contains('female');
      return gender.contains('male') && !gender.contains('female');
    }
    final name = voice['name']?.toString().toLowerCase() ?? '';
    if (female) return _looksFemaleVoiceName(name);
    return _looksMaleVoiceName(name);
  }

  Future<void> speak(String text, {OrgTtsSettings? settings}) async {
    final resolved = settings ?? OrgTtsSettings.defaults;
    if (_appliedGender != resolved.voiceGender || _warmFuture == null) {
      await warm(resolved);
    } else if (_appliedGender == null && _warmFuture != null) {
      await _warmFuture;
    }
    try {
      await _engine.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _engine.stop();
    } catch (_) {}
  }
}

bool _looksFemaleVoiceName(String name) =>
    name.contains('female') ||
    name.contains('#female') ||
    name.contains('woman') ||
    name.contains('samantha') ||
    name.contains('zira') ||
    name.contains('karen') ||
    name.contains('victoria') ||
    name.contains('susan') ||
    name.contains('-iob') ||
    name.contains('-tpf') ||
    name.contains('fem');

bool _looksMaleVoiceName(String name) =>
    name.contains('male') ||
    name.contains('#male') ||
    name.contains('man') ||
    name.contains('david') ||
    name.contains('mark') ||
    name.contains('daniel') ||
    name.contains('james') ||
    name.contains('tom') ||
    name.contains('-iom') ||
    name.contains('-tpd') ||
    name.contains('-tm');

Future<void> warmAppTts(OrgTtsSettings settings) => AppTts.instance.warm(settings);

void invalidateAppTtsVoice() => AppTts.instance.invalidateVoice();

Future<void> stopAppTts() => AppTts.instance.stop();

/// Kept for call sites that pass a [FlutterTts] — the shared engine is always used.
Future<void> applyOrgTtsVoice(
  FlutterTts tts,
  OrgTtsSettings settings,
) async {
  await AppTts.instance.warm(settings);
}

Future<void> speakAppMessage(
  FlutterTts tts,
  String text, {
  OrgTtsSettings? settings,
}) async {
  await AppTts.instance.speak(text, settings: settings);
}

Future<void> speakAppMessageFresh(
  String text, {
  OrgTtsSettings? settings,
}) async {
  await AppTts.instance.speak(text, settings: settings);
}
