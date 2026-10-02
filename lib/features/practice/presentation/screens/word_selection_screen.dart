import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/database/daos/word_dao.dart';
import '../../../../core/database/daos/user_stats_dao.dart';
import '../../../../core/database/models/word.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/bubbly_button.dart';

class WordSelectionScreen extends StatefulWidget {
  const WordSelectionScreen({super.key});

  @override
  State<WordSelectionScreen> createState() => _WordSelectionScreenState();
}



class _WordSelectionScreenState extends State<WordSelectionScreen> {
  final WordDao _wordDao = WordDao();
  final UserStatsDao _userStatsDao = UserStatsDao();
  Word? _currentWord;
  List<Word> _options = [];
  bool _isLoading = true;
  String? _selectedOptionId;

  @override
  void initState() {
    super.initState();
    _loadNewWord();
  }

  Future<void> _loadNewWord() async {
    setState(() {
      _isLoading = true;
      _selectedOptionId = null;
    });

    try {
      final stats = await _userStatsDao.getUserStats();
      // 优先使用教材编号获取新词
      final words = await _wordDao.getNewWords(
        4, 
        bookId: stats.currentBookId.isNotEmpty ? stats.currentBookId : null,
        grade: stats.currentGrade, 
        semester: stats.currentSemester
      );
      if (words.isNotEmpty) {
        _currentWord = words[0];
        _options = List.from(words)..shuffle();
      }
    } catch (e) {
      debugPrint('Error loading words: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleOptionSelected(String wordId) {
    if (_selectedOptionId != null) return; // 已选择则忽略

    setState(() {
      _selectedOptionId = wordId;
    });

    // 稍作延迟以展示结果
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _loadNewWord();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentWord == null) {
       return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(),
        body: const Center(child: Text('No words available for practice!')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_currentWord!.unit, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.stars, color: AppColors.secondary, size: 20),
                SizedBox(width: 4),
                Text('120 XP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          )
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 细节处理
          final isWide = constraints.maxWidth > 600 || (constraints.maxWidth > constraints.maxHeight && constraints.maxWidth > 480);

          if (isWide) {
            return Row(
              children: [
                // 细节处理
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: _buildWordCard(),
                  ),
                ),
                // 细节处理
                Expanded(
                  flex: 5,
                  child: Container(
                     padding: const EdgeInsets.all(24.0),
                     decoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: Colors.black12)),
                        color: Colors.white54,
                     ),
                     child: Column(
                       mainAxisAlignment: MainAxisAlignment.center,
                       children: [
                         const Align(
                            alignment: Alignment.centerLeft, 
                            child: Text('SELECT THE CORRECT MEANING', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textMediumEmphasis, letterSpacing: 1.0))
                          ),
                          const SizedBox(height: 16),
                          ..._options.map((optionWord) => 
                             Padding(
                               padding: const EdgeInsets.only(bottom: 12),
                               child: _buildOption(context, optionWord),
                             )
                           ),
                       ],
                     ),
                  ),
                ),
              ],
            );
          }

          // 细节处理
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                _buildWordCard(),
                const SizedBox(height: 32),
                const Align(
                  alignment: Alignment.centerLeft, 
                  child: Text('SELECT THE CORRECT MEANING', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textMediumEmphasis, letterSpacing: 1.0))
                ),
                 const SizedBox(height: 16),
                 
                 ..._options.map((optionWord) => 
                   Padding(
                     padding: const EdgeInsets.only(bottom: 12),
                     child: _buildOption(context, optionWord),
                   )
                 ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWordCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: const [
            BoxShadow(color: AppColors.shadowWhite, offset: Offset(0, 4), blurRadius: 0)
          ]
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(_currentWord!.text, style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.primary)),
          const SizedBox(height: 8),
          Text(_currentWord!.meaning, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textHighEmphasis)),
          const SizedBox(height: 8),
          Text(_currentWord!.displayPhonetic, style: const TextStyle(fontSize: 18, color: AppColors.textMediumEmphasis, fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),

          // 细节处理
          Container(
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
            ),
            child: IconButton(
              padding: const EdgeInsets.all(14),
              onPressed: () {},
              icon: const Icon(Icons.volume_up_rounded, color: AppColors.shadowWhite, size: 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(BuildContext context, Word optionWord) {
    // 细节处理
    final isSelected = _selectedOptionId == optionWord.id;
    // 细节处理
    final isCorrect = optionWord.id == _currentWord!.id;
    
    // 细节处理
    Color? buttonColor = Colors.white;
    Color? textColor = AppColors.textHighEmphasis;
    Widget? icon;

    if (_selectedOptionId != null) {
      if (isCorrect) {
        buttonColor = Colors.green.shade50;
        textColor = Colors.green.shade800;
        icon = const Icon(Icons.check, size: 20, color: Colors.green);
      } else if (isSelected) {
        buttonColor = Colors.red.shade50;
        textColor = Colors.red.shade800;
        icon = const Icon(Icons.close, size: 20, color: Colors.red);
      }
    }

    // 逻辑处理
    // 逻辑处理
    // 逻辑处理
    // 细节处理
    final displayText = "${optionWord.meaning} (${optionWord.text})";

    return BubblyButton(
      onPressed: () => _handleOptionSelected(optionWord.id),
      color: buttonColor,
      shadowColor: Colors.grey.shade200,
      shadowHeight: 4,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(displayText, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor))),
           Container(
             width: 24, height: 24,
             decoration: BoxDecoration(
               shape: BoxShape.circle,
               border: Border.all(color: Colors.grey.shade300, width: 2),
             ),
             child: icon,
           )
        ],
      )
    );
  }
}
