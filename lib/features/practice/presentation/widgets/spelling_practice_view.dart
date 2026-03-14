import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/services/audio_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/bubbly_button.dart';
import '../../../../core/widgets/animated_speaker_button.dart';
import '../../../../core/database/models/word.dart';

import 'practice_success_overlay.dart';

class SpellingPracticeView extends StatefulWidget {
  final Word word;
  final Function(int score) onCompleted;
  final bool isReviewMode;
  final bool forceVerticalLayout;

  const SpellingPracticeView({
    super.key, 
    required this.word, 
    required this.onCompleted,
    this.isReviewMode = false,
    this.forceVerticalLayout = false,
  });

  @override
  State<SpellingPracticeView> createState() => _SpellingPracticeViewState();
}

class _SpellingPracticeViewState extends State<SpellingPracticeView> {

  bool _showSuccess = false; // 加入成功状态
  bool _isPlayingWord = false;
  int _hintsUsed = 0;
  bool _revealFullWord = false; // 提示用尽且错误时显示完整单词
  int? _hintHighlightSlot; // 最近一次提示填充的槽位，用于短暂高亮
  
  // 提示次数随题目难度自适应：最多 3 次，避免过度提示
  int get _maxHints => _missingIndices.length.clamp(1, 3);

  // 游戏状态
  String _targetWord = "";
  List<int> _missingIndices = [];
  List<String> _userInputs = [];
  List<String> _keyboardLetters = [];

  @override
  void initState() {
    super.initState();
    _initializeGame();
  }

