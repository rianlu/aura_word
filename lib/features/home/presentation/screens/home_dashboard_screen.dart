import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/bubbly_button.dart';
import '../../../../core/widgets/animated_speaker_button.dart';

import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/database/daos/user_stats_dao.dart';

import '../../../../core/database/models/user_stats.dart';
import '../../../../core/services/iciba_daily_service.dart';
import '../../../../core/services/audio_service.dart';
import '../../../learning/presentation/screens/daily_learning_session_screen.dart';
import '../../../practice/presentation/screens/review_session_screen.dart';

import '../../../../core/services/global_stats_notifier.dart';
import '../../../../core/widgets/user_avatar.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  final UserStatsDao _userStatsDao = UserStatsDao();

  UserStats? _stats;
  bool _isLoading = true;
  DailySentence? _dailySentence;
  bool _isPlayingAudio = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadQuote();
    // 逻辑处理
    GlobalStatsNotifier.instance.addListener(_loadStats);
  }

  Future<void> _loadQuote() async {
    final sentence = await IcibaDailyService().getTodaySentence();
    if (mounted) {
      setState(() => _dailySentence = sentence);
    }
  }

  @override
  void dispose() {
    GlobalStatsNotifier.instance.removeListener(_loadStats);
    super.dispose();
  }

  Future<void> _loadStats() async {
    final stats = await _userStatsDao.getUserStats();

    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: MediaQuery.of(context).padding.top),
                      _buildHeader()
                          .animate()
                          .fadeIn(duration: 400.ms)
                          .slideY(
                            begin: 0.1,
                            end: 0,
                            curve: Curves.easeOutBack,
                          ),
                      const SizedBox(height: 20),
                      if (_dailySentence != null)
                        _buildDailySentenceCard()
                            .animate()
                            .fadeIn(duration: 450.ms, delay: 100.ms)
                            .slideY(
                              begin: 0.15,
                              end: 0,
                              curve: Curves.easeOutBack,
                            ),

                      if (_dailySentence != null) const SizedBox(height: 20),

                      _buildDailyQuestSection(context),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _playDailyAudio() async {
    // 逻辑处理
    if (_isPlayingAudio ||
        (_dailySentence?.audioUrl == null &&
            _dailySentence?.englishContent == null)) {
      return;
    }

    setState(() => _isPlayingAudio = true);
    try {
      await AudioService().playUrl(
        _dailySentence!.audioUrl ?? "", // 音频控制
        fallbackText: _dailySentence!.englishContent,
      );
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) setState(() => _isPlayingAudio = false);
      }
    }
  }

  /// 逻辑处理
  Widget _buildDailySentenceCard() {
    return GestureDetector(
      onTap: _playDailyAudio,
      child: PhysicalShape(
        clipper: const TicketClipper(
          holeRadius: 20,
          holePositionRatio: 0.72,
        ), // 裁剪形状
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        elevation: 6,
        shadowColor: AppColors.primary.withValues(alpha: 0.15),
        child: SizedBox(
          height: 180, // 布局尺寸
          child: Stack(
            children: [
              // 逻辑处理
              // 逻辑处理
              // 逻辑处理
              LayoutBuilder(
                builder: (context, constraints) {
                  final splitX = constraints.maxWidth * 0.72;
                  return Stack(
                    children: [
                      Positioned(
                        left: splitX,
                        top: 10,
                        bottom: 10,
                        child: CustomPaint(
                          size: const Size(1, double.infinity),
                          painter: DashedLinePainter(
                            color: const Color(0xFFE5E7EB),
                            dashHeight: 8,
                            dashSpace: 6,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          // 逻辑处理
                          Expanded(
                            flex: 72,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                20,
                                12,
                                20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 逻辑处理
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.secondary,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'DAILY QUOTE',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),

                                  const Spacer(),

                                  // 逻辑处理
                                  Text(
                                    _dailySentence!.englishContent,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textHighEmphasis,
                                      height: 1.3,
                                    ),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  const SizedBox(height: 8),

                                  // 逻辑处理
                                  Text(
                                    _dailySentence!.chineseNote,
                                    style: GoogleFonts.notoSans(
                                      fontSize: 12,
                                      color: AppColors.textMediumEmphasis,
                                      height: 1.4,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 逻辑处理
                          Expanded(
                            flex: 28,
                            child: Center(
                              child: AnimatedSpeakerButton(
                                onPressed: _playDailyAudio,
                                isPlaying: _isPlayingAudio,
                                size: 32, // 逻辑处理
                                variant: SpeakerButtonVariant.neutral,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            UserAvatar(avatarKey: _stats?.avatarKey, size: 48, borderWidth: 2),
            const SizedBox(width: 12),
            Text(
              '你好, ${_stats?.nickname ?? "Friend"}! 👋',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textHighEmphasis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDailyQuestSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '每日任务 🚀',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textHighEmphasis,
          ),
        ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1, end: 0, curve: Curves.easeOutBack),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth > 500) {
              return Row(
                children: [
                  Expanded(
                    child: _buildLearningButton(context)
                        .animate()
                        .fadeIn(duration: 500.ms, delay: 300.ms)
                        .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack)
                        .slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildReviewButton(context)
                        .animate()
                        .fadeIn(duration: 500.ms, delay: 400.ms)
                        .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack)
                        .slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLearningButton(context)
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 300.ms)
                    .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack)
                    .slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
                const SizedBox(height: 16),
                _buildReviewButton(context)
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 400.ms)
                    .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack)
                    .slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildLearningButton(BuildContext context) {
    return BubblyButton(
      onPressed: () async {
        // 逻辑处理
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DailyLearningSessionScreen(),
          ),
        );

        // 逻辑处理
        if (mounted) _loadStats();
      },
      color: AppColors.primary,
      shadowColor: AppColors.shadowBlue,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.menu_book, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            '学习新单词',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '今天探索 10 个新单词！',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewButton(BuildContext context) {
    return BubblyButton(
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ReviewSessionScreen()),
        );
        // 逻辑处理
        if (mounted) _loadStats();
      },
      color: AppColors.secondary,
      shadowColor: AppColors.shadowYellow,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.style, color: Color(0xFF92400E), size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            '复习',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF92400E),
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '保持记忆清晰！',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xAA92400E),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class WavyClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    // 逻辑处理
    double waveHeight = 6.0; // 逻辑处理
    double frequency = 20.0; // 逻辑处理

    path.moveTo(0, 0);

    // 逻辑处理
    for (double i = 0; i < size.width; i += frequency) {
      path.quadraticBezierTo(i + frequency / 2, waveHeight, i + frequency, 0);
    }

    // 逻辑处理
    for (double i = 0; i < size.height; i += frequency) {
      path.quadraticBezierTo(
        size.width - waveHeight,
        i + frequency / 2,
        size.width,
        i + frequency,
      );
    }

    // 逻辑处理
    for (double i = size.width; i > 0; i -= frequency) {
      path.quadraticBezierTo(
        i - frequency / 2,
        size.height - waveHeight,
        i - frequency,
        size.height,
      );
    }

    // 逻辑处理
    for (double i = size.height; i > 0; i -= frequency) {
      path.quadraticBezierTo(waveHeight, i - frequency / 2, 0, i - frequency);
    }

    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class TicketClipper extends CustomClipper<Path> {
  final double holeRadius;
  final double holePositionRatio; // 逻辑处理

  const TicketClipper({this.holeRadius = 16, this.holePositionRatio = 0.7});

  @override
  Path getClip(Size size) {
    final path = Path();
    final holeX = size.width * holePositionRatio;

    path.moveTo(0, 0);

    // 逻辑处理
    path.lineTo(holeX - holeRadius, 0);
    path.arcToPoint(
      Offset(holeX + holeRadius, 0),
      radius: Radius.circular(holeRadius),
      clockwise: false,
    );
    path.lineTo(size.width, 0);

    // 逻辑处理
    path.lineTo(size.width, size.height);

    // 逻辑处理
    path.lineTo(holeX + holeRadius, size.height);
    path.arcToPoint(
      Offset(holeX - holeRadius, size.height),
      radius: Radius.circular(holeRadius),
      clockwise: false,
    );
    path.lineTo(0, size.height);

    // 逻辑处理
    path.close();

    return path;
  }

  @override
  bool shouldReclip(TicketClipper oldClipper) => true;
}

class DashedLinePainter extends CustomPainter {
  final Color color;
  final double dashHeight;
  final double dashSpace;

  DashedLinePainter({
    required this.color,
    this.dashHeight = 5,
    this.dashSpace = 5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double startY = 0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    while (startY < size.height) {
      canvas.drawLine(Offset(0, startY), Offset(0, startY + dashHeight), paint);
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
