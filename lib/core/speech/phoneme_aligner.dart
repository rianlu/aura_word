import 'dart:math' as math;
import 'dart:typed_data';

import '../services/pronunciation_settings.dart';
import 'pronunciation_scorer.dart';

class PhonemeVerdict {
  final bool passed;
  final int stars;
  final List<PhonemeMark> phonemes;
  final String heard;
  final String hint;

  const PhonemeVerdict({
    required this.passed,
    required this.stars,
    required this.phonemes,
    required this.heard,
    required this.hint,
  });
}

class _TargetPhone {
  final String symbol;
  final int id;

  const _TargetPhone(this.symbol, this.id);
}

/// 把录音的音素概率对齐到课本音标，不拿听写文字做判断。
class PhonemeAligner {
  static const _diphthongs = {
    'aɪ', 'aʊ', 'eɪ', 'əʊ', 'oʊ', 'ɔɪ', 'ɪə', 'eə', 'ʊə', 'iə',
  };

  static const _looseCut = 0.22;
  static const _strictCut = 0.45;
  static const _looseFloor = 0.16;
  static const _strictFloor = 0.28;

  static List<String> symbolsFor(String phonetic, Map<String, int> tokens) {
    return _targets(phonetic, tokens).map((phone) => phone.symbol).toList();
  }

  static PhonemeVerdict score({
    required String phonetic,
    required Float64List logProbs,
    required int frames,
    required int vocab,
    required Map<String, int> tokens,
    required int blankId,
    required PronunciationStrictness strictness,
  }) {
    final heard = _greedy(logProbs, frames, vocab, tokens, blankId);
    final targets = _targets(phonetic, tokens);
    if (targets.isEmpty || frames <= 0 || vocab <= 0) {
      return PhonemeVerdict(
        passed: false,
        stars: 1,
        phonemes: const [],
        heard: heard,
        hint: '再读一次这个单词',
      );
    }

    final posteriors = _align(
      logProbs: logProbs,
      frames: frames,
      vocab: vocab,
      targets: targets,
      blankId: blankId,
    );
    final strict = strictness == PronunciationStrictness.strict;
    final cut = strict ? _strictCut : _looseCut;
    final floor = strict ? _strictFloor : _looseFloor;
    final mean = posteriors.fold<double>(0, (sum, value) => sum + value) /
        posteriors.length;
    final belowFloor = mean < floor;
    final marks = <PhonemeMark>[
      for (var i = 0; i < targets.length; i++)
        PhonemeMark(
          symbol: targets[i].symbol,
          ok: !belowFloor && posteriors[i] >= cut,
        ),
    ];
    final weak = marks.where((mark) => !mark.ok).map((mark) => mark.symbol).toList();
    final loosePass = !strict &&
        weak.length == 1 &&
        !_diphthongs.contains(weak.first);
    final passed = weak.isEmpty || loosePass;
    final focus = weak.isEmpty ? null : weak.first;
    return PhonemeVerdict(
      passed: passed,
      stars: weak.isEmpty ? 3 : (loosePass ? 2 : 1),
      phonemes: marks,
      heard: heard,
      hint: focus == null ? '' : (weak.length == 1 ? '再读一下 /$focus/' : '再读一次这个单词'),
    );
  }

  static List<_TargetPhone> _targets(String phonetic, Map<String, int> tokens) {
    final keys = tokens.keys
        .where((key) => key.isNotEmpty && !key.startsWith('<'))
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var text = phonetic.toLowerCase().replaceAll(':', 'ː');
    text = text.replaceAll(RegExp(r"[\[\]\(\)/ˈˌ'\.\s]"), '');
    final phones = <_TargetPhone>[];
    var index = 0;
    while (index < text.length) {
      if (text.startsWith('ɪə', index) && tokens.containsKey('iə')) {
        phones.add(_TargetPhone('ɪə', tokens['iə']!));
        index += 2;
        continue;
      }
      if (text.startsWith('r', index) && tokens.containsKey('ɹ')) {
        phones.add(_TargetPhone('r', tokens['ɹ']!));
        index += 1;
        continue;
      }
      if (text.startsWith('g', index) && tokens.containsKey('ɡ')) {
        phones.add(_TargetPhone('g', tokens['ɡ']!));
        index += 1;
        continue;
      }
      String? token;
      for (final key in keys) {
        if (text.startsWith(key, index)) {
          token = key;
          break;
        }
      }
      if (token == null) {
        index++;
        continue;
      }
      phones.add(_TargetPhone(token, tokens[token]!));
      index += token.length;
    }
    return phones;
  }

