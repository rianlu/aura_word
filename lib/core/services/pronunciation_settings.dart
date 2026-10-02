import 'package:shared_preferences/shared_preferences.dart';

enum PronunciationStrictness {
  strict,
  loose,
}

enum PronunciationEngine {
  text,
  phoneme,
}

class PhoneticSourceSettings {
  PhoneticSourceSettings._();

  static final PhoneticSourceSettings instance = PhoneticSourceSettings._();
  static const _key = 'phonetic_source';

  static bool useTextbook = true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    useTextbook = (prefs.getString(_key) ?? 'textbook') != 'dictionary';
  }

  Future<void> setUseTextbook(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value ? 'textbook' : 'dictionary');
    useTextbook = value;
  }
}

class PronunciationSettings {
  PronunciationSettings._();

  static final PronunciationSettings instance = PronunciationSettings._();

  static const _key = 'pronunciation_strictness';
  static const _engineKey = 'pronunciation_engine';

  Future<PronunciationStrictness> getStrictness() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    if (name == PronunciationStrictness.strict.name) {
      return PronunciationStrictness.strict;
    }
    return PronunciationStrictness.loose;
  }

  Future<void> setStrictness(PronunciationStrictness value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
  }

  Future<PronunciationEngine> getEngine() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_engineKey) == PronunciationEngine.phoneme.name) {
      return PronunciationEngine.phoneme;
    }
    return PronunciationEngine.text;
  }

  Future<void> setEngine(PronunciationEngine value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_engineKey, value.name);
  }
}
