import 'package:shared_preferences/shared_preferences.dart';

enum PronunciationStrictness {
  strict,
  loose,
}

class PronunciationSettings {
  PronunciationSettings._();

  static final PronunciationSettings instance = PronunciationSettings._();

  static const _key = 'pronunciation_strictness';

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
}
