import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const _modelUrls = [
  'https://modelscope.cn/models/csukuangfj/asr-models/resolve/master/sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27.tar.bz2',
  'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27.tar.bz2',
];

const _encoderName = 'encoder_model.ort';
const _decoderName = 'decoder_model_merged.ort';
const _tokensName = 'tokens.txt';

class OfflineAsrException implements Exception {
  final String message;

  const OfflineAsrException(this.message);

  @override
  String toString() => message;
}

class OfflineAsrService {
  OfflineAsrService._();

  static final OfflineAsrService instance = OfflineAsrService._();

  final AudioRecorder _recorder = AudioRecorder();
  sherpa.OfflineRecognizer? _recognizer;
  Future<void>? _downloadFuture;
  int _captureGeneration = 0;
  bool _bindingsReady = false;

  Future<Directory> _modelDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'offline_asr', 'moonshine_tiny_en'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<bool> isInstalled() async {
    final dir = await _modelDirectory();
    return await File(p.join(dir.path, _encoderName)).exists() &&
        await File(p.join(dir.path, _decoderName)).exists() &&
        await File(p.join(dir.path, _tokensName)).exists();
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

    final dir = await _modelDirectory();
    final archiveFile = File(p.join(dir.path, 'model.tar.bz2'));
    Object? lastError;

    for (final url in _modelUrls) {
      try {
        await _downloadUrl(url, archiveFile, onProgress);
        onProgress?.call(0.92);
        await compute(_extractMoonshineTarBz2, {
          'src': archiveFile.path,
          'dest': dir.path,
        });
        if (!await isInstalled()) {
          throw const OfflineAsrException('模型文件不完整');
        }
        if (await archiveFile.exists()) {
          await archiveFile.delete();
        }
        onProgress?.call(1);
        return;
      } catch (e) {
        lastError = e;
        debugPrint('Offline ASR download failed from $url: $e');
      }
    }

    throw OfflineAsrException(lastError?.toString() ?? '下载失败');
  }

  Future<void> _downloadUrl(
    String url,
    File dest,
    void Function(double progress)? onProgress,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw OfflineAsrException('下载失败（${response.statusCode}）');
      }

