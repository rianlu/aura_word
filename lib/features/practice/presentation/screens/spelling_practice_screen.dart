import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/bubbly_button.dart';
import '../../../../core/database/daos/word_dao.dart';
import '../../../../core/database/daos/user_stats_dao.dart';
import '../../../../core/database/models/word.dart';

class SpellingPracticeScreen extends StatefulWidget {
  const SpellingPracticeScreen({super.key});

  @override
  State<SpellingPracticeScreen> createState() => _SpellingPracticeScreenState();
}



class _SpellingPracticeScreenState extends State<SpellingPracticeScreen> {
  final WordDao _wordDao = WordDao();
  final UserStatsDao _userStatsDao = UserStatsDao();
  Word? _currentWord;
  bool _isLoading = true;

  // 游戏状态
  String _targetWord = "";
  List<int> _missingIndices = [];
  List<String> _userInputs = [];
  List<String> _keyboardLetters = [];

  @override
  void initState() {
    super.initState();
    _loadNewWord();
  }

  Future<void> _loadNewWord() async {
    setState(() {
      _isLoading = true;
      _userInputs = [];
      _missingIndices = [];
      _keyboardLetters = [];
    });

    try {
      final stats = await _userStatsDao.getUserStats();
      final words = await _wordDao.getNewWords(
        1,
        bookId: stats.currentBookId.isNotEmpty ? stats.currentBookId : null,
        grade: stats.currentGrade,
        semester: stats.currentSemester
      );
      if (words.isNotEmpty) {
        _currentWord = words.first;
        _targetWord = _currentWord!.text;
        _initializeGame();
      }
    } catch (e) {
      debugPrint('Error loading word: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _initializeGame() {
    if (_targetWord.isEmpty) return;

    final random = Random();
    int len = _targetWord.length;
    // 计算隐藏字母数量
    int missingCount = (len * 0.4).ceil().clamp(1, min(len - 1, 7));
    
    // 随机选择唯一索引
    Set<int> indices = {};
    while (indices.length < missingCount) {
      indices.add(random.nextInt(len));
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
  }

  void _handleLetterInput(String char) {
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
    // 找到最后一个已填位置
    int lastFilledIndex = _userInputs.lastIndexWhere((element) => element.isNotEmpty);
    if (lastFilledIndex != -1) {
      setState(() {
        _userInputs[lastFilledIndex] = "";
      });
    }
  }

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
         Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('Correct!'), backgroundColor: Colors.green)
               );
               _loadNewWord();
            }
         });
      } else {
        // 错误
         Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('Try again!'), backgroundColor: Colors.red)
               );
               // 细节处理
               setState(() {
                 _userInputs = List.filled(_userInputs.length, "");
               });
            }
         });
      }
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

    if (_currentWord == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ),
        body: const Center(child: Text('No words available')),
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
        centerTitle: true,
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
                Icon(Icons.stars_rounded, color: AppColors.secondary, size: 20),
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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        _buildWordCard(),
                        const SizedBox(height: 20),
                        _buildSentenceCard(),
                      ],
                    ),
                  ),
                ),
                
                // 细节处理
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      border: Border(left: BorderSide(color: Colors.black12)),
                      color: Colors.white54,
                    ),
                    child: Column(
                      children: [
                        const Spacer(),
                        _buildPuzzleArea(),
                        const SizedBox(height: 40),
                        _buildLetterButtons(),
                        const Spacer(),
                        _buildProgressSection(),
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      _buildWordCard(),
                      const SizedBox(height: 20),
                      _buildSentenceCard(),
                       const SizedBox(height: 40),
                      _buildPuzzleArea(),
                      const SizedBox(height: 40),
                      _buildLetterButtons(),
                    ],
                  ),
                ),
              ),
              _buildProgressSection(),
            ],
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
          Text(_currentWord!.meaning, style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.primary)),
          const SizedBox(height: 16),
          Text(_currentWord!.displayPhonetic, style: const TextStyle(fontSize: 18, color: AppColors.textMediumEmphasis, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
  
  Widget _buildSentenceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
         borderRadius: BorderRadius.circular(12),
         border: const Border(left: BorderSide(color: AppColors.primary, width: 4)),
         boxShadow: const [
            BoxShadow(color: AppColors.shadowWhite, offset: Offset(0, 2), blurRadius: 0)
         ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EXAMPLE SENTENCE', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textMediumEmphasis, letterSpacing: 1.0)),
           const SizedBox(height: 8),
           Text(
               // 细节处理
               'No example sentence available.',
               style: GoogleFonts.plusJakartaSans(fontSize: 18, color: AppColors.textHighEmphasis, height: 1.5, fontWeight: FontWeight.w500),
           ),
        ],
      ),
    );
  }

  Widget _buildPuzzleArea() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
         color: Colors.white,
         borderRadius: BorderRadius.circular(20),
         border: Border.all(color: Colors.grey.shade200),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 16,
        children: List.generate(_targetWord.length, (index) {
           bool isMissing = _missingIndices.contains(index);
           String char = _targetWord[index];
           
           String displayChar = char;
           Color textColor = AppColors.textHighEmphasis;
           bool showUnderscore = false;

           if (isMissing) {
             int slotIndex = _missingIndices.indexOf(index);
             if (slotIndex < _userInputs.length && _userInputs[slotIndex].isNotEmpty) {
               displayChar = _userInputs[slotIndex];
               textColor = AppColors.primary; 
             } else {
               displayChar = "";
               showUnderscore = true;
             }
           }

           return Column(
             children: [
               Text(
                 displayChar, 
                 style: GoogleFonts.plusJakartaSans(
                   fontSize: 28, 
                   fontWeight: FontWeight.w900, 
                   color: textColor
                 )
               ),
               Container(
                 width: 24, 
                 height: 4, 
                 margin: const EdgeInsets.only(top: 4),
                 color: showUnderscore ? Colors.grey.shade300 : (isMissing ? AppColors.primary : Colors.transparent)
               ),
             ],
           );
        }),
      ),
    );
  }

  Widget _buildLetterButtons() {
    final row1 = _keyboardLetters.take(4).toList();
    final row2 = _keyboardLetters.skip(4).take(3).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final buttonSize = ((constraints.maxWidth - spacing * 3) / 4).clamp(44.0, 72.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < row1.length; i++) ...[
                  _buildLetterButton(row1[i], size: buttonSize),
                  if (i != row1.length - 1) const SizedBox(width: spacing),
                ],
              ],
            ),
            const SizedBox(height: spacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < row2.length; i++) ...[
                  _buildLetterButton(row2[i], size: buttonSize),
                  const SizedBox(width: spacing),
                ],
                _buildBackspaceButton(size: buttonSize),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildLetterButton(String char, {double size = 64}) {
    return SizedBox(
      width: size, height: size,
      child: BubblyButton(
        onPressed: () => _handleLetterInput(char),
        color: AppColors.secondary,
        shadowColor: const Color(0xFFd4aa00), 
        padding: EdgeInsets.zero,
        borderRadius: 32,
        child: Center(
          child: Text(char, style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.bold, color: AppColors.textHighEmphasis)),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton({double size = 64}) {
     return SizedBox(
      width: size, height: size,
      child: BubblyButton(
        onPressed: _handleBackspace,
        color: const Color(0xFFe2e8f0),
        shadowColor: const Color(0xFFcbd5e1),
        padding: EdgeInsets.zero,
        borderRadius: 32,
        child: Center(
          child: Icon(Icons.backspace, color: AppColors.textMediumEmphasis, size: size * 0.36),
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: const LinearProgressIndicator(
              value: 0.66, 
              color: AppColors.primary,
              backgroundColor: Color(0xFFe2e8f0),
              minHeight: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL PROGRESS', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textMediumEmphasis, letterSpacing: 1.0)),
              Text('8 / 12 WORDS', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textMediumEmphasis, letterSpacing: 1.0)),
            ],
          )
        ],
      ),
    );
  }
}
