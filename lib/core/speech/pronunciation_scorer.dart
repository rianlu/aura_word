import '../services/pronunciation_settings.dart';

class PhonemeMark {
  final String symbol;
  final bool ok;

  const PhonemeMark({required this.symbol, required this.ok});
}

class PronunciationVerdict {
  final bool passed;
  final int stars;
  final List<PhonemeMark> phonemes;
  final String? focusSymbol;
  final String hint;

  const PronunciationVerdict({
    required this.passed,
    required this.stars,
    required this.phonemes,
    required this.focusSymbol,
    required this.hint,
  });
}

class PronunciationScorer {
  static const _diphthongs = {'aɪ', 'aʊ', 'eɪ', 'əʊ', 'oʊ', 'ɔɪ', 'ɪə', 'eə', 'ʊə'};

  static const _units = [
    'tʃ', 'dʒ', 'aɪ', 'aʊ', 'eɪ', 'əʊ', 'oʊ', 'ɔɪ', 'ɪə', 'eə', 'ʊə',
    'iː', 'uː', 'ɑː', 'ɔː', 'ɜː',
    'θ', 'ð', 'ʃ', 'ʒ', 'ŋ', 'ɡ',
    'ə', 'ɪ', 'ʊ', 'ɒ', 'ʌ', 'æ', 'ɑ', 'ɔ', 'ɜ',
    'i', 'u', 'e', 'o', 'ɛ', 'ɐ',
    'p', 'b', 't', 'd', 'k', 'g', 'f', 'v', 's', 'z', 'h', 'm', 'n', 'l', 'r', 'w', 'j', 'ɹ',
  ];

  static PronunciationVerdict score({
    required String targetText,
    required String phonetic,
    required String recognized,
    required PronunciationStrictness strictness,
  }) {
    final target = _squash(targetText);
    final heard = _squash(recognized);
    final phones = _parsePhonetic(phonetic);
    final exact = heard == target ||
        recognized
            .split(RegExp(r'\s+'))
            .any((word) => _squash(word) == target);

    if (phones.isEmpty) {
      final passed = exact;
      return PronunciationVerdict(
        passed: passed,
        stars: passed ? 3 : 1,
        phonemes: const [],
        focusSymbol: null,
        hint: passed ? '' : '再读一次这个单词',
      );
    }

    if (exact) {
      return PronunciationVerdict(
        passed: true,
        stars: 3,
        phonemes: [for (final phone in phones) PhonemeMark(symbol: phone, ok: true)],
        focusSymbol: null,
        hint: '',
      );
    }

    final coverage = _coverage(target, recognized);
    var okCount = (phones.length * coverage).round().clamp(0, phones.length);
    if (okCount == phones.length) okCount = phones.length - 1;
    final marks = <PhonemeMark>[
      for (var i = 0; i < phones.length; i++)
        PhonemeMark(symbol: phones[i], ok: i < okCount),
    ];
    final weak = marks.where((mark) => !mark.ok).map((mark) => mark.symbol).toList();
    final loosePass = strictness == PronunciationStrictness.loose &&
        weak.length == 1 &&
        !_diphthongs.contains(weak.first);
    final focus = weak.isEmpty ? null : weak.first;
    return PronunciationVerdict(
      passed: loosePass,
      stars: loosePass ? 2 : 1,
      phonemes: marks,
      focusSymbol: focus,
      hint: focus == null ? '再读一次这个单词' : '再读一下 /$focus/',
    );
  }

  static double _coverage(String target, String recognized) {
    if (target.isEmpty) return 0;
    var best = 0;
    final tokens = recognized.split(RegExp(r'\s+')).where((token) => token.isNotEmpty);
    for (final token in tokens) {
      final squashed = _squash(token);
      best = best > _matchedPrefix(target, squashed) ? best : _matchedPrefix(target, squashed);
    }
    final whole = _squash(recognized);
    best = best > _matchedPrefix(target, whole) ? best : _matchedPrefix(target, whole);
    return best / target.length;
  }

  static int _matchedPrefix(String target, String heard) {
    final limit = target.length < heard.length ? target.length : heard.length;
    var count = 0;
    for (var i = 0; i < limit; i++) {
      if (target[i] != heard[i]) break;
      count++;
    }
    if (count > 0) return count;
    var distance = _levenshtein(target, heard);
    final matched = target.length - distance;
    return matched < 0 ? 0 : matched;
  }

  static List<String> _parsePhonetic(String phonetic) {
    var text = phonetic.toLowerCase();
    text = text.replaceAll(RegExp(r'us:|uk:'), ' ');
    text = text.replaceAll(RegExp(r'[\[\]\(\)/ˈˌ\.\,\s]'), '');
    final phones = <String>[];
    var index = 0;
    while (index < text.length) {
      String? matched;
      for (final unit in _units) {
        if (text.startsWith(unit, index)) {
          matched = unit;
          break;
        }
      }
      if (matched == null) {
        index++;
        continue;
      }
      phones.add(matched);
      index += matched.length;
    }
    return phones;
  }

  static String _squash(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  }

  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    final rows = List.generate(s.length + 1, (i) => List.filled(t.length + 1, 0));
    for (var i = 0; i <= s.length; i++) {
      rows[i][0] = i;
    }
    for (var j = 0; j <= t.length; j++) {
      rows[0][j] = j;
    }
    for (var i = 1; i <= s.length; i++) {
      for (var j = 1; j <= t.length; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;
        final delete = rows[i - 1][j] + 1;
        final insert = rows[i][j - 1] + 1;
        final replace = rows[i - 1][j - 1] + cost;
        var best = delete < insert ? delete : insert;
        if (replace < best) best = replace;
        rows[i][j] = best;
      }
    }
    return rows[s.length][t.length];
  }
}
