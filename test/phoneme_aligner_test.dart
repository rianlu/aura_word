import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aura_word/core/services/pronunciation_settings.dart';
import 'package:aura_word/core/speech/phoneme_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, int> tokens;

  setUpAll(() {
    final raw = File('assets/models/espeak_phoneme_vocab.json').readAsStringSync();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    tokens = decoded.map((key, value) => MapEntry(key, value as int));
  });

  test('课本 without 拆成 w ɪ ð aʊ t', () {
    expect(
      PhonemeAligner.symbolsFor('/wɪðˈaʊt/', tokens),
      ['w', 'ɪ', 'ð', 'aʊ', 't'],
    );
  });

  test('r 和 g 映射到模型里的英语音素', () {
    expect(PhonemeAligner.symbolsFor('/rʌn/', tokens), ['r', 'ʌ', 'n']);
    expect(PhonemeAligner.symbolsFor('/ɡəʊ/', tokens), ['ɡ', 'əʊ']);
    expect(PhonemeAligner.symbolsFor('/goʊ/', tokens), ['g', 'oʊ']);
  });

  test('音和课本音标对齐时通过', () {
    final phones = PhonemeAligner.symbolsFor('/wɪðˈaʊt/', tokens);
    final ids = [for (final phone in phones) tokens[phone]!];
    final verdict = PhonemeAligner.score(
      phonetic: '/wɪðˈaʊt/',
      logProbs: _peaked(ids, peak: 0.9),
      frames: ids.length * 3,
      vocab: 392,
      tokens: tokens,
      blankId: tokens['<pad>']!,
      strictness: PronunciationStrictness.strict,
    );
    expect(verdict.passed, isTrue);
    expect(verdict.stars, 3);
    expect(verdict.phonemes.every((phone) => phone.ok), isTrue);
  });

  test('只有一个短音偏弱时宽松可以通过', () {
    final phones = PhonemeAligner.symbolsFor('/wɪðˈaʊt/', tokens);
    final ids = [for (final phone in phones) tokens[phone]!];
    final peaks = [0.9, 0.9, 0.9, 0.9, 0.08];
    final verdict = PhonemeAligner.score(
      phonetic: '/wɪðˈaʊt/',
      logProbs: _peaked(ids, peaks: peaks),
      frames: ids.length * 3,
      vocab: 392,
      tokens: tokens,
      blankId: tokens['<pad>']!,
      strictness: PronunciationStrictness.loose,
    );
    expect(verdict.passed, isTrue);
    expect(verdict.stars, 2);
    expect(verdict.hint, '再读一下 /t/');
  });

  test('双元音偏弱时宽松也不通过', () {
    final phones = PhonemeAligner.symbolsFor('/wɪðˈaʊt/', tokens);
    final ids = [for (final phone in phones) tokens[phone]!];
    final peaks = [0.9, 0.9, 0.9, 0.08, 0.9];
    final verdict = PhonemeAligner.score(
      phonetic: '/wɪðˈaʊt/',
      logProbs: _peaked(ids, peaks: peaks),
      frames: ids.length * 3,
      vocab: 392,
      tokens: tokens,
      blankId: tokens['<pad>']!,
      strictness: PronunciationStrictness.loose,
    );
    expect(verdict.passed, isFalse);
    expect(verdict.phonemes[3].ok, isFalse);
  });

  test('整段都对不上时不通过', () {
    final frames = 12;
    const vocab = 392;
    final logProbs = Float64List(frames * vocab);
    final rest = math.log(0.01 / (vocab - 1));
    for (var frame = 0; frame < frames; frame++) {
      for (var id = 0; id < vocab; id++) {
        logProbs[frame * vocab + id] = id == 9 ? math.log(0.99) : rest;
      }
    }
    final verdict = PhonemeAligner.score(
      phonetic: '/wɪðˈaʊt/',
      logProbs: logProbs,
      frames: frames,
      vocab: vocab,
      tokens: tokens,
      blankId: tokens['<pad>']!,
      strictness: PronunciationStrictness.loose,
    );
    expect(verdict.passed, isFalse);
  });
}

Float64List _peaked(List<int> phoneIds, {double peak = 0.9, List<double>? peaks}) {
  const vocab = 392;
  final frames = phoneIds.length * 3;
  final data = Float64List(frames * vocab);
  for (var phone = 0; phone < phoneIds.length; phone++) {
    final height = peaks == null ? peak : peaks[phone];
    final rest = math.log((1 - height) / (vocab - 1));
    final high = math.log(height);
    for (var step = 0; step < 3; step++) {
      final frame = phone * 3 + step;
      for (var id = 0; id < vocab; id++) {
        data[frame * vocab + id] = id == phoneIds[phone] ? high : rest;
      }
    }
  }
  return data;
}
