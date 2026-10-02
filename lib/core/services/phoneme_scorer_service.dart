import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../speech/phoneme_aligner.dart';
import '../speech/phoneme_ort_worker.dart';
import 'offline_asr_service.dart';
import 'pronunciation_settings.dart';

const _modelUrls = [
  'https://modelscope.cn/models/onnx-community/wav2vec2-lv-60-espeak-cv-ft-ONNX/resolve/master/onnx/model_int8.onnx',
  'https://hf-mirror.com/onnx-community/wav2vec2-lv-60-espeak-cv-ft-ONNX/resolve/main/onnx/model_int8.onnx',
];

const _modelFileName = 'model_int8.onnx';
const _vocabAsset = 'assets/models/espeak_phoneme_vocab.json';
const _minBytes = 250 * 1024 * 1024;

class PhonemeScorerException implements Exception {
  final String message;

  const PhonemeScorerException(this.message);

  @override
  String toString() => message;
}

class PhonemeScorerService {
  PhonemeScorerService._();

  static final PhonemeScorerService instance = PhonemeScorerService._();

  final PhonemeOrtClient _ort = PhonemeOrtClient();
  Future<void>? _sessionFuture;
  Future<void>? _downloadFuture;
  int _generation = 0;
  Map<String, int>? _tokens;
  int _blankId = 0;

  Future<Directory> _modelDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'phoneme_asr'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _modelFile() async {
    final dir = await _modelDirectory();
    return File(p.join(dir.path, _modelFileName));
  }

  Future<bool> isInstalled() async {
    final file = await _modelFile();
    if (!await file.exists()) return false;
    return await file.length() >= _minBytes;
  }

  Future<void> download({void Function(double progress)? onProgress}) {
    return _downloadFuture ??= _download(onProgress).whenComplete(() {
      _downloadFuture = null;
    });
  }

  Future<void> _download(void Function(double progress)? onProgress) async {
    if (await isInstalled()) {
      onProgress?.call(1);
      return;
    }
    final dest = await _modelFile();
    final part = File('${dest.path}.part');
    Object? lastError;
    for (final url in _modelUrls) {
      try {
        await _downloadUrl(url, part, onProgress);
        if (await part.length() < _minBytes) {
          throw const PhonemeScorerException('下载到的模型不完整');
        }
        final header = await part.openRead(0, 1).first;
        if (header.isNotEmpty && header.first == 0x3c) {
          throw const PhonemeScorerException('下载到的不是模型文件');
        }
        if (await dest.exists()) await dest.delete();
        await part.rename(dest.path);
        onProgress?.call(1);
        return;
      } catch (e) {
        lastError = e;
        debugPrint('Phoneme model download failed from $url: $e');
        if (await part.exists()) {
          await part.delete();
        }
      }
    }
    throw PhonemeScorerException(lastError?.toString() ?? '下载失败');
  }

  Future<void> _downloadUrl(
    String url,
    File dest,
    void Function(double progress)? onProgress,
  ) async {
    final client = http.Client();
    try {
      await _downloadWithClient(client, url, dest, onProgress, 0);
    } finally {
      client.close();
    }
  }

  Future<void> _downloadWithClient(
    http.Client client,
    String url,
    File dest,
    void Function(double progress)? onProgress,
    int hops,
  ) async {
    if (hops > 3) {
      throw const PhonemeScorerException('下载地址无效');
    }
    final response = await _send(client, url);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw PhonemeScorerException('下载失败（${response.statusCode}）');
    }

