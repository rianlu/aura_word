import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/database/daos/word_dao.dart';
import '../../../../core/database/daos/user_stats_dao.dart';
import '../../../../core/database/daos/stats_dao.dart';
import '../../../../core/database/models/word.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/audio_service.dart';
import '../../../../core/widgets/bubbly_button.dart';
import '../widgets/word_learning_card.dart';
import '../../../practice/presentation/widgets/speaking_practice_view.dart';
import '../../../practice/presentation/widgets/word_selection_view.dart';
import '../../../practice/presentation/widgets/spelling_practice_view.dart';

enum SessionPhase {
  learning,
  speaking,
  selection,
  spelling,
  completed
}

class DailyLearningSessionScreen extends StatefulWidget {
  const DailyLearningSessionScreen({super.key});

  @override
  State<DailyLearningSessionScreen> createState() => _DailyLearningSessionScreenState();
}

class _DailyLearningSessionScreenState extends State<DailyLearningSessionScreen> {
  final WordDao _wordDao = WordDao();
  final UserStatsDao _userStatsDao = UserStatsDao();
  
  List<Word> _sessionWords = [];
  bool _isLoading = true;
  DateTime? _sessionStart;
  
  SessionPhase _currentPhase = SessionPhase.learning;
  int _currentIndex = 0;
  
  // 细节处理
  bool _isTransitioning = false;
  int _transitionCountdown = 3;
  SessionPhase? _pendingNextPhase;

