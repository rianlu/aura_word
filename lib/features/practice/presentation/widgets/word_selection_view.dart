import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

import '../../../../core/widgets/animated_speaker_button.dart';
import '../../../../core/database/models/word.dart';
import '../../../../core/services/audio_service.dart';
import 'practice_success_overlay.dart';

class WordSelectionView extends StatefulWidget {
  final Word word;
  final List<Word> options;
  final Function(int score) onCompleted;
  final bool isReviewMode;
  final bool forceVerticalLayout;

  const WordSelectionView({
    super.key,
    required this.word,
    required this.options,
    required this.onCompleted,
    this.isReviewMode = false,
    this.forceVerticalLayout = false,
  });

  @override
  State<WordSelectionView> createState() => _WordSelectionViewState();
}

class _WordSelectionViewState extends State<WordSelectionView> {
  String? _selectedOptionId;
  String? _pressingOptionId;
  int _wrongAttempts = 0;

  bool _isPlaying = false;

  @override
  void didUpdateWidget(WordSelectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word.id != widget.word.id) {
      setState(() {
        _selectedOptionId = null;
        _wrongAttempts = 0;

        _isPlaying = false;
      });
    }
  }

  Future<void> _playAudio() async {
    if (_isPlaying) return;
    setState(() => _isPlaying = true);
    try {
      await AudioService().playWord(widget.word);
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (mounted) setState(() => _isPlaying = false);
      }
    }
  }

  void _handleOptionSelected(String wordId) {
    if (_selectedOptionId != null) return; // 已选择则忽略

    setState(() {
      _selectedOptionId = wordId;
      _pressingOptionId = null;
    });

    final isCorrect = wordId == widget.word.id;

    // 稍作延迟以展示结果
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        if (isCorrect) {
          // 展示成功提示层
          if (mounted) {
            _showSuccessOverlay();
          }
        } else {
          // 错误时播放提示并重置
          AudioService().playAsset('wrong.mp3');
          _showErrorToast();
          setState(() {
            _selectedOptionId = null;
            _wrongAttempts++;
          });
        }
      }
    });
  }

  bool _showError = false;

  void _showErrorToast() {
    if (_showError) return;
    setState(() => _showError = true);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showError = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [_buildMainContent()]);
  }

  void _showSuccessOverlay() {
    // 播放音频
    AudioService().playWord(widget.word);
    AudioService().playAsset('correct.mp3');

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Success",
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) {
        return PracticeSuccessOverlay(
          word: widget.word,
          title: "正确!",
          variant: widget.isReviewMode
              ? PracticeSuccessVariant.review
              : PracticeSuccessVariant.learning,
        );
      },
    );

    // 自动进入下一题
    final isLargeScreen = MediaQuery.of(context).size.shortestSide >= 700;
    Future.delayed(Duration(milliseconds: isLargeScreen ? 1500 : 1200), () {
      if (mounted) {
        Navigator.of(context).pop(); // 关闭提示层
        widget.onCompleted(_wrongAttempts == 0 ? 5 : 3);
      }
    });
  }

  Widget _buildMainContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide =
            !widget.forceVerticalLayout &&
            constraints.maxWidth > constraints.maxHeight &&
            constraints.maxWidth > 480;
        final isTall = constraints.maxHeight > 600;
        final isPhone = constraints.biggest.shortestSide < 600;
        final isPortrait = constraints.maxHeight >= constraints.maxWidth;
        // 手机竖屏优先双列，保障四个选项无需滚动即可完整显示
        final useSingleColumn =
            isPhone && isPortrait && constraints.maxHeight >= 820;

        if (isWide) {
          final wideScale = (constraints.maxWidth / 1000).clamp(1.04, 1.16);
          return Row(
            children: [
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 12, 24),
                  child: Center(
                    child: _buildWordCard(
                      compactTop: false,
                      scale: wideScale,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 24, 24, 24),
                  child: _buildOptionsGrid(
                    useSingleColumn: false,
                    isWideLayout: true,
                    scale: wideScale,
                  ),
                ),
              ),
            ],
          );
        }

        if (!isTall) {
          // 逻辑处理
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _buildWordCard(compactTop: useSingleColumn),
                const SizedBox(height: 24),
                // 逻辑处理
                // 逻辑处理
                _buildOptionsGrid(
                  shrinkWrap: true,
                  useSingleColumn: useSingleColumn,
                  isWideLayout: false,
                  scale: 1.0,
                ),
              ],
            ),
          );
        }

        // 标准 竖屏布局
        return Column(
          children: [
            Expanded(
              flex: useSingleColumn ? 4 : 4,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  useSingleColumn ? 24 : 24,
                  24,
                  useSingleColumn ? 12 : 24,
                ),
                child: Center(
                  child: SingleChildScrollView(
                    child: _buildWordCard(compactTop: useSingleColumn),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: useSingleColumn ? 6 : 6,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  0,
                  24,
                  useSingleColumn ? 16 : 24,
                ),
                child: _buildOptionsGrid(useSingleColumn: useSingleColumn),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOptionsGrid({
    bool shrinkWrap = false,
    required bool useSingleColumn,
    bool isWideLayout = false,
    double scale = 1.0,
  }) {
    final titleFontSize = (useSingleColumn ? 16.0 : 12.0) * scale;
    final subtitleFontSize = 13.0 * scale;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isWideLayout)
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择正确释义',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: (18 * scale).clamp(16, 22),
                    fontWeight: FontWeight.w900,
                    color: AppColors.textHighEmphasis,
                  ),
                ),
                SizedBox(height: 4 * scale),
                Text(
                  '点击与你听到的单词相匹配的中文意思',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: subtitleFontSize,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMediumEmphasis,
                  ),
                ),
              ],
            ),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '选择正确释义',
              style: GoogleFonts.plusJakartaSans(
                fontSize: titleFontSize,
                fontWeight: FontWeight.w900,
                color: AppColors.textMediumEmphasis,
                letterSpacing: 0.8,
              ),
            ),
          ),
        SizedBox(height: useSingleColumn ? 10 : (isWideLayout ? 14 : 16)),
        shrinkWrap
            ? GridView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: useSingleColumn ? 1 : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: useSingleColumn ? 3.6 : 1.3,
                ),
                itemCount: widget.options.length,
                itemBuilder: (context, index) {
                  return _buildOptionTile(
                    context,
                    widget.options[index],
                    compactSingleColumn: useSingleColumn,
                    roomyLayout: false,
                    scale: scale,
                  );
                },
              )
            : Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final gap =
                        (constraints.maxWidth * (isWideLayout ? 0.035 : 0.04))
                            .clamp(12.0, 20.0);
                    final crossAxisCount = useSingleColumn ? 1 : 2;
                    final rows = (widget.options.length / crossAxisCount)
                        .ceil();
                    final tileWidth =
                        (constraints.maxWidth - gap * (crossAxisCount - 1)) /
                        crossAxisCount;
                    final tileHeight =
                        (constraints.maxHeight - gap * (rows - 1)) / rows;
                    final roomyLayout =
                        !useSingleColumn &&
                        tileWidth >= 210 &&
                        tileHeight >= 120;
                    final dynamicRatio = (tileWidth / tileHeight).clamp(
                      useSingleColumn ? 3.0 : 1.1,
                      useSingleColumn ? 5.5 : (isWideLayout ? 2.4 : 2.2),
                    );
                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: gap,
                        mainAxisSpacing: gap,
                        childAspectRatio: dynamicRatio,
                      ),
                      itemCount: widget.options.length,
                      itemBuilder: (context, index) {
                        return _buildOptionTile(
                          context,
                          widget.options[index],
                          compactSingleColumn: useSingleColumn,
                          roomyLayout: roomyLayout,
                          scale: scale,
                        )
                        .animate()
                        .fadeIn(duration: 400.ms, delay: (index * 80).ms)
                        .scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack)
                        .slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack);
                      },
                    );
                  },
                ),
              ),
      ],
    );
  }

  Widget _buildWordCard({bool compactTop = false, double scale = 1.0}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLearningMode = !widget.isReviewMode;
        final isCompact = constraints.maxWidth < 360;
        final wordFontSize = isCompact
            ? (isLearningMode ? 30.0 : 27.0)
            : (isLearningMode
                  ? (compactTop ? 40.0 : 36.0)
                  : (compactTop ? 35.0 : 32.0));
        final phoneticFontSize = isCompact
            ? (isLearningMode ? 17.0 : 15.0)
            : (isLearningMode
                  ? (compactTop ? 22.0 : 19.0)
                  : (compactTop ? 20.0 : 18.0));

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(compactTop ? 20 : (isLearningMode ? 24 : 20)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowWhite,
                offset: Offset(0, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.word.text,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: wordFontSize * scale,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        height: 1.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.word.phonetic,
                      style: TextStyle(
                        fontSize: phoneticFontSize * scale,
                        color: AppColors.textMediumEmphasis,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: compactTop ? 8 : 12),
              AnimatedSpeakerButton(
                onPressed: _playAudio,
                isPlaying: _isPlaying,
                size: (compactTop ? 34 : (isLearningMode ? 34 : 32)) * scale,
                variant: widget.isReviewMode
                    ? SpeakerButtonVariant.review
                    : SpeakerButtonVariant.learning,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOptionTile(
    BuildContext context,
    Word optionWord, {
    bool compactSingleColumn = false,
    bool roomyLayout = false,
    double scale = 1.0,
  }) {
    final isLearningMode = !widget.isReviewMode;
    final isSelected = _selectedOptionId == optionWord.id;
    final isPressed =
        _pressingOptionId == optionWord.id && _selectedOptionId == null;

    // 弹跳风格配色
    Color bgColor = Colors.white;
    Color borderColor = Colors.transparent;
    Color shadowColor = AppColors.shadowWhite;
    double yOffset = 4;
    Color textColor = AppColors.textHighEmphasis;

    if (_selectedOptionId != null) {
      final isCorrect = optionWord.id == widget.word.id;
      final isSelectedAndCorrect =
          isCorrect && _selectedOptionId == widget.word.id;

      if (isSelectedAndCorrect) {
        // 正确且被选中：复习模式使用黄系，学习模式使用绿系
        if (widget.isReviewMode) {
          bgColor = const Color(0xFFFEF3C7); // Amber 100
          borderColor = AppColors.secondary;
          shadowColor = AppColors.shadowYellow;
          textColor = const Color(0xFF92400E); // Amber 900
        } else {
          bgColor = AppColors.primaryLight;
          borderColor = AppColors.primary;
          shadowColor = AppColors.shadowBlue;
          textColor = AppColors.primary;
        }
      } else if (isSelected) {
        // 错误
        bgColor = const Color(0xFFFEE2E2); // Red 100
        borderColor = AppColors.error;
        shadowColor = const Color(0xFFDC2626).withValues(alpha: 0.4); 
        textColor = AppColors.error;
      } else {
        // 其他选项
        bgColor = AppColors.surfaceVariant;
        textColor = AppColors.textLowEmphasis;
        yOffset = 0; // 按下效果
        shadowColor = Colors.transparent;
      }
    } else {
      // 正常状态
      // 逻辑处理
      bgColor = Colors.white;
      borderColor = AppColors.surfaceVariant;
      shadowColor = AppColors.shadowWhite;
    }

    return GestureDetector(
      onTapDown: (_) {
        if (_selectedOptionId != null) return;
        setState(() => _pressingOptionId = optionWord.id);
      },
      onTapUp: (_) {
        if (_pressingOptionId == optionWord.id) {
          setState(() => _pressingOptionId = null);
        }
      },
      onTapCancel: () {
        if (_pressingOptionId == optionWord.id) {
          setState(() => _pressingOptionId = null);
        }
      },
      onTap: () => _handleOptionSelected(optionWord.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, isPressed ? 3 : 0, 0),
        padding: EdgeInsets.symmetric(
          horizontal:
              (compactSingleColumn ? 14 : (isLearningMode ? 18 : 16)) * scale,
          vertical:
              (compactSingleColumn ? 6 : (isLearningMode ? 18 : 16)) * scale,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              offset: Offset(0, isPressed ? 1 : yOffset),
              blurRadius: 0, // 实体阴影效果
            ),
          ],
        ),
        child: Center(
          child: LayoutBuilder(
            builder: (context, tileConstraints) {
              final baseSize = compactSingleColumn
                  ? 19.0
                  : (isLearningMode ? 17.0 : 16.0);
              final sizeFromTile = (tileConstraints.biggest.shortestSide * 0.2)
                  .clamp(baseSize, roomyLayout ? 23.0 : 20.0);
              final fontSize = roomyLayout
                  ? (sizeFromTile + 1.0).clamp(baseSize, 24.0)
                  : sizeFromTile;

              return Text(
                optionWord.meaning,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  fontSize: fontSize * scale,
                  color: textColor,
                  height: roomyLayout ? 1.25 : (compactSingleColumn ? 1.15 : 1.2),
                ),
                textAlign: TextAlign.center,
                maxLines: compactSingleColumn ? 1 : (roomyLayout ? 4 : 3),
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
        ),
      ).animate(target: isSelected && optionWord.id == widget.word.id ? 1 : 0)
       .scale(begin: const Offset(1, 1), end: const Offset(1.08, 1.08), curve: Curves.elasticOut, duration: 500.ms),
    );
  }
}
