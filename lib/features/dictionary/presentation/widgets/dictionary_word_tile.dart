import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/bubbly_button.dart';
import '../../../../core/database/models/word.dart';
import '../../../../core/database/models/word_progress.dart';
import '../../../../core/database/daos/word_dao.dart';
import 'word_detail_sheet.dart';

class DictionaryWordTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onTap;

  const DictionaryWordTile({
    super.key,
    required this.item,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = item['text'] as String;
    final meaning = item['meaning'] as String;
    final mastery = item['mastery_level'] as int? ?? 0;
    final isLearned = (item['is_learned'] as int? ?? 0) == 1;
    final interval = item['interval'] as int? ?? 1;

    Color badgeColor = Colors.grey.shade400;
    String badgeText = "未开始";
    IconData badgeIcon = Icons.circle_outlined;

    if (isLearned) {
      if (mastery == 2) {
        badgeColor = AppColors.success;
        badgeText = "已掌握";
        badgeIcon = Icons.check_circle;
      } else {
        if (interval >= 8) {
          badgeColor = const Color(0xFF8BC34A); // 保持自然的草绿色
          badgeText = "熟练中";
          badgeIcon = Icons.trending_up;
        } else if (interval >= 3) {
          badgeColor = AppColors.warning;
          badgeText = "学习中";
          badgeIcon = Icons.schedule;
        } else {
          badgeColor = const Color(0xFFFB923C); // 浅橙色
          badgeText = "初学";
          badgeIcon = Icons.flag;
        }
      }
    }

    return BubblyButton(
      onPressed: onTap ?? () => showDetail(context, item),
      color: Colors.white,
      shadowColor: AppColors.shadowWhite,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textHighEmphasis,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  meaning,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textMediumEmphasis,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(badgeIcon, size: 16, color: badgeColor),
              const SizedBox(height: 4),
              Text(
                badgeText,
                style: TextStyle(
                  fontSize: 12,
                  color: badgeColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  static bool _isOpening = false;

  static Future<void> showDetail(BuildContext context, Map<String, dynamic> item) async {
    if (_isOpening) return;
    _isOpening = true;
    
    // Dismiss keyboard if any
    FocusScope.of(context).unfocus();

    try {
      final wordId = item['id'] as String;
      final dao = WordDao();
      
      final Word? fullWord = await dao.getWordDetails(wordId);
      final WordProgress? progress = await dao.getWordProgress(wordId);

      if (fullWord == null || !context.mounted) {
        _isOpening = false;
        return;
      }

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: WordDetailSheet(
            word: fullWord,
            progress: progress,
          ),
        ),
      );
    } catch (e) {
      debugPrint("Error opening detail sheet: $e");
    } finally {
      _isOpening = false;
    }
  }
}