    final sink = dest.openWrite();
    var received = 0;
    var checked = false;
    final total = response.contentLength ?? 0;
    try {
      await for (final chunk in response.stream) {
        if (!checked) {
          checked = true;
          if (chunk.isNotEmpty && chunk.first == 0x3c) {
            await sink.close();
            if (await dest.exists()) await dest.delete();
            final rest = await response.stream.bytesToString();
            final page = utf8.decode(chunk) + rest;
            final href = RegExp(r'href="([^"]+)"').firstMatch(page)?.group(1);
            if (href == null) {
              throw const PhonemeScorerException('下载地址无效');
            }
            await _downloadWithClient(
              client,
              href.replaceAll('&amp;', '&'),
              dest,
              onProgress,
              hops + 1,
            );
            return;
          }
        }
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          onProgress?.call((received / total).clamp(0, 0.99));
        }
      }
    } finally {
      try {
        await sink.close();
      } catch (_) {}
    }
  }

  Future<http.StreamedResponse> _send(http.Client client, String url) {
    final request = http.Request('GET', Uri.parse(url));
    request.headers['User-Agent'] = 'Mozilla/5.0';
    return client.send(request).timeout(const Duration(seconds: 30));
  }

  /// 播放标准音时预加载。没有下载则什么都不做。
  Future<void> warmUp() async {
    if (!await isInstalled()) return;
    OfflineAsrService.instance.release();
    await _ensureSession();
  }

  bool _sessionReady = false;

  Future<void> release() async {
    _generation++;
    _sessionFuture = null;
    _sessionReady = false;
    await _ort.close();
  }

  Future<PhonemeVerdict> score({
    required Float32List samples,
    required String phonetic,
    required PronunciationStrictness strictness,
  }) async {
    if (samples.isEmpty) {
      throw const PhonemeScorerException('没有听清，请再试一次');
    }
    OfflineAsrService.instance.release();
    await _ensureSession();
    final tokens = await _loadTokens();
    final normalized = _normalize(_speechRegion(samples));
    final output = await _ort.run(normalized).timeout(const Duration(seconds: 45));
    final logProbs = _logSoftmax(output.values, output.frames, output.vocab);
    return PhonemeAligner.score(
      phonetic: phonetic,
      logProbs: logProbs,
      frames: output.frames,
      vocab: output.vocab,
      tokens: tokens,
      blankId: _blankId,
      strictness: strictness,
    );
  }

  Future<void> _ensureSession() async {
    if (_sessionReady) return;
    final generation = _generation;
    try {
      _sessionFuture ??= _loadSession(generation);
      await _sessionFuture;
    } catch (e) {
      _sessionFuture = null;
      rethrow;
    }
    if (!_sessionReady) {
      _sessionFuture = null;
      if (generation != _generation) return _ensureSession();
      throw const PhonemeScorerException('音素评分还没准备好');
    }
  }

  Future<void> _loadSession(int generation) async {
    final file = await _modelFile();
    if (!await file.exists()) {
      throw const PhonemeScorerException('音素评分模型还没下载');
    }
    await _ort.open(file.path).timeout(const Duration(seconds: 60));
    if (generation != _generation) {
      await _ort.close();
      return;
    }
    _sessionReady = true;
  }

  Future<Map<String, int>> _loadTokens() async {
    final cached = _tokens;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(_vocabAsset);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const PhonemeScorerException('音素词表损坏');
    }
    final tokens = <String, int>{};
    for (final entry in decoded.entries) {
      final id = entry.value;
      if (id is int) tokens[entry.key.toString()] = id;
    }
    _blankId = tokens['<pad>'] ?? 0;
    _tokens = tokens;
    return tokens;
  }

  Float32List _speechRegion(Float32List samples) {
    const rate = 16000;
    const window = 160;
    const threshold = 0.012;
    int? first;
    var last = 0;
    for (var i = 0; i + window <= samples.length; i += window) {
      var energy = 0.0;
      for (var j = 0; j < window; j++) {
        final sample = samples[i + j];
        energy += sample * sample;
      }
      if (energy / window >= threshold * threshold) {
        first ??= i;
        last = i + window;
      }
    }
    if (first == null) return samples;
    const pad = rate * 60 ~/ 1000;
    final start = first - pad < 0 ? 0 : first - pad;
    final end = last + pad > samples.length ? samples.length : last + pad;
    if (end - start < rate ~/ 5) return samples;
    return Float32List.sublistView(samples, start, end);
  }

  Float32List _normalize(Float32List samples) {
    var mean = 0.0;
    for (final sample in samples) {
      mean += sample;
    }
    mean /= samples.length;
    var variance = 0.0;
    for (final sample in samples) {
      final delta = sample - mean;
      variance += delta * delta;
    }
    variance /= samples.length;
    final scale = math.sqrt(variance + 1e-7);
    final normalized = Float32List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      normalized[i] = (samples[i] - mean) / scale;
    }
    return normalized;
  }

  Float64List _logSoftmax(List<dynamic> logits, int frames, int vocab) {
    final logProbs = Float64List(frames * vocab);
    for (var frame = 0; frame < frames; frame++) {
      final offset = frame * vocab;
      var maxValue = (logits[offset] as num).toDouble();
      for (var id = 1; id < vocab; id++) {
        final value = (logits[offset + id] as num).toDouble();
        if (value > maxValue) maxValue = value;
      }
      var sum = 0.0;
      for (var id = 0; id < vocab; id++) {
        sum += math.exp((logits[offset + id] as num).toDouble() - maxValue);
      }
      final logZ = maxValue + math.log(sum);
      for (var id = 0; id < vocab; id++) {
        logProbs[offset + id] = (logits[offset + id] as num).toDouble() - logZ;
      }
    }
    return logProbs;
  }
}
