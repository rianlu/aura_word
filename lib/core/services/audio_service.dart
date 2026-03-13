import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:aura_word/core/database/models/word.dart';

/// 音频发音类型
enum AudioType {
  us, // 美式发音
  uk, // 英式发音
}

/// 音频服务
///
/// 统一管理应用内的音频播放，包括：
/// * 单词发音 (支持 Youdao API, Google Oxford API 和系统 TTS 降级)
/// * 例句发音 (优先 Youdao API，降级到 TTS)
/// * 音效播放 (正确/错误/麦克风提示音，支持预加载)
/// * 通用 URL 音频播放 (支持缓存)
class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  // 核心播放器组件
  final AudioPlayer _audioPlayer = AudioPlayer(); // 主音频播放器 (用于单词、例句、URL)
  final FlutterTts _flutterTts = FlutterTts();    // 系统 TTS 引擎
  final DefaultCacheManager _cacheManager = DefaultCacheManager(); // 音频缓存管理

  // 音效专用播放器 (分离实例以支持重叠播放或独立控制)
  final AudioPlayer _sfxCorrect = AudioPlayer();
  final AudioPlayer _sfxWrong = AudioPlayer();
  final AudioPlayer _sfxMic = AudioPlayer();

  /// 服务是否已初始化
  bool _isInit = false;

  /// 初始化音频服务
  ///
  /// 配置 TTS 语言、语速，并预加载常用音效。
  Future<void> init() async {
    if (_isInit) return;
    
    // 配置 TTS
    await _flutterTts.awaitSpeakCompletion(true); // 等待说完再返回
    await _flutterTts.setLanguage("en-GB");       // 默认使用英式英语
    await _flutterTts.setSpeechRate(0.5);         // 设置较慢语速以适合学习
    
    // 预加载音效资源
    try {
        await _sfxCorrect.setSource(AssetSource('sounds/correct.mp3'));
        await _sfxCorrect.setReleaseMode(ReleaseMode.stop); // 播放完自动停止并重置
        
        await _sfxWrong.setSource(AssetSource('sounds/wrong.mp3'));
        await _sfxWrong.setReleaseMode(ReleaseMode.stop);

        await _sfxMic.setSource(AssetSource('sounds/mic_start.mp3'));
        await _sfxMic.setReleaseMode(ReleaseMode.stop);
    } catch (e) {
        debugPrint("SFX Preload Error: $e");
    }

    _isInit = true;
  }

  /// 播放单词发音
  ///
  /// 策略链：
  /// 1. 尝试 Youdao API (支持美音/英音参数)
  /// 2. (仅单次且为英文) 尝试 Google Oxford API (高质量真人发音)
  /// 3. 系统 TTS (兜底方案)
  Future<void> playWord(Word word, {AudioType type = AudioType.uk}) async {
    try {
      if (!_isInit) await init(); 

      // 停止当前所有播放
      _audioPlayer.stop();
      _flutterTts.stop();

      // 1. 尝试 Youdao API
      // type=0: 美音, type=1: 英音
      if (_isEnglish(word.text)) {
        final int apiType = type == AudioType.us ? 0 : 1;
        final String url = "https://dict.youdao.com/dictvoice?type=$apiType&audio=${Uri.encodeComponent(word.text)}";
        
        try {
          // 优先查缓存
          final FileInfo? cachedFile = await _cacheManager.getFileFromCache(url);
          if (cachedFile != null && await cachedFile.file.exists()) {
             await _audioPlayer.play(DeviceFileSource(cachedFile.file.path));
             try {
                await _audioPlayer.onPlayerComplete.first.timeout(const Duration(seconds: 10));
             } catch (_) {}
             return;
          }

          // 下载并播放
          File file = await _cacheManager.getSingleFile(url);
          if (await file.exists()) {
             await _audioPlayer.play(DeviceFileSource(file.path));
             try {
                await _audioPlayer.onPlayerComplete.first.timeout(const Duration(seconds: 10));
             } catch (_) {}
             return;
          }
        } catch (e) {
          debugPrint("Youdao API failed for ${word.text}, falling back to Google. Error: $e");
        }
      }

      // 2. 尝试 Google Oxford API (Youdao 失败后的备选)
      // 仅适用于单个英文单词
      bool isSingleWord = !word.text.trim().contains(' ');
      
      if (isSingleWord && _isEnglish(word.text)) {
        try {
           final String cleanWord = word.text.trim().toLowerCase();
           // Google Oxford API URL 格式
           final String googleUrl = "https://ssl.gstatic.com/dictionary/static/sounds/oxford/$cleanWord--_gb_1.mp3";
           
           // 优先查缓存
           final FileInfo? cachedFile = await _cacheManager.getFileFromCache(googleUrl);
           if (cachedFile != null && await cachedFile.file.exists()) {
             await _audioPlayer.play(DeviceFileSource(cachedFile.file.path));
             try {
                await _audioPlayer.onPlayerComplete.first.timeout(const Duration(seconds: 10));
             } catch (_) {}
             return;
           }

           // 下载并播放
           File file = await _cacheManager.getSingleFile(googleUrl);
           if (await file.exists()) {
             await _audioPlayer.play(DeviceFileSource(file.path));
             try {
                await _audioPlayer.onPlayerComplete.first.timeout(const Duration(seconds: 10));
             } catch (_) {}
             return;
           }
        } catch (e) {
          debugPrint("Google API failed for ${word.text}, falling back to TTS. Error: $e");
        }
      }
      
      // 3. 系统 TTS (最后的兜底)
      debugPrint("Falling back to TTS for: ${word.text}");
      if (!_isInit) await init(); // 双重检查初始化
      await _flutterTts.speak(word.text);
      await _flutterTts.awaitSpeakCompletion(true);
      
    } catch (e) {
      debugPrint("Audio playback init failed: $e");
    }
  }

  /// 播放例句
  ///
  /// 优先使用 Youdao API (支持长句自然发音)，失败则降级到 TTS。
  Future<void> playSentence(String sentence) async {
      try {
        await stop();

        // 尝试网络发音接口
        if (_isEnglish(sentence)) {
             // 默认请求英音(type=1)
             final String url = "https://dict.youdao.com/dictvoice?type=1&audio=${Uri.encodeComponent(sentence)}";
              try {
                File file = await _cacheManager
                    .getSingleFile(url)
                    .timeout(const Duration(seconds: 12));
                if (await file.exists()) {
                   await _audioPlayer.play(DeviceFileSource(file.path));
                   await _audioPlayer.onPlayerComplete.first.timeout(const Duration(seconds: 20));
                   return;
                }
              } catch (e) {
                debugPrint("Sentence Cache error: $e");
              }
        }

        // 降级 TTS
        if (!_isInit) await init();
        await _flutterTts.speak(sentence);

      } catch (e) {
        debugPrint("Sentence playback failed: $e");
      }
  }

  /// 播放本地音效资源
  ///
  /// [fileName] 为 assets/sounds/ 下的文件名，如 "correct.mp3"
  Future<void> playAsset(String fileName) async {
    try {
       // 针对常用音效使用预加载的专用播放器，降低延迟
       if (fileName.contains('correct')) {
           if (_sfxCorrect.state == PlayerState.playing) await _sfxCorrect.stop();
           await _sfxCorrect.resume(); // resume 可用于重复播放预加载资源
       } else if (fileName.contains('wrong')) {
           if (_sfxWrong.state == PlayerState.playing) await _sfxWrong.stop();
           await _sfxWrong.resume();
       } else if (fileName.contains('mic')) {
           if (_sfxMic.state == PlayerState.playing) await _sfxMic.stop();
           await _sfxMic.resume();
       } else {
           // 其他非常用音效使用临时播放器（用完即焚）
           final tempPlayer = AudioPlayer();
           await tempPlayer.play(AssetSource('sounds/$fileName'));
           tempPlayer.onPlayerComplete.listen((_) => tempPlayer.dispose());
       }
    } catch (e) {
      debugPrint("Asset playback failed ($fileName): $e");
    }
  }

  /// 停止所有正在播放的音频
  Future<void> stop() async {
    await _audioPlayer.stop();
    await _flutterTts.stop();
    await _sfxCorrect.stop();
    await _sfxWrong.stop();
    await _sfxMic.stop();
  }

  /// 播放任意 URL 音频
  ///
  /// 支持缓存。如果播放失败，可指定 [fallbackText] 进行 TTS 朗读。
  Future<void> playUrl(String url, {String? fallbackText}) async {
    // URL 有效性检查
    if (url.isEmpty || !url.startsWith('http')) {
      debugPrint("AudioService: No valid URL found ($url), using TTS fallback...");
      if (fallbackText != null && fallbackText.isNotEmpty) {
        if (!_isInit) await init();
        await stop();
        await _flutterTts.speak(fallbackText);
        await _flutterTts.awaitSpeakCompletion(true);
      }
      return;
    }

    try {
      debugPrint("AudioService: Attempting to play URL: $url");
      if (!_isInit) await init();
      await stop(); 
      
      bool playedSuccessfully = false;

      // 等待播放完成的帮助函数
      Future<void> wait() async {
        try {
          await _audioPlayer.onPlayerComplete.first.timeout(const Duration(seconds: 20));
        } catch (e) {
          debugPrint("AudioService: Playback finished or timed out: $e");
        }
      }

      try {
        // 1. 尝试从缓存播放
        final FileInfo? cachedFile = await _cacheManager.getFileFromCache(url);
        if (cachedFile != null && await cachedFile.file.exists()) {
          debugPrint("AudioService: Playing from cache: ${cachedFile.file.path}");
          await _audioPlayer.play(DeviceFileSource(cachedFile.file.path));
          await wait();
          playedSuccessfully = true;
        } else {
          // 2. 尝试下载并播放
          debugPrint("AudioService: Downloading to cache...");
          File file = await _cacheManager.getSingleFile(url);
          if (await file.exists()) {
            debugPrint("AudioService: Downloaded, playing: ${file.path}");
            await _audioPlayer.play(DeviceFileSource(file.path));
            await wait();
            playedSuccessfully = true;
          }
        }
      } catch (e) {
        // 3. 缓存失败，尝试直接流式播放
        debugPrint("AudioService: Cache/Direct file playback failed: $e. Trying direct URL source...");
        try {
          await _audioPlayer.play(UrlSource(url));
          await wait();
          playedSuccessfully = true;
        } catch (e2) {
          debugPrint("AudioService: Direct URL source also failed: $e2");
        }
      }

      // 4. 所有尝试均失败，降级到 TTS
      if (!playedSuccessfully && fallbackText != null && fallbackText.isNotEmpty) {
        debugPrint("AudioService: All URL sources failed. Falling back to system TTS for: $fallbackText");
        _flutterTts.stop();
        await _flutterTts.speak(fallbackText);
        await _flutterTts.awaitSpeakCompletion(true);
      }
      
    } catch (e) {
      debugPrint("AudioService: playUrl Critical Error: $e");
    }
  }
  
  /// 简单的正则判断文本是否纯英文
  bool _isEnglish(String text) {
    return RegExp(r"^[a-zA-Z\s\.,\?!'-]+$").hasMatch(text);
  }
}