      final total = response.contentLength ?? 0;
      final sink = dest.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) {
            onProgress?.call((received / total) * 0.9);
          }
        }
      } finally {
        await sink.close();
      }

      if (received < 1024 * 1024) {
        throw const OfflineAsrException('下载到的文件不完整');
      }
    } finally {
      client.close();
    }
  }

  void cancelCapture() {
    _captureGeneration++;
    unawaited(_recorder.cancel().then((_) {}, onError: (_) {}));
  }

  Future<void>? _recognizerFuture;

  /// 只加载模型，不打开麦克风。可在播放标准音时调用，避免播完后还要等模型。
  Future<void> warmUp() => _ensureRecognizer();

  Future<String?> captureAndTranscribe({
    required bool Function() isCancelled,
    void Function()? onListening,
    void Function(String text)? onPartial,
  }) async {
    final generation = ++_captureGeneration;
    final permitted = await _recorder.hasPermission();
    if (generation != _captureGeneration || isCancelled()) return null;
    if (!permitted) {
      throw const OfflineAsrException('没有麦克风权限');
    }

    await _ensureRecognizer();
    if (generation != _captureGeneration || isCancelled()) return null;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
    if (generation != _captureGeneration || isCancelled()) {
      await _recorder.cancel();
      return null;
    }
    onListening?.call();

    final pcm = BytesBuilder(copy: false);
    var totalSamples = 0;
    var speechSamples = 0;
    var trailingSilence = 0;
    var heardSpeech = false;
    const sampleRate = 16000;
    const speechRms = 0.008;
    const minSpeechSamples = 16000 * 250 ~/ 1000;
    const silenceSamples = 16000 * 700 ~/ 1000;
    const maxSamples = 16000 * 8;
    const noSpeechSamples = 16000 * 6;
    final timeout = Timer(const Duration(seconds: 10), () {
      if (generation == _captureGeneration) {
        unawaited(_recorder.stop().then((_) {}, onError: (_) {}));
      }
    });

    try {
      await for (final chunk in stream) {
        if (generation != _captureGeneration || isCancelled()) {
          return null;
        }
        if (chunk.length < 2) continue;
        pcm.add(chunk);
        final count = chunk.length ~/ 2;
        final rms = _rmsPcm16(chunk);
        totalSamples += count;
        if (rms >= speechRms) {
          heardSpeech = true;
          speechSamples += count;
          trailingSilence = 0;
        } else if (heardSpeech) {
          trailingSilence += count;
        }

        final speechLongEnough = speechSamples >= minSpeechSamples;
        final endedBySilence = heardSpeech && speechLongEnough && trailingSilence >= silenceSamples;
        final endedByLength = totalSamples >= maxSamples;
        final endedByNoSpeech = !heardSpeech && totalSamples >= noSpeechSamples;
        if (endedBySilence || endedByLength || endedByNoSpeech) {
          break;
        }
      }
    } finally {
      timeout.cancel();
      if (generation == _captureGeneration) {
        await _recorder.stop().then((_) {}, onError: (_) {});
      }
    }

    if (generation != _captureGeneration || isCancelled()) return null;
    if (!heardSpeech || speechSamples < minSpeechSamples) {
      return '';
    }

    final samples = _pcm16ToFloat(pcm.toBytes());
    final text = _transcribe(samples, sampleRate);
    if (text.isNotEmpty) onPartial?.call(text);
    return text;
  }

  Future<void> _ensureRecognizer() async {
    if (_recognizer != null) return;
    try {
      _recognizerFuture ??= _loadRecognizer();
      await _recognizerFuture;
    } catch (e) {
      _recognizerFuture = null;
      rethrow;
    }
  }

  Future<void> _loadRecognizer() async {
    if (!await isInstalled()) {
      throw const OfflineAsrException('离线识别模型还没下载');
    }
    if (!_bindingsReady) {
      await sherpa.initBindingsAsync();
      _bindingsReady = true;
    }
    final dir = await _modelDirectory();
    final config = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        moonshine: sherpa.OfflineMoonshineModelConfig(
          encoder: p.join(dir.path, _encoderName),
          mergedDecoder: p.join(dir.path, _decoderName),
        ),
        tokens: p.join(dir.path, _tokensName),
        numThreads: 2,
        debug: false,
      ),
    );
    _recognizer = sherpa.OfflineRecognizer(config);
  }

  String _transcribe(Float32List samples, int sampleRate) {
    final recognizer = _recognizer;
    if (recognizer == null) {
      throw const OfflineAsrException('离线识别还没准备好');
    }
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  double _rmsPcm16(Uint8List bytes) {
    final count = bytes.length ~/ 2;
    if (count == 0) return 0;
    var sum = 0.0;
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < count; i++) {
      final sample = data.getInt16(i * 2, Endian.little) / 32768.0;
      sum += sample * sample;
    }
    return math.sqrt(sum / count);
  }

  Float32List _pcm16ToFloat(Uint8List bytes) {
    final count = bytes.length ~/ 2;
    final samples = Float32List(count);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < count; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }
}

Future<void> _extractMoonshineTarBz2(Map<String, String> args) async {
  final src = args['src']!;
  final dest = args['dest']!;
  final bytes = await File(src).readAsBytes();
  final tarBytes = BZip2Decoder().decodeBytes(bytes);
  if (tarBytes.length < 1024) {
    throw StateError('模型压缩包无法解压');
  }
  final archive = TarDecoder().decodeBytes(tarBytes);
  const needed = {_encoderName, _decoderName, _tokensName};
  final found = <String>{};
  for (final file in archive) {
    if (!file.isFile) continue;
    final name = p.basename(file.name);
    if (!needed.contains(name)) continue;
    final out = File(p.join(dest, name));
    await out.parent.create(recursive: true);
    await out.writeAsBytes(file.content, flush: true);
    found.add(name);
  }
  if (found.length != needed.length) {
    throw StateError('模型压缩包缺少文件');
  }
}
