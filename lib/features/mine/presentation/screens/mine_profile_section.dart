import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/daos/stats_dao.dart';
import '../../../../core/database/daos/user_stats_dao.dart';
import '../../../../core/database/models/user_stats.dart';
import '../../../../core/services/global_stats_notifier.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/bubbly_button.dart';
import '../../../../core/widgets/book_selection_sheet.dart';
import '../../../../core/widgets/user_avatar.dart';

class MineProfileSection extends StatefulWidget {
  const MineProfileSection({super.key});

  @override
  State<MineProfileSection> createState() => _MineProfileSectionState();
}

class _MineProfileSectionState extends State<MineProfileSection> {
  final UserStatsDao _userStatsDao = UserStatsDao();
  final StatsDao _statsDao = StatsDao();
  
  UserStats? _stats;
  BookProgress? _bookProgress;
  bool _isLoading = true;
  List<dynamic> _booksManifest = [];
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadStats();
    GlobalStatsNotifier.instance.addListener(_loadStats);
  }

  @override
  void dispose() {
    GlobalStatsNotifier.instance.removeListener(_loadStats);
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _userStatsDao.getUserStats();
      String bookId = stats.currentBookId;
      if (bookId.isEmpty) {
        bookId = 'waiyan_${stats.currentGrade}_${stats.currentSemester}';
      }
      final bookProg = await _statsDao.getBookProgress(bookId);

      if (_booksManifest.isEmpty) {
        _booksManifest = await DatabaseHelper().loadBooksManifest();
      }

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _bookProgress = bookProg;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = '页面加载失败，请重试';
      });
    }
  }

  Future<void> _showBookSelectionDialog() async {
    final books = _booksManifest;
    if (books.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('教材列表为空，请稍后重试'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selected = await BookSelectionSheet.show(
      context: context,
      books: books,
      title: '选择教材',
      selectedBookId: _stats?.currentBookId,
      selectedGrade: _stats?.currentGrade,
      selectedSemester: _stats?.currentSemester,
    );
    if (selected == null) return;
    if (selected.id == null ||
        selected.grade == null ||
        selected.semester == null) {
      return;
    }
    await _userStatsDao.updateCurrentBook(
      selected.id!,
      selected.grade!,
      selected.semester!,
    );
    _loadStats();
    GlobalStatsNotifier.instance.notify();
  }

  Future<void> _showAvatarSelectionDialog() async {
    if (_stats == null) return;
    final selectedKey = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          constraints: const BoxConstraints(maxHeight: 500),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Row(
                  children: [
                    Text(
                      '选择头像',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textHighEmphasis,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade100),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: UserAvatar.presets.length,
                  itemBuilder: (context, index) {
                    final preset = UserAvatar.presets[index];
                    final selected = preset.key == _stats!.avatarKey;
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, preset.key),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          UserAvatar(
                            avatarKey: preset.key,
                            size: 62,
                            borderWidth: selected ? 3 : 2,
                          ),
                          if (selected)
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(3),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        );
      },
    );
    if (selectedKey == null || selectedKey == _stats!.avatarKey) return;
    final updated = _stats!.copyWith(avatarKey: selectedKey);
    await _userStatsDao.updateUserStats(updated);
    if (!mounted) return;
    setState(() => _stats = updated);
    GlobalStatsNotifier.instance.notify();
  }

  Future<void> _showEditNicknameDialog() async {
    final TextEditingController controller = TextEditingController(
      text: _stats?.nickname ?? '',
    );

    final newNickname = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    offset: const Offset(0, 8),
                    blurRadius: 32,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFF6FF), // 配色
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mode_edit_outline_rounded,
                      color: AppColors.primary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '修改昵称',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textHighEmphasis,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: controller,
                    maxLength: 12,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textHighEmphasis,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: "输入新昵称",
                      hintStyle: GoogleFonts.plusJakartaSans(
                        color: Colors.grey.shade400,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context, null),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            backgroundColor: AppColors.background,
                          ),
                          child: Text(
                            '取消',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              color: AppColors.textMediumEmphasis,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BubblyButton(
                          onPressed: () {
                            if (controller.text.trim().isNotEmpty) {
                              Navigator.pop(context, controller.text.trim());
                            }
                          },
                          color: AppColors.primary,
                          shadowColor: AppColors.shadowBlue,
                          borderRadius: 14,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: Text(
                              '确认',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (newNickname != null &&
        newNickname.isNotEmpty &&
        _stats != null &&
        newNickname != _stats!.nickname) {
      final updatedStats = _stats!.copyWith(nickname: newNickname);
      await _userStatsDao.updateUserStats(updatedStats);
      _loadStats();
      GlobalStatsNotifier.instance.notify();
    }
  }

  String _getCurrentBookName() {
    if (_stats == null) return '加载中...';

    // 细节处理
    final bookId = _stats!.currentBookId;
    if (bookId.isNotEmpty && _booksManifest.isNotEmpty) {
      final idx = _booksManifest.indexWhere((b) => b['id'] == bookId);
      if (idx >= 0) {
        final book = _booksManifest[idx];
        return (book['name'] ?? '').toString();
      }
    }

    // 细节处理
    if (_booksManifest.isNotEmpty) {
      final idx = _booksManifest.indexWhere(
        (b) =>
            b['grade'] == _stats!.currentGrade &&
            b['semester'] == _stats!.currentSemester,
      );
      if (idx >= 0) {
        final book = _booksManifest[idx];
        return (book['name'] ?? '').toString();
      }
    }

    // 细节处理
    return _getGradeLabel(_stats!.currentGrade, _stats!.currentSemester);
  }

  String _getGradeLabel(int grade, int semester) {
    String gradeStr = '';
    switch (grade) {
      case 7:
        gradeStr = '七年级';
        break;
      case 8:
        gradeStr = '八年级';
        break;
      case 9:
        gradeStr = '九年级';
        break;
      default:
        gradeStr = '$grade年级';
    }
    String semesterStr = semester == 1 ? '上册' : '下册';
    return '$gradeStr$semesterStr';
  }

  Widget _buildCurrentBookCard() {
    final percentage = _bookProgress?.percentage ?? 0.0;
    final learned = _bookProgress?.learned ?? 0;
    final total = _bookProgress?.total ?? 0;

    return GestureDetector(
      onTap: _showBookSelectionDialog,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowWhite,
              offset: Offset(0, 8),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前教材',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textMediumEmphasis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getCurrentBookName(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textHighEmphasis,
                          overflow: TextOverflow.ellipsis,
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                // 细节处理
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMediumEmphasis,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '总体进度',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  '${(percentage * 100).toStringAsFixed(1)}%',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: percentage,
                minHeight: 12,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '已掌握 $learned / $total 词',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMediumEmphasis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator())
      );
    }
    if (_loadError != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.orange,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              _loadError!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textHighEmphasis,
              ),
            ),
            const SizedBox(height: 16),
            BubblyButton(
              onPressed: () {
                setState(() => _isLoading = true);
                _loadStats();
              },
              color: AppColors.primary,
              shadowColor: AppColors.shadowBlue,
              borderRadius: 12,
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              child: Text(
                '重新加载',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        GestureDetector(
          onTap: _showAvatarSelectionDialog,
          child: UserAvatar(
            avatarKey: _stats?.avatarKey,
            size: 100,
            borderWidth: 3,
          ),
        )
        .animate()
        .scale(
          begin: const Offset(0.5, 0.5), 
          duration: 800.ms, 
          curve: Curves.elasticOut
        )
        .fadeIn(duration: 400.ms),
        const SizedBox(height: 8),
        Text(
          '点击更换头像',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: AppColors.textMediumEmphasis,
            fontWeight: FontWeight.w600,
          ),
        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _showEditNicknameDialog,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _stats?.nickname ?? '学习者',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textHighEmphasis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.mode_edit_outline_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
        const SizedBox(height: 40),
        _buildCurrentBookCard()
            .animate()
            .fadeIn(duration: 500.ms, delay: 450.ms)
            .slideY(begin: 0.15, end: 0, curve: Curves.easeOutBack),
      ],
    );
  }
}
