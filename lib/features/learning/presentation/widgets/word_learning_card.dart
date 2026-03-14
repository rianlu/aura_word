import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/database/models/word.dart';
import '../../../../core/widgets/bubbly_button.dart';
import '../../../../core/widgets/animated_speaker_button.dart';
import '../../../../core/services/audio_service.dart';

class WordLearningCard extends StatefulWidget {
  final Word word;
  final VoidCallback onNext;

  const WordLearningCard({
    super.key, 
    required this.word, 
    required this.onNext
  });

  @override
  State<WordLearningCard> createState() => _WordLearningCardState();
}

class _WordLearningCardState extends State<WordLearningCard> {
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playAudio();
    });
  }

  @override
  void didUpdateWidget(WordLearningCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word.id != widget.word.id) {
       setState(() {
         _isPlaying = false;
       });
       _playAudio();
    }
  }

  Future<void> _playAudio() async {
    if (_isPlaying) return;

    setState(() {
      _isPlaying = true;
    });

    try {
      await AudioService().playWord(widget.word);
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (mounted) {
          setState(() {
             _isPlaying = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 逻辑处理
          final isWide = constraints.maxWidth > constraints.maxHeight && constraints.maxWidth > 480;

          if (isWide) {
            final contentMaxWidth = constraints.maxWidth.clamp(760.0, 1100.0);
            final wideScale = (constraints.maxWidth / 1000).clamp(1.08, 1.26);
            final panelHeight = constraints.maxHeight * 0.74;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: Center(
                          child: SizedBox(
                            height: panelHeight,
                            child: _buildWordInfoCard(
                              compact: true,
                              scale: wideScale,
                              fillHeight: true,
                            )
                            .animate()
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 4,
                        child: Center(
                          child: SizedBox(
                            height: panelHeight,
                            child: Column(
                              children: [
                                Expanded(
                                  child: _buildExampleCard(
                                    compact: true,
                                    scrollableBody: true,
                                    scale: wideScale,
                                  )
                                  .animate()
                                  .fadeIn(duration: 400.ms, delay: 100.ms)
                                  .slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),
                                ),
                                const SizedBox(height: 14),
                                _buildNextButton(scale: wideScale)
                                    .animate()
                                    .fadeIn(duration: 400.ms, delay: 200.ms)
                                    .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack),
                              ],
                            ),
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
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildWordInfoCard()
                          .animate()
                          .fadeIn(duration: 400.ms)
                          .slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),
                      const SizedBox(height: 16),
                      _buildExampleCard()
                          .animate()
                          .fadeIn(duration: 400.ms, delay: 100.ms)
                          .slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: _buildNextButton()
                      .animate()
                      .fadeIn(duration: 400.ms, delay: 200.ms)
                      .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWordInfoCard({
    bool compact = false,
    double scale = 1.0,
    bool fillHeight = false,
  }) {
    final wordSize = (compact ? 40.0 : 48.0) * scale;
    final phoneticSize = (compact ? 18.0 : 18.0) * scale;
    final meaningSize = (compact ? 22.0 : 24.0) * scale;
    final cardPadding = (compact ? 22.0 : 32.0) * scale;
    final gapSm = (compact ? 10.0 : 16.0) * scale;
    final gapMd = (compact ? 16.0 : 24.0) * scale;
    final gapLg = (compact ? 18.0 : 32.0) * scale;

    return Container(
       height: fillHeight ? double.infinity : null,
       padding: EdgeInsets.all(cardPadding),
       decoration: BoxDecoration(
         color: Colors.white,
         borderRadius: BorderRadius.circular(32),
         boxShadow: const [
           BoxShadow(color: AppColors.shadowWhite, offset: Offset(0, 8), blurRadius: 16),
           BoxShadow(color: Colors.black12, offset: Offset(0, 4), blurRadius: 4),
         ],
       ),
       child: Column(
         mainAxisAlignment: fillHeight ? MainAxisAlignment.center : MainAxisAlignment.start,
         mainAxisSize: MainAxisSize.min,
         children: [
           Text(
             widget.word.text, 
             textAlign: TextAlign.center,
             style: GoogleFonts.plusJakartaSans(
               fontSize: wordSize, 
               fontWeight: FontWeight.w900, 
               color: AppColors.primary
             ),
             maxLines: compact ? 2 : 3,
             overflow: TextOverflow.ellipsis,
           ),
           
           SizedBox(height: gapSm),
           
           Container(
             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
             decoration: BoxDecoration(
               color: AppColors.background,
               borderRadius: BorderRadius.circular(12)
             ),
             child: Text(
               widget.word.displayPhonetic, 
               style: GoogleFonts.notoSans(
                 fontSize: phoneticSize, 
                 fontWeight: FontWeight.w500, 
                 color: AppColors.textMediumEmphasis
               ),
               maxLines: 1,
               overflow: TextOverflow.ellipsis,
             ),
           ),
           
           SizedBox(height: gapMd),
           
           AnimatedSpeakerButton(
             onPressed: _playAudio,
             isPlaying: _isPlaying,
             size: 32 * scale,
             variant: SpeakerButtonVariant.learning,
           ),

           SizedBox(height: gapLg),
           const Divider(height: 1, color: AppColors.shadowWhite), 
           SizedBox(height: gapMd),
           
           Text(
             widget.word.meaning, 
             textAlign: TextAlign.center,
             style: GoogleFonts.notoSans(
               fontSize: meaningSize, 
               fontWeight: FontWeight.bold, 
               color: AppColors.textHighEmphasis
             ),
             maxLines: compact ? 4 : 4,
             overflow: TextOverflow.ellipsis,
           ),
         ],
       ),
    );
  }

  Widget _buildExampleCard({
    bool compact = false,
    bool scrollableBody = false,
    double scale = 1.0,
  }) {
    final englishSize = (compact ? 17.0 : 20.0) * scale;
    final chineseSize = (compact ? 14.0 : 16.0) * scale;
    final titleSize = (compact ? 11.0 : 12.0) * scale;
    final cardPadding = (compact ? 20.0 : 24.0) * scale;

    Widget body;
    if (widget.word.examples.isNotEmpty) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => AudioService().playSentence(widget.word.examples.first['en']!),
            child: Text(
              widget.word.examples.first['en']!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: englishSize,
                height: 1.5,
                color: AppColors.textHighEmphasis,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.word.examples.first['cn']!,
            style: GoogleFonts.notoSans(
              fontSize: chineseSize,
              height: 1.5,
              color: AppColors.textMediumEmphasis,
            ),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "No example sentence available.",
            style: GoogleFonts.plusJakartaSans(
              fontSize: compact ? 16 : 18,
              height: 1.5,
              color: AppColors.textHighEmphasis,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "暂无例句",
            style: GoogleFonts.notoSans(
              fontSize: chineseSize,
              height: 1.5,
              color: AppColors.textMediumEmphasis,
            ),
          ),
        ],
      );
    }

    return Container(
       padding: EdgeInsets.all(cardPadding),
       decoration: BoxDecoration(
         color: Colors.white,
         borderRadius: BorderRadius.circular(24),
         border: const Border(left: BorderSide(color: AppColors.primary, width: 4)),
         boxShadow: const [
            BoxShadow(color: AppColors.shadowWhite, offset: Offset(0, 4), blurRadius: 8),
         ],
       ),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Row(
             children: [
               Icon(Icons.format_quote_rounded, color: AppColors.primary.withValues(alpha: 0.8), size: 20),
               const SizedBox(width: 8),
               Text(
                 "EXAMPLE SENTENCE", 
                 style: GoogleFonts.plusJakartaSans(
                   fontSize: titleSize, 
                   fontWeight: FontWeight.w900, 
                   color: AppColors.primary, 
                   letterSpacing: 1.2
                 )
               ),
             ],
           ),
           const SizedBox(height: 16),
           if (scrollableBody)
             Expanded(
               child: SingleChildScrollView(
                 child: body,
               ),
             )
           else
             body,
         ],
       ),
    );
  }

  Widget _buildNextButton({double scale = 1.0, bool compactStyle = false}) {
    return BubblyButton(
      onPressed: widget.onNext,
      color: AppColors.primary,
      shadowColor: AppColors.shadowBlue,
      borderRadius: compactStyle ? 999 : 16,
      padding: EdgeInsets.symmetric(
        vertical: (compactStyle ? 10 : 14) * scale,
        horizontal: (compactStyle ? 16 : 20) * scale,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "下一步",
            style: GoogleFonts.notoSans(
              color: Colors.white, 
              fontSize: 16 * scale,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(width: 8 * scale),
          Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22 * scale)
        ],
      ),
    );
  }
}