  @override
  void didUpdateWidget(SpellingPracticeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word.id != widget.word.id) {
       _initializeGame();
    }
  }

  void _initializeGame() {
    _targetWord = widget.word.text;

    _showSuccess = false;
    _isPlayingWord = false;
    _hintsUsed = 0;
    _revealFullWord = false;
    _hintHighlightSlot = null;
    
    final random = Random();
    int len = _targetWord.length;
    // 计算隐藏字母数量
    // 保证至少隐藏 1 个字母
    int upperLimit = max(1, len - 1);
    int missingCount = (len * 0.4).ceil().clamp(1, min(upperLimit, 7));
    
    // 随机选择唯一索引
    Set<int> indices = {};
    // 重试次数限制
    int attempts = 0;
    while (indices.length < missingCount && attempts < 100) {
      attempts++;
      int randIndex = random.nextInt(len);
      // 不隐藏空格或特殊字符
      if (_targetWord[randIndex].trim().isEmpty) continue;
      
      indices.add(randIndex);
    }
    _missingIndices = indices.toList()..sort();
    _userInputs = List.filled(missingCount, "");

    // 准备键盘
    // 包含所有缺失字母
    Set<String> letters = {};
    for (int idx in _missingIndices) {
      letters.add(_targetWord[idx].toLowerCase());
    }
    // 加入随机干扰字母
    const allChars = "abcdefghijklmnopqrstuvwxyz";
    while (letters.length < 7) { // 固定 7 个字母键
       letters.add(allChars[random.nextInt(allChars.length)]);
    }
    _keyboardLetters = letters.toList()..shuffle();
    setState(() {});
  }

  Future<void> _playWordAudio() async {
    if (_isPlayingWord) return;
    setState(() => _isPlayingWord = true);
    try {
      await AudioService().playWord(widget.word);
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (mounted) setState(() => _isPlayingWord = false);
      }
    }
  }

  void _handleLetterInput(String char) {
    if (_showSuccess) return; // 已完成时禁止输入
    // 找到第一个空位
    int emptyIndex = _userInputs.indexOf("");
    if (emptyIndex != -1) {
      setState(() {
        _userInputs[emptyIndex] = char;
      });
      _checkCompletion();
    }
  }

  void _handleBackspace() {
    if (_showSuccess) return;
    // 找到最后一个已填位置
    int lastFilledIndex = _userInputs.lastIndexWhere((element) => element.isNotEmpty);
    if (lastFilledIndex != -1) {
      setState(() {
        _userInputs[lastFilledIndex] = "";
      });
    }
  }

  void _useHint() {
    if (_showSuccess || _revealFullWord) return;
    if (_hintsUsed >= _maxHints) return; // 达到提示上限
    
    // 从前往后补全，符合低年级拼写回忆习惯
    final int slotIndex = _userInputs.indexOf("");
    if (slotIndex != -1) {
      setState(() {
         // 从目标单词取出实际字母
         // 缺失索引映射：输入槽位 -> 单词索引
         int wordIndex = _missingIndices[slotIndex];
         String char = _targetWord[wordIndex].toLowerCase();
         
         _userInputs[slotIndex] = char;
         _hintsUsed++;
         _hintHighlightSlot = slotIndex;
      });
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        if (_hintHighlightSlot == slotIndex) {
          setState(() => _hintHighlightSlot = null);
        }
      });
      _checkCompletion();
    }
  }

  bool get _canUseHint => _hintsUsed < _maxHints && !_showSuccess && !_revealFullWord;

  void _checkCompletion() {
    if (!_userInputs.contains("")) {
      // 重建单词
      String constructed = "";
      int inputIndex = 0;
      for (int i = 0; i < _targetWord.length; i++) {
        if (_missingIndices.contains(i)) {
          constructed += _userInputs[inputIndex];
          inputIndex++;
        } else {
          constructed += _targetWord[i];
        }
      }

      if (constructed.toLowerCase() == _targetWord.toLowerCase()) {
         // 正确
         // 1. 立即显示成功状态
         setState(() {
           _showSuccess = true;
         });

         // 2. 播放音频 同时
         AudioService().playWord(widget.word);
         
         // 3. 显示成功提示层
         if (mounted) {
            _showSuccessOverlay();
         }
      } else {
        // 错误
        AudioService().playAsset('wrong.mp3');
        _showErrorToast(); // 立即视觉报错

        // 检查是否用尽提示
        if (_hintsUsed >= _maxHints) {
          // 提示用尽时展示完整单词
          setState(() {
            _revealFullWord = true;
            // 填充所有缺失字母
            for (int i = 0; i < _missingIndices.length; i++) {
              int wordIndex = _missingIndices[i];
              _userInputs[i] = _targetWord[wordIndex].toLowerCase();
            }
          });

          // 播放单词读音
          AudioService().playWord(widget.word);

          // 展示完整单词后自动进入下一题
          Future.delayed(const Duration(milliseconds: 2000), () {
            if (mounted) {
              widget.onCompleted(0); // 显示答案时记 0 分
            }
          });
        } else {
          // 还有提示次数，稍后清空输入供重试
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) {
              setState(() {
                _userInputs = List.filled(_userInputs.length, "");
              });
            }
          });
        }
      }
    }
  }

  bool _showError = false;

  void _showErrorToast() {
    if (_showError) return;
    setState(() => _showError = true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showError = false);
    });
  }

  // --- 主题配置 ---
  Color get _activeColor => widget.isReviewMode 
      ? const Color(0xFFFFC107) // 复习模式：明亮黄色（与进度条一致）
      : AppColors.primary;      // 学习模式：默认蓝色

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = !widget.forceVerticalLayout &&
              constraints.maxWidth > constraints.maxHeight &&
              constraints.maxWidth > 480;

          if (isWide) {
            final wideScale = (constraints.maxWidth / 1100).clamp(1.0, 1.2);
            final puzzleScale = (wideScale * 1.05).clamp(1.0, 1.22);
            final keyboardScale = wideScale.clamp(1.0, 1.15);
            final contentMaxWidth = min(1080.0, constraints.maxWidth - 48);

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: const [
                              BoxShadow(
                                color: AppColors.shadowWhite,
                                blurRadius: 28,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                                child: Center(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildMeaningHeader(fontScale: wideScale),
                                        const SizedBox(height: 20),
                                        _buildPuzzleArea(visualScale: puzzleScale),
                                        const SizedBox(height: 14),
                                        _buildSentenceHint(
                                          fontScale: wideScale,
                                          showChinese: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 4,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white54,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.black12),
                          ),
                          padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                          child: Column(
                            children: [
                              const Spacer(),
                              _buildHintButton(),
                              const SizedBox(height: 12),
                              _buildKeyboardArea(sizeScale: keyboardScale),
                              const Spacer(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // 竖屏布局
          return Column(
            children: [
              // 上部：拼图与释义
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const Spacer(),
                      _buildMeaningHeader(),
                      const SizedBox(height: 24),
                      _buildPuzzleArea(),
                      const SizedBox(height: 24),
                      _buildSentenceHint(),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
              
              // 下部：交互区
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), // 缩减底部间距
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))
                  ]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHintButton(),
                    const SizedBox(height: 12), // 略微压缩间距
                    _buildKeyboardArea(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMeaningHeader({double fontScale = 1.0}) {
    final titleSize = (12.0 * fontScale).clamp(12.0, 16.0);
    final meaningSize = (24.0 * fontScale).clamp(24.0, 32.0);
    final buttonSize = (32.0 * fontScale).clamp(30.0, 42.0);
    return Column(
      children: [
        Text(
          "SPELL THE WORD",
          style: GoogleFonts.plusJakartaSans(
            fontSize: titleSize, fontWeight: FontWeight.w900, 
            color: AppColors.textMediumEmphasis, letterSpacing: 1.0
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            widget.word.meaning,
            style: GoogleFonts.plusJakartaSans(
              fontSize: meaningSize, 
              fontWeight: FontWeight.w900, 
              color: _activeColor
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 10),
        AnimatedSpeakerButton(
          onPressed: _playWordAudio,
          isPlaying: _isPlayingWord,
          size: buttonSize,
          variant: widget.isReviewMode
              ? SpeakerButtonVariant.review
              : SpeakerButtonVariant.learning,
        ),
      ],
    );
  }
  
  Widget _buildPuzzleArea({double visualScale = 1.0}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        
        // 1. 将单词按空格拆分
        final words = _targetWord.split(' ');
        
        // 2. 基础尺寸定义
        final baseBoxWidth = 44.0 * visualScale;
        final baseFontSize = 24.0 * visualScale;
        final baseLetterSpacing = 8.0 * visualScale;
        final baseWordSpacing = 24.0 * visualScale;
        
        // 3. 计算如果不缩放，单行所需的总宽度
        double totalRequiredWidth = 0;
        for (int i = 0; i < words.length; i++) {
          totalRequiredWidth += words[i].length * baseBoxWidth + (words[i].length - 1) * baseLetterSpacing;
          if (i < words.length - 1) {
            totalRequiredWidth += baseWordSpacing;
          }
        }
        
        // 4. 计算缩放比例（可在大屏轻微放大）
        final scaleFactor = (availableWidth / totalRequiredWidth).clamp(0.7, 1.2);
        
        // 5. 应用缩放后的尺寸
        final boxSize = baseBoxWidth * scaleFactor;
        final fontSize = baseFontSize * scaleFactor;
        final letterSpacing = baseLetterSpacing * scaleFactor;
        final wordSpacing = baseWordSpacing * scaleFactor;
        
        // 查找当前待填写的第一个空位索引
        final int firstEmptySlotIndex = _userInputs.indexOf("");

        // 跟踪全局字符索引，用于匹配 _missingIndices
        int globalCharIndex = 0;

        final wordWidgets = words.map((wordText) {
          final wordWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(wordText.length, (charIdx) {
              final curIndex = globalCharIndex + charIdx;
              final bool isMissing = _missingIndices.contains(curIndex);
              final int slotIndex = isMissing ? _missingIndices.indexOf(curIndex) : -1;
              final bool isCurrentFocus = isMissing && slotIndex == firstEmptySlotIndex && !_showSuccess && !_revealFullWord;
              
              String char = _targetWord[curIndex];
              String displayChar = char;
              Color bgColor = Colors.grey.shade100;
              Color borderColor = Colors.transparent;
              Color textColor = AppColors.textHighEmphasis;
              double borderWidth = 2.0;

              if (isMissing) {
                final isHintHighlighted = _hintHighlightSlot == slotIndex;

                if (_showError) {
                  // 全局报错状态：所有待填空位统一变红
                  bgColor = Colors.red.withValues(alpha: 0.1);
                  borderColor = Colors.red;
                  borderWidth = 3.5;
                  displayChar = _userInputs[slotIndex];
                } else if (_userInputs[slotIndex].isNotEmpty) {
                  displayChar = _userInputs[slotIndex];
                  
                  if (isHintHighlighted) {
                    // 提示高亮色：基于当前模式动态选择
                    if (widget.isReviewMode) {
                      bgColor = const Color(0xFFFFF4CC);  // 浅黄
                      borderColor = const Color(0xFFF59E0B); // 橙黄
                      textColor = const Color(0xFFB45309);   // 深褐
                    } else {
                      bgColor = const Color(0xFFE0F2FE);  // 浅蓝 (Blue 50)
                      borderColor = const Color(0xFF0EA5E9); // 天蓝 (Blue 500)
                      textColor = const Color(0xFF0369A1);   // 深蓝 (Blue 700)
                    }
                  } else {
                    // 普通填充色
                    bgColor = _activeColor.withValues(alpha: 0.1);
                    borderColor = _activeColor;
                    textColor = _activeColor;
                  }
                } else {
                  displayChar = "";
                  bgColor = Colors.white;
                  // 当前焦点：加粗边框及模式主色调
                  if (isCurrentFocus) {
                    borderColor = _activeColor;
                    borderWidth = 3.5; // 焦点位边框加粗
                  } else {
                    // 提示空位色
                    if (isHintHighlighted) {
                       borderColor = widget.isReviewMode ? const Color(0xFFF59E0B) : const Color(0xFF0EA5E9);
                    } else {
                       borderColor = Colors.grey.shade300;
                    }
                  }
                }
              } else {
                bgColor = Colors.grey.shade200;
                textColor = Colors.grey.shade500;
              }

              final isLastInWord = charIdx == wordText.length - 1;

              return Padding(
                padding: EdgeInsets.only(right: isLastInWord ? 0 : letterSpacing),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: boxSize,
                  height: boxSize * 1.2,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(max(4, 8 * scaleFactor)),
                    border: Border.all(color: borderColor, width: borderWidth * scaleFactor),
                  ),
                  child: Text(
                    displayChar,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                    ),
                  ),
                ),
              );
            }),
          );
          
          globalCharIndex += wordText.length + 1; // +1 是为了跳过空格
          return wordWidget;
        }).toList();

        // 核心拼读区域容器
        Widget puzzleBody = Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: wordSpacing,
          runSpacing: 16.0 * scaleFactor,
          children: wordWidgets,
        ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack);

        // 输错时的全局抖动效果
        return TweenAnimationBuilder<double>(
          key: const ValueKey('puzzle_shake_container'),
          tween: Tween(begin: 0.0, end: _showError ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            final offset = _showError ? sin(value * pi * 4) * 12 * (1.0 - value) : 0.0;
            return Transform.translate(
              offset: Offset(offset, 0),
              child: child,
            );
          },
          child: puzzleBody,
        );
      },
    );
  }

  Widget _buildSentenceHint({
    double fontScale = 1.0,
    bool showChinese = false,
  }) {
    if (widget.word.examples.isEmpty) return const SizedBox.shrink();
    final sentenceSize = ((showChinese ? 15.0 : 14.0) * fontScale).clamp(
      showChinese ? 15.0 : 14.0,
      showChinese ? 20.0 : 18.0,
    );
    final chineseSize = (14.0 * fontScale).clamp(13.0, 18.0);
    final english = widget.word.examples.first['en']!.replaceAll(
      RegExp(widget.word.text, caseSensitive: false),
      "____",
    );
    final chinese = widget.word.examples.first['cn'] ?? "";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            english,
            style: GoogleFonts.plusJakartaSans(
              fontSize: sentenceSize,
              color: AppColors.textMediumEmphasis,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          if (showChinese && chinese.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              chinese,
              style: GoogleFonts.notoSans(
                fontSize: chineseSize,
                color: AppColors.textMediumEmphasis.withValues(alpha: 0.9),
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKeyboardArea({double sizeScale = 1.0}) {
    final row1 = _keyboardLetters.take(4).toList();
    final row2 = _keyboardLetters.skip(4).take(3).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final buttonSize = (((constraints.maxWidth - spacing * 3) / 4) * sizeScale)
            .clamp(44.0, 74.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < row1.length; i++) ...[
                  _buildLetterButton(row1[i], size: buttonSize)
                      .animate()
                      .fadeIn(duration: 300.ms, delay: (i * 50).ms)
                      .scale(begin: const Offset(0.7, 0.7), curve: Curves.easeOutBack),
                  if (i != row1.length - 1) const SizedBox(width: spacing),
                ],
              ],
            ),
            const SizedBox(height: spacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < row2.length; i++) ...[
                  _buildLetterButton(row2[i], size: buttonSize)
                      .animate()
                      .fadeIn(duration: 300.ms, delay: (200 + i * 50).ms)
                      .scale(begin: const Offset(0.7, 0.7), curve: Curves.easeOutBack),
                  const SizedBox(width: spacing),
                ],
                _buildBackspaceButton(size: buttonSize)
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 350.ms)
                    .scale(begin: const Offset(0.7, 0.7), curve: Curves.easeOutBack),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildHintButton() {
    return Padding(
       padding: const EdgeInsets.only(bottom: 16),
       child: Visibility(
         visible: _userInputs.contains("") && !_revealFullWord,
         maintainSize: true,
         maintainAnimation: true,
         maintainState: true,
         child: TextButton.icon(
           onPressed: _canUseHint ? _useHint : null,
           icon: Icon(
             Icons.lightbulb_outline, 
             color: _canUseHint ? const Color(0xFFF59E0B) : Colors.grey, // 提示始终用橙色
           ),
           label: Text(
             "提示 ($_hintsUsed/$_maxHints)", 
             style: TextStyle(
               color: _canUseHint ? _activeColor : Colors.grey, // 文字跟随模式主色
               fontWeight: FontWeight.bold,
             ),
           ),
         ),
       ),
     );
  }







  void _showSuccessOverlay() {
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
          title: "正确!",
          variant: widget.isReviewMode ? PracticeSuccessVariant.review : PracticeSuccessVariant.learning,
        );
      },
    );

      Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
         Navigator.of(context).pop(); // 关闭提示层
         int score = _hintsUsed > 0 ? 3 : 5;
         widget.onCompleted(score);
      }
    });
  }

  Widget _buildLetterButton(String char, {double size = 56}) {
    return SizedBox(
      width: size, height: size,
      child: BubblyButton(
        onPressed: () => _handleLetterInput(char),
        color: Colors.white,
        shadowColor: Colors.grey.shade300, 
        padding: EdgeInsets.zero,
        borderRadius: 16,
        child: Center(
          child: Text(char, style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.bold, color: AppColors.textHighEmphasis)),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton({double size = 56}) {
     return SizedBox(
      width: size, height: size,
      child: BubblyButton(
        onPressed: _handleBackspace,
        color: const Color(0xFFFEE2E2), // 红色 100
        shadowColor: const Color(0xFFFECaca),
        padding: EdgeInsets.zero,
        borderRadius: 16,
        child: Center(
          child: Icon(Icons.backspace, color: const Color(0xFFEF4444), size: size * 0.36),
        ),
      ),
    );
  }
}
