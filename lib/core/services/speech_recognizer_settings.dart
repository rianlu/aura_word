import 'package:shared_preferences/shared_preferences.dart';

enum SpeechRecognizerMode {
  auto,
  system,
  offline,
}

class SpeechRecognizerSettings {
  SpeechRecognizerSettings._();

  static final SpeechRecognizerSettings instance = SpeechRecognizerSettings._();

  static const _key = 'speech_recognizer_mode';

  Future<SpeechRecognizerMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('pronunciation_engine') == 'phoneme') {
      await prefs.setString('pronunciation_engine', 'text');
      await prefs.setString(_key, SpeechRecognizerMode.offline.name);
      return SpeechRecognizerMode.offline;
    }
    return _fromName(prefs.getString(_key));
  }

  Future<void> setMode(SpeechRecognizerMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  SpeechRecognizerMode _fromName(String? name) {
    for (final mode in SpeechRecognizerMode.values) {
      if (mode.name == name) return mode;
    }
    return SpeechRecognizerMode.auto;
  }
}