  static List<double> _align({
    required Float64List logProbs,
    required int frames,
    required int vocab,
    required List<_TargetPhone> targets,
    required int blankId,
  }) {
    final states = <int>[blankId];
    for (final phone in targets) {
      states.add(phone.id);
      states.add(blankId);
    }
    final stateCount = states.length;
    const negative = -1e30;
    final dp = List.generate(frames, (_) => Float64List(stateCount));
    final back = List.generate(frames, (_) => Int32List(stateCount));
    for (var frame = 0; frame < frames; frame++) {
      for (var state = 0; state < stateCount; state++) {
        dp[frame][state] = negative;
      }
    }
    dp[0][0] = _at(logProbs, vocab, 0, states[0]);
    if (stateCount > 1) {
      dp[0][1] = _at(logProbs, vocab, 0, states[1]);
    }

    for (var frame = 1; frame < frames; frame++) {
      for (var state = 0; state < stateCount; state++) {
        var best = dp[frame - 1][state];
        var from = state;
        if (state > 0 && dp[frame - 1][state - 1] > best) {
          best = dp[frame - 1][state - 1];
          from = state - 1;
        }
        final label = states[state];
        if (state > 1 &&
            label != blankId &&
            label != states[state - 2] &&
            dp[frame - 1][state - 2] > best) {
          best = dp[frame - 1][state - 2];
          from = state - 2;
        }
        dp[frame][state] = _at(logProbs, vocab, frame, label) + best;
        back[frame][state] = from;
      }
    }

    var end = stateCount - 1;
    if (stateCount > 1 && dp[frames - 1][stateCount - 2] > dp[frames - 1][end]) {
      end = stateCount - 2;
    }
    final sums = List<double>.filled(targets.length, 0);
    final counts = List<int>.filled(targets.length, 0);
    var state = end;
    for (var frame = frames - 1; frame >= 0; frame--) {
      if (state.isOdd) {
        final phoneIndex = (state - 1) >> 1;
        if (phoneIndex >= 0 && phoneIndex < targets.length) {
          sums[phoneIndex] += math.exp(_at(logProbs, vocab, frame, states[state]));
          counts[phoneIndex] += 1;
        }
      }
      if (frame == 0) break;
      state = back[frame][state];
    }
    return [
      for (var i = 0; i < targets.length; i++)
        counts[i] == 0 ? 0.0 : sums[i] / counts[i],
    ];
  }

  static String _greedy(
    Float64List logProbs,
    int frames,
    int vocab,
    Map<String, int> tokens,
    int blankId,
  ) {
    if (frames <= 0 || vocab <= 0) return '';
    final idToToken = <int, String>{
      for (final entry in tokens.entries)
        if (!entry.key.startsWith('<')) entry.value: entry.key,
    };
    final pieces = <String>[];
    var previous = -1;
    for (var frame = 0; frame < frames; frame++) {
      var bestId = 0;
      var best = _at(logProbs, vocab, frame, 0);
      for (var id = 1; id < vocab; id++) {
        final value = _at(logProbs, vocab, frame, id);
        if (value > best) {
          best = value;
          bestId = id;
        }
      }
      if (bestId == previous) continue;
      previous = bestId;
      if (bestId == blankId || bestId < 4) continue;
      final token = idToToken[bestId];
      if (token != null && token.isNotEmpty) pieces.add(token);
    }
    return pieces.join(' ');
  }

  static double _at(Float64List logProbs, int vocab, int frame, int id) {
    final index = frame * vocab + id;
    if (index < 0 || index >= logProbs.length) return -1e30;
    return logProbs[index];
  }
}
