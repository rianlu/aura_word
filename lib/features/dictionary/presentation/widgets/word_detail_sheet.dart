import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/database/models/word.dart';
import '../../../../core/database/models/word_progress.dart';
import '../../../../core/services/audio_service.dart';
import '../../../../core/theme/app_colors.dart';

import '../../../../core/widgets/animated_speaker_button.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

class WordDetailSheet extends StatefulWidget {
  final Word word;
  final WordProgress? progress;

  const WordDetailSheet({super.key, required this.word, this.progress});

  @override
  State<WordDetailSheet> createState() => _WordDetailSheetState();
}

class _WordDetailSheetState extends State<WordDetailSheet> {
  bool _isPlaying = false;
  bool _isExamplesExpanded = false;

  @override
  void initState() {
    super.initState();
    // _playAudio(); // Disable auto-play
  }

  Future<void> _playAudio() async {
    if (_isPlaying) return;
    setState(() => _isPlaying = true);
    try {
      await AudioService().playWord(widget.word);
    } finally {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  String get _nextReviewText {
    if (widget.progress == null) return "未学习";
    final next = DateTime.fromMillisecondsSinceEpoch(
      widget.progress!.nextReviewDate,
    );
    final now = DateTime.now();
    final diff = next.difference(now);

    if (diff.isNegative) return "现在复习";
    if (diff.inDays == 0) return "今天复习";
    if (diff.inDays == 1) return "明天复习";
    if (diff.inDays < 30) return "${diff.inDays}天后复习";
    return DateFormat('MM-dd').format(next);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 1. Header Area (Word + Phonetic + Audio)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.word.text,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textHighEmphasis,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSpeakerButton(
                            onPressed: _playAudio,
                            isPlaying: _isPlaying,
                            size: 32,
                            variant: SpeakerButtonVariant.learning,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "/${widget.word.displayPhonetic}/",
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 16,
                              color: AppColors.textMediumEmphasis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),

            const SizedBox(height: 16),

            // 2. Memory Strength Bar (Plan C)
            if (widget.progress != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  children: [
                    // Header Row
                    Row(
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          size: 18,
                          color: _retentionColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "记忆强度: ${(_calculateRetention() * 100).toInt()}%",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textHighEmphasis,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _retentionColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _retentionStatusText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _retentionColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _calculateRetention(),
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _retentionColor,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Info Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "上次: ${_formatDate(widget.progress!.lastReviewDate)}",
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 11,
                            color: AppColors.textMediumEmphasis,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.event_repeat_rounded,
                              size: 12,
                              color: AppColors.textMediumEmphasis,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "下次: $_nextReviewText",
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 11,
                                color: AppColors.textMediumEmphasis,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "该单词尚未开始学习",
                      style: TextStyle(color: AppColors.textMediumEmphasis),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),
            ],

            const SizedBox(height: 24),
            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 24),

            // 3. Meaning
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "释义",
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMediumEmphasis,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.word.meaning,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.5,
                    color: AppColors.textHighEmphasis,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),

            const SizedBox(height: 24),

            // 4. Examples (Collapsible)
            if (widget.word.examples.isNotEmpty) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "例句",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMediumEmphasis,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildExampleItem(widget.word.examples.first),
                ],
              ).animate().fadeIn(duration: 400.ms, delay: 300.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),

              // Collapsible extra examples
              if (widget.word.examples.length > 1) ...[
                if (_isExamplesExpanded)
                  ...widget.word.examples
                      .skip(1)
                      .map(
                        (ex) => Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _buildExampleItem(ex),
                        ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack),
                      ),

                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _isExamplesExpanded = !_isExamplesExpanded,
                    ),
                    icon: Icon(
                      _isExamplesExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      _isExamplesExpanded
                          ? "收起"
                          : "展开其余 ${widget.word.examples.length - 1} 个例句",
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.05,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 400.ms),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExampleItem(Map<String, dynamic> ex) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ex['en'] ?? '',
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textHighEmphasis,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            ex['cn'] ?? '',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textMediumEmphasis,
            ),
          ),
        ],
      ),
    );
  }

  // Helper for date formatting
  String _formatDate(int millis) {
    if (millis <= 0) return "-";
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return "今天";
    if (diff.inDays == 1) return "昨天";
    if (diff.inDays < 7) return "${diff.inDays}天前";
    return DateFormat('MM-dd').format(date);
  }

  double _calculateRetention() {
    if (widget.progress == null) return 0.0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastReview = widget.progress!.lastReviewDate > 0
        ? widget.progress!.lastReviewDate
        : widget.progress!.createdAt;

    final nextReview = widget.progress!.nextReviewDate;

    // Interval
    final interval = nextReview - lastReview;
    if (interval <= 0) return 0.0;

    // Elapsed
    final elapsed = now - lastReview;
    if (elapsed < 0) return 1.0;

    // SM-2 Formula: R = e^(-t/S)
    // S = -interval / ln(0.9)
    final s = -interval / math.log(0.9);
    final retention = math.exp(-elapsed / s);

    return retention.clamp(0.0, 1.0);
  }

  Color get _retentionColor {
    final r = _calculateRetention();
    if (r >= 0.9) return const Color(0xFF4CAF50); // Green
    if (r >= 0.8) return const Color(0xFFFF9800); // Orange
    return const Color(0xFFF44336); // Red
  }

  String get _retentionStatusText {
    final r = _calculateRetention();
    if (r >= 0.9) return "状态极佳";
    if (r >= 0.8) return "记得回顾";
    return "急需复习";
  }
}
