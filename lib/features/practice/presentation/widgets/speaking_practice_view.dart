import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/database/models/word.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/audio_service.dart';
import '../../../../core/services/speech_service.dart';
import '../../../../core/utils/phonetic_utils.dart';
import '../../../../core/widgets/animated_speaker_button.dart';

import 'practice_success_overlay.dart';

/// 口语练习状态
enum SpeakingState {
  idle, // 空闲
  playingAudio, // 播放标准音
  listening, // 录音识别中
  processing, // 处理识别结果
  success, // 识别通过
  failed, // 识别失败
}

class SpeakingPracticeView extends StatefulWidget {
  final Word word;
  final Function(int score) onCompleted;
  final bool isReviewMode;
  final bool forceVerticalLayout;

  const SpeakingPracticeView({
    super.key,
    required this.word,
    required this.onCompleted,
    this.isReviewMode = false,
    this.forceVerticalLayout = false,
  });

  @override
  State<SpeakingPracticeView> createState() => _SpeakingPracticeViewState();
}

class _SpeakingPracticeViewState extends State<SpeakingPracticeView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _glowIdleAlpha = 0.22;
  static const double _glowActiveAlpha = 0.36;
  static const double _glowRecordingAlpha = 0.46;
  static const double _glowIdleBlur = 14;
  static const double _glowActiveBlur = 22;
  static const double _glowRecordingBlur = 26;
  static const double _glowIdleYOffset = 4;
  static const double _glowActiveYOffset = 8;
  static const double _glowRecordingYOffset = 10;

  late AnimationController _pulseController;
  StreamSubscription<bool>? _engineListeningSub;

  // 练习状态
  SpeakingState _state = SpeakingState.idle;
  String _lastHeard = ''; // 最近一次识别内容
  bool _hasPlayedAudioForCurrentWord = false; // 本轮是否已播放标准音
  int _sessionToken = 0; // 用于隔离旧异步回调
  bool _isStartingRecognition = false; // 防并发 startListening
  bool _engineIsListening = false; // 引擎底层真实监听状态

  // 计时器
  Timer? _skipTimer;
  Timer? _listenTimeoutTimer;
  Timer? _successTimer;

  // 配置
  static const int _skipButtonDelaySeconds = 3;
  static const int _listenTimeoutSeconds = 16;

  Color get _accentColor =>
      widget.isReviewMode ? AppColors.secondary : AppColors.primary;
  bool get _isLearningMode => !widget.isReviewMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _engineListeningSub = SpeechService().listeningState.listen(
      _handleEngineListeningChanged,
    );

    // 启动练习流程
    _startPractice();
  }

  @override
  void didUpdateWidget(SpeakingPracticeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.word.id != oldWidget.word.id) {
      unawaited(_resetAndRestart());
    }
  }

  Future<void> _resetAndRestart() async {
    _sessionToken++;
    final token = _sessionToken;
    _cancelAllTimers();
    await SpeechService().cancel();
    if (!mounted || token != _sessionToken) return;

    setState(() {
      _state = SpeakingState.idle;
      _lastHeard = '';
      _hasPlayedAudioForCurrentWord = false;
      _isStartingRecognition = false;
    });

    _pulseController.reset();
    await _startPractice(token);
  }

  void _cancelAllTimers() {
    _skipTimer?.cancel();
    _listenTimeoutTimer?.cancel();
    _successTimer?.cancel();
  }

  @override
  void dispose() {
    _sessionToken++;
    _cancelAllTimers();
    _engineListeningSub?.cancel();
    _pulseController.dispose();
    SpeechService().cancel(); // Key 机制保证新实例在旧实例 dispose 后才创建
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleEngineListeningChanged(bool isListening) {
    if (!mounted) return;
    _engineIsListening = isListening;
    if (isListening) return;
    // 引擎意外停止时，UI 主动收敛到失败态，避免界面仍显示“正在监听”
    if (_state == SpeakingState.listening) {
      _handleStartListeningFailed('识别已停止，请重试');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _cancelAllTimers();
      SpeechService().stopListening();
      _pulseController.stop();
      _engineIsListening = false;
      setState(() {
        _state = SpeakingState.failed;
        _lastHeard = '';
      });
      _isStartingRecognition = false;
    }
  }

  /// 启动口语练习流程
  Future<void> _startPractice([int? token]) async {
    final currentToken = token ?? _sessionToken;
    if (!mounted || currentToken != _sessionToken) return;

    // 避免界面切换瞬间触发
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted || currentToken != _sessionToken) return;

    // 播放标准音的同时，后台预初始化语音引擎（避免第一次超时）
    setState(() => _state = SpeakingState.playingAudio);
    unawaited(SpeechService().ensureInitialized());

    await AudioService().playWord(widget.word);
    if (!mounted || currentToken != _sessionToken) return;
    _hasPlayedAudioForCurrentWord = true;

    // 播放完成后进入识别
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted || currentToken != _sessionToken) return;

    // 开始监听
    unawaited(_beginListening(currentToken));
  }

  Future<void> _beginListening([int? token]) async {
    final currentToken = token ?? _sessionToken;
    if (!mounted ||
        currentToken != _sessionToken ||
        _state == SpeakingState.success) {
      return;
    }
    if (_isStartingRecognition) {
      debugPrint(
        'Speaking: _beginListening skipped, recognition start in progress',
      );
      return;
    }

    // 启动前清理旧计时器
    _skipTimer?.cancel();
    _listenTimeoutTimer?.cancel();

    setState(() {
      _state = SpeakingState.processing;
      _lastHeard = '';
    });
    _isStartingRecognition = false;

    bool success = false;
    try {
      success = await _startSpeechRecognition(
        currentToken,
      ).timeout(const Duration(seconds: 12));
    } catch (_) {
      success = false;
    }
    if (!mounted || currentToken != _sessionToken) return;
    if (!success) {
      _handleStartListeningFailed('识别引擎启动超时或失败');
      return;
    }

    setState(() {
      _state = SpeakingState.listening;
    });
    _engineIsListening = true;
    _pulseController.repeat();

    // 控制跳过按钮显示时机
    _skipTimer = Timer(const Duration(seconds: _skipButtonDelaySeconds), () {
      if (mounted) setState(() {}); // 刷新界面
    });

    // 监听超时保护（检测到有效语音后会自动续期）
    _armListenTimeout(currentToken);
  }

  Future<bool> _startSpeechRecognition([int? token]) async {
    final currentToken = token ?? _sessionToken;
    if (!mounted || currentToken != _sessionToken) return false;
    if (_isStartingRecognition) return false;
    _isStartingRecognition = true;
    final success = await SpeechService().startListening(
      onResult: (chunk) {
        if (currentToken != _sessionToken) return; // 过滤旧 session 的结果
        _handleSpeechResult(chunk.text, isFinal: chunk.isFinal);
      },
      onError: (error) {
        debugPrint('Speech error: $error');
        if (mounted &&
            currentToken == _sessionToken &&
            _state == SpeakingState.listening) {
          _handleStartListeningFailed(error);
        }
      },
    );
    _isStartingRecognition = false;
    return success;
  }

  void _handleStartListeningFailed(String reason) {
    debugPrint('Start listening failed: $reason');
    _cancelAllTimers();
    SpeechService().stopListening();
    _pulseController.stop();
    _pulseController.reset();
    _engineIsListening = false;
    setState(() {
      _state = SpeakingState.failed;
      _lastHeard = '';
    });
    _isStartingRecognition = false;
  }

  void _handleListenTimeout([int? token]) {
    final currentToken = token ?? _sessionToken;
    if (currentToken != _sessionToken) return;
    if (!mounted || _state != SpeakingState.listening) return;

    debugPrint('Listen timeout');
    _handleStartListeningFailed('监听超时');
  }

  void _armListenTimeout(int token) {
    _listenTimeoutTimer?.cancel();
    _listenTimeoutTimer = Timer(
      const Duration(seconds: _listenTimeoutSeconds),
      () {
        _handleListenTimeout(token);
      },
    );
  }

  void _handleSpeechResult(String text, {required bool isFinal}) {
    if (!mounted || _state != SpeakingState.listening) return;

    final recognized = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
    if (recognized.isEmpty) return;

    // 有语音输入就续期，避免“还在说就超时”
    _armListenTimeout(_sessionToken);
    setState(() => _lastHeard = recognized);

    // 中间结果只更新 UI，不做通过/失败判定
    if (!isFinal) return;

    final target = widget.word.text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();

    // 计算匹配质量与星级
    final stars = _calculateStars(recognized, target);

    // 2 星以上才自动通过
    if (stars >= 2) {
      _handleResult(stars, recognized);
    } else if (stars == 1) {
      // 部分匹配时提示重试
      debugPrint('Partial match only (1 star), prompting retry');
      _listenTimeoutTimer?.cancel(); // 已有输入，取消超时
      _showRetryPrompt(recognized);
    } else {
      // 最终结果完全未匹配，进入重试态
      _showRetryPrompt(recognized);
    }
  }

  /// 根据匹配质量计算星级
  /// 规范教育场景常见缩写
  /// 将缩写映射为发音形式以提高匹配
  String _normalizeAbbreviations(String text) {
    final abbreviations = {
      'sb.': 'somebody',
      'sb': 'somebody',
      'sth.': 'something',
      'sth': 'something',
      'esp.': 'especially',
      'etc.': 'et cetera',
      'e.g.': 'for example',
      'i.e.': 'that is',
      'vs.': 'versus',
      'adj.': 'adjective',
      'adv.': 'adverb',
      'n.': 'noun',
      'v.': 'verb',
      'prep.': 'preposition',
    };

    String result = text.toLowerCase();
    abbreviations.forEach((abbr, full) {
      result = result.replaceAll(abbr.toLowerCase(), full);
    });

    // 移除标点以便匹配
    result = result
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return result;
  }

  /// 根据识别匹配度计算星级
  int _calculateStars(String recognized, String target) {
    // 规范化字符串以便比较
    String normalizedRecognized = _normalizeAbbreviations(recognized);
    String normalizedTarget = _normalizeAbbreviations(target);
    final recognizedWords = normalizedRecognized
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final targetWords = normalizedTarget
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();

    // 完全匹配（避免使用子串 contains 导致误判）
    if (normalizedRecognized == normalizedTarget) {
      return 3; // 完全匹配
    }
    // 单词场景：识别结果中任一词精确命中目标词
    if (targetWords.length == 1 &&
        recognizedWords.any((w) => w == normalizedTarget)) {
      return 3;
    }

    // 使用编辑距离判断近似
    final int distance = _levenshtein(normalizedRecognized, normalizedTarget);
    final int targetLen = normalizedTarget.replaceAll(' ', '').length;
    final int strict3StarThreshold = targetLen <= 5
        ? 1
        : (targetLen <= 9 ? 2 : 3);
    final int tolerant2StarThreshold = targetLen <= 5
        ? 2
        : (targetLen <= 9 ? 4 : 5);

    if (distance <= strict3StarThreshold) {
      return 3; // 非常接近，视为完美匹配
    }

    if (distance <= tolerant2StarThreshold) {
      return 2; // 匹配良好
    }

    // 使用 音标算法 做语音相似匹配
    String targetSoundex = PhoneticUtils.soundex(normalizedTarget);
    for (String word in recognizedWords) {
      if (PhoneticUtils.soundex(word) == targetSoundex) {
        return 2; // 发音相似
      }
    }

    // 多词场景：逐词容错
    int matchedWords = 0;
    for (String tw in targetWords) {
      if (tw.length < 2) continue; // 跳过过短的词
      if (recognizedWords.any((rw) => rw == tw || _levenshtein(rw, tw) <= 1)) {
        matchedWords++;
      }
    }

    // 大部分匹配则判定为较好
    if (targetWords.isNotEmpty && matchedWords >= targetWords.length * 0.7) {
      return 2;
    }

    // 单词场景进一步放宽：允许一个音节左右误差
    if (targetWords.length == 1 &&
        recognizedWords.any(
          (w) => _levenshtein(w, normalizedTarget) <= (targetLen <= 6 ? 2 : 3),
        )) {
      return 1; // 部分匹配时提示重试
    }

    // 检测到语音但未匹配时返回 1
    if (recognized.isNotEmpty) {
      return 1;
    }

    return 0; // 完全未匹配
  }

  /// 检测到语音但匹配差时进入失败态，等待用户手动重新开始
  void _showRetryPrompt(String recognized) {
    if (!mounted) return;

    // 播放错误音效
    AudioService().playAsset('wrong.mp3');

    // 取消计时并停止当前监听
    _skipTimer?.cancel();
    _listenTimeoutTimer?.cancel();
    SpeechService().stopListening();
    _pulseController.stop();
    _engineIsListening = false;

    setState(() {
      _state = SpeakingState.failed;
    });
    _isStartingRecognition = false;
  }

  void _handleResult(int stars, String recognized) {
    if (!mounted || _state == SpeakingState.success) return;

    _cancelAllTimers();
    SpeechService().stopListening();
    _pulseController.stop();
    _pulseController.reset();
    _engineIsListening = false;

    setState(() {
      _state = SpeakingState.success;

      _lastHeard = recognized;
    });
    _isStartingRecognition = false;

    _showSuccessOverlay(stars);
  }

  Future<void> _skip() async {
    _sessionToken++;
    _cancelAllTimers();
    await SpeechService().cancel();
    if (!mounted) return;
    _pulseController.stop();
    _pulseController.reset();
    _engineIsListening = false;
    _isStartingRecognition = false;
    widget.onCompleted(0); // 跳过记 0 分
  }

  void _replayStandardAudio() async {
    final currentToken = _sessionToken;
    // 成功或正在播放时不允许重播
    if (_state == SpeakingState.success ||
        _state == SpeakingState.playingAudio ||
        _state == SpeakingState.processing) {
      return;
    }

    final wasListening = _state == SpeakingState.listening;

    if (wasListening) {
      // 监听中：暂停监听，播放音频，再恢复监听
      await SpeechService().stopListening();
      _listenTimeoutTimer?.cancel();
      _pulseController.stop();
      _engineIsListening = false;
    }

    setState(() => _state = SpeakingState.playingAudio);

    await AudioService().playWord(widget.word);
    if (!mounted || currentToken != _sessionToken) return;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted || currentToken != _sessionToken) return;

    if (wasListening) {
      // 之前在监听，恢复监听
      unawaited(_beginListening(currentToken));
    } else {
      // 之前在 idle/failed，播放完回到原状态，用户可以点麦克风开始
      setState(() => _state = SpeakingState.failed);
    }
  }

  void _showSuccessOverlay(int stars) {
    // 音效
    AudioService().playAsset('correct.mp3');

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Success",
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (context, a1, a2) {
        return PracticeSuccessOverlay(
          word: widget.word,
          title: _getStarTitle(stars),
          stars: stars,
          variant: widget.isReviewMode
              ? PracticeSuccessVariant.review
              : PracticeSuccessVariant.learning,
        );
      },
    );

    // 播放单词读音 稍作延迟后
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        AudioService().playWord(widget.word);
      }
    });

    // 自动进入下一题
    _successTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.of(context).pop(); // 关闭提示层
        widget.onCompleted(stars);
      }
    });
  }

  String _getStarTitle(int stars) {
    switch (stars) {
      case 3:
        return '太棒了！';
      case 2:
        return '不错哦！';
      case 1:
        return '继续加油！';
      default:
        return '完成！';
    }
  }

  // 编辑距离算法
  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.filled(t.length + 1, 0);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < t.length + 1; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = [
          v1[j] + 1,
          v0[j + 1] + 1,
          v0[j] + cost,
        ].reduce((min, e) => e < min ? e : min);
      }
      for (int j = 0; j < t.length + 1; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }

  /// 判断是否显示跳过按钮
  bool _shouldShowSkipButton() {
    // 监听超时后显示跳过
    if (_state == SpeakingState.listening && _skipTimer?.isActive == false) {
      return true;
    }
    // 失败态始终允许跳过
    if (_state == SpeakingState.failed) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide =
              !widget.forceVerticalLayout &&
              constraints.maxWidth > constraints.maxHeight &&
              constraints.maxWidth > 480;

          if (isWide) {
            final wideScale = _isLearningMode
                ? (constraints.maxWidth / 1000).clamp(1.06, 1.18)
                : 1.0;
            return Row(
              children: [
                Expanded(
                  flex: _isLearningMode ? 5 : 4,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: LayoutBuilder(
                      builder: (context, viewport) {
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: viewport.maxHeight,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildTargetWord(
                                  scale: wideScale,
                                  isWideLayout: true,
                                ),
                                const SizedBox(height: 24),
                                _buildStatusHUD(scale: wideScale),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Expanded(
                  flex: _isLearningMode ? 4 : 5,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white54,
                      border: Border(left: BorderSide(color: Colors.black12)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(),
                        _buildVoiceWave(height: _isLearningMode ? 32 : 28),
                        const Spacer(),
                        _buildVoiceControls(scale: wideScale),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // 竖屏布局
          return Column(
            children: [
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight * 0.58,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 20),
                          _buildTargetWord(),
                          const SizedBox(height: 20),
                          _buildStatusHUD(),
                          const SizedBox(height: 22),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 底部控制区
              Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  minHeight:
                      constraints.maxHeight * (_isLearningMode ? 0.34 : 0.28),
                  maxHeight:
                      constraints.maxHeight * (_isLearningMode ? 0.4 : 0.34),
                ),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 20,
                      offset: Offset(0, -5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    _buildVoiceWave(),
                    SizedBox(height: _isLearningMode ? 20 : 12),
                    _buildVoiceControls(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVoiceWave({double height = 28}) {
    // 固定占位，避免识别状态切换导致控制区上下跳动
    return SizedBox(height: height);
  }

  Widget _buildVoiceControls({double scale = 1.0}) {
    final controlScale = _isLearningMode ? scale : 1.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左侧：跳过按钮/占位
          SizedBox(
            width: (_isLearningMode ? 98 : 86) * controlScale,
            child: _shouldShowSkipButton()
                ? TextButton.icon(
                    onPressed: _skip,
                    style: TextButton.styleFrom(
                      minimumSize: Size(
                        (_isLearningMode ? 96 : 84) * controlScale,
                        (_isLearningMode ? 42 : 38) * controlScale,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 10 * controlScale,
                        vertical: 8 * controlScale,
                      ),
                      backgroundColor: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    icon: Icon(
                      Icons.skip_next_rounded,
                      size: 18 * controlScale,
                      color: Colors.grey.shade600,
                    ),
                    label: Text(
                      "跳过",
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                        fontSize: 14 * controlScale,
                      ),
                    ),
                  )
                : const SizedBox(),
          ),

          // 中间：麦克风按钮
          _buildVoiceMicButton(sizeScale: controlScale),

          // 右侧：重播按钮
          SizedBox(
            width: 80 * controlScale,
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedSpeakerButton(
                onPressed: _replayStandardAudio,
                isPlaying: _state == SpeakingState.playingAudio,
                size: (_isLearningMode ? 32 : 26) * controlScale,
                variant: widget.isReviewMode
                    ? SpeakerButtonVariant.review
                    : SpeakerButtonVariant.learning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceMicButton({double sizeScale = 1.0}) {
    final isListening = _state == SpeakingState.listening && _engineIsListening;
    final isProcessing = _state == SpeakingState.processing;

    return GestureDetector(
      onTap: () {
        if (isProcessing) return; // 正在启动识别，忽略点击
        if (_state == SpeakingState.idle || _state == SpeakingState.failed) {
          _lastHeard = '';
          if (_hasPlayedAudioForCurrentWord) {
            unawaited(_beginListening(_sessionToken));
          } else {
            unawaited(_startPractice(_sessionToken));
          }
        } else if (_state == SpeakingState.listening) {
          _handleStartListeningFailed('用户手动取消');
        }
      },
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulse = _pulseController.value;
          final pulseScale = isListening ? (1.0 + pulse * 0.06) : 1.0;
          final ringOpacity = isListening ? (0.24 * (1 - pulse)) : 0.0;
          final ringScale = isListening ? (1.0 + pulse * 0.55) : 1.0;
          final controlScale = _isLearningMode ? sizeScale : 1.0;
          final buttonSize = (_isLearningMode ? 92.0 : 80.0) * controlScale;
          final glowAlpha = isListening
              ? _glowRecordingAlpha
              : isProcessing
              ? _glowActiveAlpha
              : _glowIdleAlpha;
          final glowBlur = isListening
              ? _glowRecordingBlur
              : isProcessing
              ? _glowActiveBlur
              : _glowIdleBlur;
          final glowYOffset = isListening
              ? _glowRecordingYOffset
              : isProcessing
              ? _glowActiveYOffset
              : _glowIdleYOffset;

          return Stack(
            alignment: Alignment.center,
            children: [
              if (isListening)
                Transform.scale(
                  scale: ringScale,
                  child: Container(
                    width: buttonSize,
                    height: buttonSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(
                        0xFFFF5252,
                      ).withValues(alpha: ringOpacity),
                      border: Border.all(
                        color: const Color(
                          0xFFFF5252,
                        ).withValues(alpha: ringOpacity * 0.9),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              Transform.scale(
                scale: pulseScale,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: buttonSize,
                  height: buttonSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isListening
                        ? AppColors.error
                        : isProcessing
                        ? _accentColor.withValues(alpha: 0.7)
                        : _accentColor,
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isListening
                                    ? AppColors.error
                                    : _accentColor)
                                .withValues(alpha: glowAlpha),
                        blurRadius: glowBlur,
                        offset: Offset(0, glowYOffset),
                      ),
                    ],
                  ),
                  child: isProcessing
                      ? SizedBox(
                          width: 28 * controlScale,
                          height: 28 * controlScale,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Icon(
                          isListening
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                          color: Colors.white,
                          size: 32 * controlScale,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTargetWord({double scale = 1.0, bool isWideLayout = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.of(context).size;
        final isPortrait = screen.height >= screen.width;
        final isNarrow = constraints.maxWidth < 360;
        final wordLength = widget.word.text.length;
        double wordFontSize;
        if (isNarrow) {
          wordFontSize = _isLearningMode ? 38.0 : 32.0;
        } else if (wordLength > 16) {
          wordFontSize = isPortrait
              ? (_isLearningMode ? 40.0 : 34.0)
              : (_isLearningMode ? 36.0 : 32.0);
        } else if (wordLength > 12) {
          wordFontSize = isPortrait
              ? (_isLearningMode ? 46.0 : 38.0)
              : (_isLearningMode ? 40.0 : 34.0);
        } else {
          wordFontSize = isPortrait
              ? (_isLearningMode ? 58.0 : 48.0)
              : (_isLearningMode ? 48.0 : 40.0);
        }
        if (isWideLayout && _isLearningMode) {
          wordFontSize = (wordFontSize * 0.9).clamp(34.0, 52.0);
        }

        double phoneticFontSize = isNarrow
            ? (_isLearningMode ? 20.0 : 17.0)
            : (isPortrait
                  ? (_isLearningMode ? 24.0 : 20.0)
                  : (_isLearningMode ? 20.0 : 18.0));
        if (isWideLayout && _isLearningMode) {
          phoneticFontSize = (phoneticFontSize * 1.08).clamp(19.0, 26.0);
        }

        double meaningFontSize = isPortrait ? (_isLearningMode ? 20 : 16) : 16;
        if (isWideLayout && _isLearningMode) {
          meaningFontSize = (meaningFontSize * 1.18).clamp(18.0, 26.0);
        }
        final textScale = _isLearningMode ? scale : 1.0;

        return Column(
          children: [
            Text(
              "READ ALOUD",
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12 * textScale,
                fontWeight: FontWeight.w900,
                color: AppColors.textMediumEmphasis,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.word.text,
              style: GoogleFonts.plusJakartaSans(
                fontSize: wordFontSize * textScale,
                fontWeight: FontWeight.w900,
                color: _accentColor,
                height: 1.05,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              widget.word.phonetic,
              style: GoogleFonts.plusJakartaSans(
                fontSize: phoneticFontSize * textScale,
                fontWeight: FontWeight.w500,
                color: AppColors.textMediumEmphasis,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              widget.word.meaning,
              style: GoogleFonts.plusJakartaSans(
                fontSize: meaningFontSize * textScale,
                fontWeight: FontWeight.bold,
                color: AppColors.textHighEmphasis.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
              maxLines: isPortrait ? (_isLearningMode ? 3 : 2) : 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusHUD({double scale = 1.0}) {
    final textScale = _isLearningMode ? scale : 1.0;
    String text;
    Color foregroundColor;
    Color backgroundColor;
    Color borderColor;
    IconData? icon;

    switch (_state) {
      case SpeakingState.idle:
      case SpeakingState.playingAudio:
        text = '请听发音...';
        foregroundColor = AppColors.primary;
        backgroundColor = AppColors.primaryLight;
        borderColor = AppColors.primary.withValues(alpha: 0.2);
        icon = Icons.volume_up_rounded;
        break;
      case SpeakingState.listening:
        if (!_engineIsListening) {
          text = '识别引擎连接中...';
          foregroundColor = AppColors.textMediumEmphasis;
          backgroundColor = AppColors.surfaceVariant;
          borderColor = AppColors.shadowWhite;
          icon = Icons.settings_input_antenna_rounded;
        } else if (_lastHeard.isNotEmpty) {
          text = '听到: "$_lastHeard"';
          foregroundColor = AppColors.success;
          backgroundColor = AppColors.success.withValues(alpha: 0.1);
          borderColor = AppColors.success.withValues(alpha: 0.3);
          icon = Icons.hearing_rounded;
        } else {
          text = '请大声读出来...';
          if (widget.isReviewMode) {
            foregroundColor = const Color(0xFF92400E);
            backgroundColor = AppColors.secondaryLight;
            borderColor = AppColors.secondary.withValues(alpha: 0.3);
          } else {
            foregroundColor = AppColors.primary;
            backgroundColor = AppColors.primaryLight;
            borderColor = AppColors.primary.withValues(alpha: 0.3);
          }
          icon = Icons.mic_rounded;
        }
        break;
      case SpeakingState.processing:
        text = '准备识别...';
        foregroundColor = AppColors.tertiary;
        backgroundColor = AppColors.tertiary.withValues(alpha: 0.1);
        borderColor = AppColors.tertiary.withValues(alpha: 0.2);
        icon = Icons.sync_rounded;
        break;
      case SpeakingState.success:
        text = '完美!';
        foregroundColor = AppColors.success;
        backgroundColor = AppColors.success.withValues(alpha: 0.1);
        borderColor = AppColors.success.withValues(alpha: 0.3);
        icon = Icons.check_circle_rounded;
        break;
      case SpeakingState.failed:
        text = '再试一次!';
        foregroundColor = AppColors.error;
        backgroundColor = AppColors.error.withValues(alpha: 0.05);
        borderColor = AppColors.error.withValues(alpha: 0.2);
        icon = Icons.refresh_rounded;
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(_state),
        padding: EdgeInsets.symmetric(
          horizontal: 24 * textScale,
          vertical: 12 * textScale,
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(30 * textScale),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foregroundColor, size: 20),
            SizedBox(width: 8 * textScale),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16 * textScale,
                  fontWeight: FontWeight.bold,
                  color: foregroundColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
