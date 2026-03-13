import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  static const routeName = '/splash';

  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _seenKey = 'seen_splash';

  late final AnimationController _floatController;
  late final AnimationController _pulseController;
  late final Animation<double> _floatAnimation;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
    _floatAnimation = CurvedAnimation(
      parent: _floatController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: -8.0, end: 8.0));
  }

  Future<void> _complete() async {
    if (!mounted || _navigated) return;
    _navigated = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  @override
  void dispose() {
    _floatController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isCompact = width < 360;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _complete,
        child: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF5F7F8),
                  Color(0xFFEAF2FF),
                  Color(0xFFFFF4D6),
                ],
              ),
            ),
            child: Stack(
              children: [
                _buildGlow(
                  alignment: const Alignment(-0.9, -0.8),
                  color: AppColors.primary.withValues(alpha: 0.16),
                  size: 220,
                ),
                _buildGlow(
                  alignment: const Alignment(0.95, -0.4),
                  color: AppColors.secondary.withValues(alpha: 0.18),
                  size: 200,
                ),
                _buildGlow(
                  alignment: const Alignment(0.2, 0.9),
                  color: AppColors.primary.withValues(alpha: 0.12),
                  size: 240,
                ),
                SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            const Spacer(flex: 2),
                            AnimatedBuilder(
                              animation: _floatAnimation,
                              builder: (context, child) => Transform.translate(
                                offset: Offset(0, _floatAnimation.value),
                                child: child,
                              ),
                              child: _buildCardStack(isCompact: isCompact),
                            ),
                            const SizedBox(height: 28),
                            _buildBranding(isCompact: isCompact)
                                .animate()
                                .fadeIn(duration: 400.ms, delay: 200.ms)
                                .slideY(
                                  begin: 0.1,
                                  end: 0,
                                  curve: Curves.easeOutBack,
                                ),
                            const Spacer(flex: 1),
                            Text(
                              '轻触进入',
                              style: GoogleFonts.notoSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMediumEmphasis,
                                letterSpacing: 1.2,
                              ),
                            ).animate().fadeIn(duration: 600.ms, delay: 600.ms),
                            const SizedBox(height: 8),
                            _buildLoadingDots().animate().fadeIn(duration: 600.ms, delay: 700.ms),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlow({
    required Alignment alignment,
    required Color color,
    required double size,
  }) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: size * 0.6,
              spreadRadius: size * 0.05,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardStack({required bool isCompact}) {
    final baseWidth = isCompact ? 240.0 : 280.0;
    final baseHeight = isCompact ? 190.0 : 210.0;

    return SizedBox(
      width: baseWidth + 40,
      height: baseHeight + 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 18,
            left: 6,
            child: Transform.rotate(
              angle: -0.08,
              child: _buildBackdropCard(
                width: baseWidth * 0.9,
                height: baseHeight * 0.75,
                color: const Color(0xFFFFF1C2),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 4,
            child: Transform.rotate(
              angle: 0.06,
              child: _buildBackdropCard(
                width: baseWidth * 0.92,
                height: baseHeight * 0.78,
                color: const Color(0xFFE3EDFF),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: _buildMainCard(
              width: baseWidth,
              height: baseHeight,
            ).animate().fadeIn(duration: 400.ms),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdropCard({
    required double width,
    required double height,
    required Color color,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildPillLabel(),
              const Spacer(),
              _buildSpeakerBadge(),
            ],
          ),
          const Spacer(),
          Text(
            'Focus',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textHighEmphasis,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '/\u02c8fo\u028ak\u0259s/',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMediumEmphasis,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '\u4e13\u6ce8\uff1b\u96c6\u4e2d\u6ce8\u610f',
            style: GoogleFonts.notoSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textHighEmphasis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillLabel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        'DAILY CARD',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildSpeakerBadge() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.volume_up_rounded,
        size: 18,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildBranding({required bool isCompact}) {
    return Column(
      children: [
        Text(
          '灵听单词 (AuraWord)',
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSans(
            fontSize: isCompact ? 24 : 28,
            fontWeight: FontWeight.w900,
            color: AppColors.textHighEmphasis,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '让单词成为习惯',
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSans(
            fontSize: isCompact ? 13 : 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textMediumEmphasis,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingDots() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final t = (_pulseController.value + index * 0.18) % 1.0;
            final wave = 1 - (2 * (t - 0.5).abs());
            final scale = 0.6 + 0.4 * wave;
            final opacity = 0.45 + 0.45 * wave;
            return Container(
              margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
