import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/database/models/word.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/audio_service.dart';
import '../../../../core/services/offline_asr_service.dart';
import '../../../../core/services/speech_recognizer_settings.dart';
import '../../../../core/services/speech_service.dart';
import '../../../../core/services/pronunciation_settings.dart';
import '../../../../core/speech/pronunciation_scorer.dart';
import '../../../../core/widgets/offline_asr_download_dialog.dart';
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
  bool _systemEngineFailed = false;
  bool _showOfflineOffer = false;
  bool _acceptEngineStop = false;
  String _phonemeHint = '';
  List<PhonemeMark> _phonemeMarks = const [];

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
    OfflineAsrService.instance.cancelCapture();
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
    OfflineAsrService.instance.cancelCapture();
    SpeechService().cancel(); // Key 机制保证新实例在旧实例 dispose 后才创建
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleEngineListeningChanged(bool isListening) {
    if (!mounted || !_acceptEngineStop) return;
    _engineIsListening = isListening;
    if (isListening) return;
    // 只在系统识别已经真正开始后，才把意外停止当成失败。
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

    // 先播完标准音再初始化识别。系统识别在这台手机上会抢占麦克风和音频焦点，
    // 与播放同时进行时，标准音会被立刻掐掉。
    setState(() => _state = SpeakingState.playingAudio);

    final mode = await SpeechRecognizerSettings.instance.getMode();
    if (!mounted || currentToken != _sessionToken) return;
    if (mode == SpeechRecognizerMode.offline) {
      unawaited(OfflineAsrService.instance.warmUp());
    }

    try {
      await AudioService()
          .playWord(widget.word)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Standard audio skipped: $e');
    }
    if (!mounted || currentToken != _sessionToken) return;
    _hasPlayedAudioForCurrentWord = true;

    // 播放完成后进入识别
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted || currentToken != _sessionToken) return;

    // 开始监听
    unawaited(_beginListening(currentToken));
  }

  Future<bool> _shouldUseOffline() async {
    final mode = await SpeechRecognizerSettings.instance.getMode();
    if (mode == SpeechRecognizerMode.offline) return true;
    if (mode == SpeechRecognizerMode.system) return false;
    return _systemEngineFailed && await OfflineAsrService.instance.isInstalled();
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
    _acceptEngineStop = false;

    setState(() {
      _state = SpeakingState.listening;
      _lastHeard = '';
      _showOfflineOffer = false;
    });
    _engineIsListening = true;
    _pulseController.repeat();
    _skipTimer = Timer(const Duration(seconds: _skipButtonDelaySeconds), () {
      if (mounted) setState(() {});
    });
    _isStartingRecognition = false;

    final useOffline = await _shouldUseOffline();
    if (!mounted || currentToken != _sessionToken) return;

    if (useOffline) {
      await _beginOfflineListening(currentToken);
      return;
    }

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
      final mode = await SpeechRecognizerSettings.instance.getMode();
      if (!mounted || currentToken != _sessionToken) return;
      if (mode == SpeechRecognizerMode.auto) {
        _systemEngineFailed = true;
        if (await OfflineAsrService.instance.isInstalled()) {
          if (!mounted || currentToken != _sessionToken) return;
          await _beginOfflineListening(currentToken);
          return;
        }
        _showOfflineOffer = true;
      }
      _handleStartListeningFailed('识别引擎启动超时或失败');
      return;
    }

    _acceptEngineStop = true;
    _armListenTimeout(currentToken);
  }

  Future<void> _beginOfflineListening(int token) async {
    if (!await OfflineAsrService.instance.isInstalled()) {
      if (!mounted || token != _sessionToken) return;
      final ok = await OfflineAsrDownloadDialog.show(context);
      if (!ok || !mounted || token != _sessionToken) {
        setState(() => _showOfflineOffer = true);
        _handleStartListeningFailed('离线识别模型还没下载');
        return;
      }
    }

    await SpeechService().cancel();
    if (!mounted || token != _sessionToken) return;

    String? text;
    try {
      text = await OfflineAsrService.instance.captureAndTranscribe(
        isCancelled: () => !mounted || token != _sessionToken,
      );
    } on OfflineAsrException catch (e) {
      debugPrint('Offline ASR failed: $e');
      if (!mounted || token != _sessionToken) return;
      _handleStartListeningFailed(e.message);
      return;
    } catch (e) {
      debugPrint('Offline ASR failed: $e');
      if (!mounted || token != _sessionToken) return;
      _handleStartListeningFailed('离线识别失败');
      return;
    }

    if (!mounted || token != _sessionToken || text == null) return;
    if (text.isEmpty) {
      _handleStartListeningFailed('没有听清，请再试一次');
      return;
    }

    if (_state != SpeakingState.listening) {
      setState(() => _state = SpeakingState.listening);
    }
    _engineIsListening = true;
    setState(() => _lastHeard = text!);
    _handleSpeechResult(text, isFinal: true);
  }

  Future<void> _downloadOfflineAndRetry() async {
    final ok = await OfflineAsrDownloadDialog.show(context);
    if (!ok || !mounted) return;
    await SpeechRecognizerSettings.instance.setMode(SpeechRecognizerMode.offline);
    _systemEngineFailed = true;
    if (!mounted) return;
    setState(() => _showOfflineOffer = false);
    await _beginListening(_sessionToken);
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
    _acceptEngineStop = false;
    _cancelAllTimers();
    OfflineAsrService.instance.cancelCapture();
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

  Future<void> _handleSpeechResult(String text, {required bool isFinal}) async {
    if (!mounted) return;
    if (_state != SpeakingState.listening && _state != SpeakingState.processing) {
      return;
    }

    final recognized = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
    if (recognized.isEmpty) return;

    if (!isFinal) return;

    _armListenTimeout(_sessionToken);
    setState(() => _lastHeard = recognized);

    final strictness = await PronunciationSettings.instance.getStrictness();
    if (!mounted) return;
    if (_state != SpeakingState.listening && _state != SpeakingState.processing) {
      return;
    }
    final verdict = PronunciationScorer.score(
      targetText: widget.word.text,
      phonetic: widget.word.displayPhonetic,
      recognized: recognized,
      strictness: strictness,
    );
    _phonemeMarks = verdict.phonemes;
    if (verdict.passed) {
      _phonemeHint = '';
      _handleResult(verdict.stars, recognized);
    } else {
      _phonemeHint = verdict.hint;
      _showRetryPrompt();
    }
  }


  /// 没对上时弹出重试。点「再读一次」会直接重新听，不再多点一次麦克风。
  void _showRetryPrompt() {
    if (!mounted) return;

    // 播放错误音效
    AudioService().playAsset('wrong.mp3');

    // 取消计时并停止当前监听
    _skipTimer?.cancel();
    _listenTimeoutTimer?.cancel();
    _acceptEngineStop = false;
    SpeechService().stopListening();
    _pulseController.stop();
    _engineIsListening = false;

    setState(() {
      _state = SpeakingState.failed;
    });
    _isStartingRecognition = false;
    _showRetryOverlay();
  }

  Future<void> _retryListening() async {
    await AudioService().stop();
    if (!mounted || _state == SpeakingState.success) return;
    await _beginListening(_sessionToken);
  }

  void _showRetryOverlay() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Retry',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (context, a1, a2) {
        return PracticeRetryOverlay(
          word: widget.word,
          heard: _lastHeard,
          hint: _phonemeHint,
          phonemes: _phonemeMarks,
          variant: widget.isReviewMode
              ? PracticeSuccessVariant.review
              : PracticeSuccessVariant.learning,
          onRetry: () {
            Navigator.of(context).pop();
            unawaited(_retryListening());
          },
        );
      },
    );
  }

  void _handleResult(int stars, String recognized) {
    if (!mounted || _state == SpeakingState.success) return;

    _cancelAllTimers();
    _acceptEngineStop = false;
    OfflineAsrService.instance.cancelCapture();
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
    OfflineAsrService.instance.cancelCapture();
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
          phonemes: _phonemeMarks,
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
                                _buildOfflineOffer(),
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
                          _buildOfflineOffer(),
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
              widget.word.displayPhonetic,
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

  Widget _buildOfflineOffer() {
    if (!_showOfflineOffer || _state != SpeakingState.failed) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextButton(
        onPressed: _downloadOfflineAndRetry,
        child: Text(
          '下载离线识别（约 30MB）',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
      ),
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
        text = '点麦克风再读';
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
