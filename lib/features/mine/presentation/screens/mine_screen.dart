import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as dart;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sqflite/sqflite.dart';
import 'package:aura_word/features/mine/presentation/screens/settings_screen.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/database/daos/user_stats_dao.dart';
import '../../../../core/database/daos/stats_dao.dart';
import '../../../../core/database/daos/word_dao.dart';
import '../../../../core/database/database_helper.dart';
import 'mine_profile_section.dart';
import '../../../../core/widgets/bubbly_button.dart'; // Add BubblyButton for _buildMenuItem

class MineScreen extends StatefulWidget {
  const MineScreen({super.key});

  @override
  State<MineScreen> createState() => _MineScreenState();
}

class _MineScreenState extends State<MineScreen> {
  final WordDao _wordDao = WordDao();
  final StatsDao _statsDao = StatsDao();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _generateMockData() async {
    final confirmed = await _confirmGenerateMockData();
    if (!confirmed) return;
    setState(() => _isLoading = true);

    final r = dart.Random();
    final now = DateTime.now();
    final userStats = await UserStatsDao().getUserStats();

    // 逻辑处理
    for (int i = 1; i <= 14; i++) {
      final date = now.subtract(Duration(days: i));

      // 逻辑处理
      if (r.nextDouble() > 0.2) {
        // 逻辑处理
        int newWords = r.nextInt(15);
        int reviewWords = r.nextInt(30) + 10;
        int correct = (reviewWords * (0.6 + r.nextDouble() * 0.4)).round(); 
        int wrong = reviewWords - correct;
        int minutes = r.nextInt(30) + 10;

        await _statsDao.recordDailyActivity(
          newWords: newWords,
          reviewWords: reviewWords,
          correct: correct,
          wrong: wrong,
          minutes: minutes,
          date: date,
        );
      }
    }

    final newWords = await _wordDao.getNewWords(
      20,
      bookId: userStats.currentBookId.isNotEmpty ? userStats.currentBookId : null,
      grade: userStats.currentGrade,
      semester: userStats.currentSemester,
    );
    if (newWords.isNotEmpty) {
      final db = await DatabaseHelper().database;
      final batch = db.batch();
      final yesterday = now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;

      for (var word in newWords) {
        batch.insert('word_progress', {
          'id': 'progress_${word.id}',
          'word_id': word.id,
          'created_at': yesterday,
          'updated_at': yesterday,
          'easiness_factor': 2.5,
          'interval': 1,
          'repetition': 1,
          'next_review_date': yesterday, 
          'last_review_date': yesterday,
          'review_count': 1,
          'mastery_level': 1,
          'correct_count': 1,
          'wrong_count': 0,
          'speak_mode_count': 0,
          'spell_mode_count': 0,
          'select_mode_count': 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    }

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已生成过去数据 & ${newWords.length} 个待复习单词')),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _openXhsProfile() async {
    const userId = '5efb6a420000000001005544';

    final appUris = [
      Uri.parse('xhsuserprofile://user_id=$userId'),
      Uri.parse('xhsdiscover://user/$userId'),
      Uri.parse('xhsdiscover://user/profile/$userId'),
    ];

    final webUri = Uri.parse('https://www.xiaohongshu.com/user/profile/$userId');
    bool launched = false;

    for (final uri in appUris) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          launched = true;
          break;
        }
      } catch (e) {
        debugPrint('Failed to launch scheme $uri: $e');
      }
    }

    if (!launched) {
      try {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Could not launch web profile: $e');
        try {
          await launchUrl(webUri, mode: LaunchMode.platformDefault);
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const MineProfileSection(),
            const SizedBox(height: 16),
            _buildMenuItem(
                  icon: Icons.rocket_launch_rounded,
                  title: '参与内测 & 获取更新',
                  onTap: _openXhsProfile,
                )
                .animate()
                .fadeIn(duration: 500.ms, delay: 400.ms)
                .slideY(begin: 0.2, end: 0, curve: Curves.easeOutQuad),
            const SizedBox(height: 16),
            _buildMenuItem(
                  icon: Icons.settings_rounded,
                  title: '高级设置',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                  },
                )
                .animate()
                .fadeIn(duration: 500.ms, delay: 500.ms)
                .slideY(begin: 0.2, end: 0, curve: Curves.easeOutQuad),
            const SizedBox(height: 16),
            if (kDebugMode)
              _buildMenuItem(
                    icon: Icons.auto_graph_rounded,
                    title: '生成模拟数据 (仅调试)',
                    onTap: _generateMockData,
                  )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 600.ms)
                  .slideY(begin: 0.2, end: 0, curve: Curves.easeOutQuad),
            const SizedBox(height: 40),
            Center(
              child: Text(
                'v1.0.0',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmGenerateMockData() async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('生成测试数据'),
            content: const Text('该操作会写入模拟学习记录，仅用于调试。是否继续？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return BubblyButton(
      onPressed: onTap,
      color: Colors.white,
      shadowColor: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      borderRadius: 16,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textHighEmphasis,
              ),
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 16,
            color: Colors.grey,
          ),
        ],
      ),
    );
  }
}