  Timer? _transitionTimer;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    AudioService().stop();
    super.dispose();
  }

  Future<void> _startSession() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _userStatsDao.getUserStats();
      // 优先使用教材编号获取新词
      final words = await _wordDao.getNewWords(
        10, 
        bookId: stats.currentBookId.isNotEmpty ? stats.currentBookId : null,
        grade: stats.currentGrade,
        semester: stats.currentSemester
      );
      
      if (mounted) {
        setState(() {
          _sessionWords = words;
          _isLoading = false;
          _sessionStart = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint("Error starting session: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _next() {
    if (_currentIndex < _sessionWords.length - 1) {
      setState(() {
        _currentIndex++;
      });
    } else {
      // 细节处理
      _triggerPhaseTransition();
    }
  }

  void _triggerPhaseTransition() {
    // 细节处理
    AudioService().stop(); // 音频控制
    SessionPhase next;
    switch (_currentPhase) {
        case SessionPhase.learning: next = SessionPhase.speaking; break;
        case SessionPhase.speaking: next = SessionPhase.selection; break;
        case SessionPhase.selection: next = SessionPhase.spelling; break;
        case SessionPhase.spelling: next = SessionPhase.completed; break;
        case SessionPhase.completed: next = SessionPhase.completed; break;
    }
    
    if (next == SessionPhase.completed) {
       _advancePhase(next);
       return;
    }

    // 细节处理
    setState(() {
      _isTransitioning = true;
      _transitionCountdown = 3;
      _pendingNextPhase = next;
    });

    _runTransitionCountdown(next);
  }

  void _runTransitionCountdown(SessionPhase nextPhase) {
     _transitionTimer?.cancel();
     _transitionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
       if (!mounted) {
         timer.cancel();
         return;
       }
       if (_transitionCountdown > 1) {
         setState(() => _transitionCountdown--);
       } else {
         timer.cancel();
         setState(() {
           _isTransitioning = false;
           _pendingNextPhase = null;
         });
         _advancePhase(nextPhase);
       }
     });
  }

  void _advancePhase(SessionPhase nextPhase) {
    setState(() {
      _currentIndex = 0;
      _currentPhase = nextPhase;
    });

    if (_currentPhase == SessionPhase.completed) {
       _handleSessionCompletion();
    }
  }
  
  Future<void> _handleSessionCompletion() async {
     await _saveProgress();
     if (mounted) _showCompletionDialog();
  }

  Future<void> _saveProgress() async {
    try {
       // 逻辑处理
       await _wordDao.batchMarkAsLearned(_sessionWords);
       
       // 细节处理
       final stats = await _userStatsDao.getUserStats();
       final now = DateTime.now();
       final todayStr = "${now.year}-${now.month}-${now.day}";
       
       bool isNewDay = stats.lastStudyDate != todayStr;
       
       final newStats = stats.copyWith(
         totalWordsLearned: stats.totalWordsLearned + _sessionWords.length,
         totalStudyDays: isNewDay ? stats.totalStudyDays + 1 : stats.totalStudyDays,
         continuousDays: isNewDay ? stats.continuousDays + 1 : stats.continuousDays,
         lastStudyDate: todayStr,
         updatedAt: now.millisecondsSinceEpoch
       );
       
       await _userStatsDao.updateUserStats(newStats);
       
       // 使用真实耗时（按分钟向上取整）
       final start = _sessionStart ?? DateTime.now();
       final minutes = ((DateTime.now().difference(start).inSeconds) / 60).ceil();
       await StatsDao().recordDailyActivity(
         newWords: _sessionWords.length, 
         reviewWords: 0, 
         correct: _sessionWords.length, // 学习完成视为正确
         wrong: 0, 
         minutes: minutes == 0 ? 1 : minutes
       );
       
       debugPrint("Progress Saved: ${_sessionWords.length} words.");
    } catch (e) {
      debugPrint("Error saving progress: $e");
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), offset: const Offset(0, 8), blurRadius: 32)
                ]
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 细节处理
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0FDF4), // 绿色 500
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.emoji_events_rounded, size: 48, color: Color(0xFF22C55E)), // 绿色 500
                  )
                  .animate()
                  .scale(duration: 800.ms, curve: Curves.elasticOut)
                  .fadeIn(),
                  const SizedBox(height: 20),
                  
                  Text(
                    "任务完成!", 
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textHighEmphasis)
                  ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
                  const SizedBox(height: 8),
                  Text(
                    "太棒了！你完成了今天的学习任务。",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textMediumEmphasis, height: 1.4)
                  ).animate().fadeIn(delay: 300.ms),

                  const SizedBox(height: 24),

                  // 细节处理
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade100)
                          ),
                          child: Column(
                            children: [
                              Text("${_sessionWords.length}", style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary)),
                              const SizedBox(height: 2),
                              Text("新学单词", style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMediumEmphasis)),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: 450.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade100)
                          ),
                          child: Column(
                            children: [
                              Text("+${_sessionWords.length * 10}", style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.secondary)),
                              const SizedBox(height: 2),
                              Text("获得经验", style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMediumEmphasis)),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: 550.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
                    ],
                  ),

                  const SizedBox(height: 24),
                  
                  // 细节处理
                  SizedBox(
                    width: double.infinity,
                    child: BubblyButton(
                      onPressed: () {
                         Navigator.pop(context); // 返回上一页
                         Navigator.pop(context); // 返回上一页
                      },
                      color: AppColors.primary,
                      shadowColor: AppColors.shadowBlue,
                      borderRadius: 14,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "完成",
                            style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                        ],
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _getPhaseTitle(SessionPhase phase) {
    switch (phase) {
      case SessionPhase.learning: return "学习阶段 (Learning)";
      case SessionPhase.speaking: return "口语练习 (Speaking)";
      case SessionPhase.selection: return "词义辨析 (Selection)";
      case SessionPhase.spelling: return "拼写练习 (Spelling)";
      case SessionPhase.completed: return "Completed";
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_sessionWords.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("该等级暂时没有新单词了!"),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("返回"))
            ],
          ),
        ),
      );
    }

    if (_currentPhase == SessionPhase.completed) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()), // 加载指示
      );
    }

    final double progress = (_currentIndex + 1) / _sessionWords.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_getPhaseTitle(_currentPhase), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6.0),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 4,
          ),
        )
      ),
      body: Stack(
        children: [
          _buildCurrentView(),
          
          if (_isTransitioning)
            Positioned.fill(
              child: Container(
                color: Colors.white,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "下一项: ${_getPhaseTitle(_pendingNextPhase!)}",
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 24, 
                          fontWeight: FontWeight.bold, 
                          color: AppColors.textMediumEmphasis
                        )
                      ).animate().fadeIn().slideY(begin: -0.2, end: 0, curve: Curves.easeOutBack),
                      const SizedBox(height: 32),
                      Container(
                        width: 140, height: 140,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4), 
                              blurRadius: 40, 
                              offset: const Offset(0, 10)
                            )
                          ]
                        ),
                        child: Text(
                          "$_transitionCountdown",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 72, 
                            fontWeight: FontWeight.w900, 
                            color: Colors.white
                          ),
                        ),
                      )
                      .animate(key: ValueKey(_transitionCountdown))
                      .scale(begin: const Offset(0.8, 0.8), duration: 400.ms, curve: Curves.elasticOut)
                      .shimmer(delay: 200.ms, duration: 800.ms),
                      const SizedBox(height: 32),
                      Text(
                        "准备开始!", 
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18, 
                          color: AppColors.textMediumEmphasis
                        )
                      ).animate().fadeIn(delay: 400.ms),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentView() {
    final word = _sessionWords[_currentIndex];
    final key = ValueKey("${_currentPhase}_${word.id}");

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: KeyedSubtree(
        key: key,
        child: _buildPhaseContent(word),
      )
    );
  }

  Widget _buildPhaseContent(Word word) {
    switch (_currentPhase) {
      case SessionPhase.learning:
        return WordLearningCard(
          word: word,
          onNext: _next,
        );
      case SessionPhase.speaking:
        return SpeakingPracticeView(
          word: word,
          isReviewMode: false,
          onCompleted: (_) => _next(),
        );
      case SessionPhase.selection:
        final distractors = List<Word>.from(_sessionWords)..removeWhere((w) => w.id == word.id);
        distractors.shuffle();
        final options = (distractors.take(3).toList() + [word])..shuffle();
        
        return WordSelectionView(
          word: word,
          options: options,
          isReviewMode: false,
          onCompleted: (_) => _next(),
        );
      case SessionPhase.spelling:
        return SpellingPracticeView(
          word: word,
          isReviewMode: false,
          onCompleted: (_) => _next(),
        );
      default:
        return const SizedBox();
    }
  }
}
