import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/database/models/word.dart';
import 'dart:math' as math;

enum PracticeSuccessVariant {
  learning,
  review,
}

class PracticeSuccessOverlay extends StatelessWidget {
  final Word word;
  final String title;
  final String? subtitle;
  final int stars; // 口语练习的星级（1-3 星）
  final PracticeSuccessVariant variant;

  const PracticeSuccessOverlay({
    super.key,
    required this.word,
    this.title = 'CORRECT!',
    this.subtitle,
    this.stars = 0, // 0 表示不显示星级（拼写练习）
    this.variant = PracticeSuccessVariant.learning,
  });


  @override
  Widget build(BuildContext context) {
    final isReview = variant == PracticeSuccessVariant.review;
    final accentColor = isReview ? AppColors.secondary : AppColors.primary;
    final accentTextColor = isReview ? const Color(0xFF92400E) : AppColors.primary; // 深琥珀色文字
    final iconBgColor = isReview ? AppColors.secondaryLight : const Color(0xFFEAF3FF);
    final iconColor = isReview ? const Color(0xFFB45309) : AppColors.primary; // 琥珀强调色

    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
      child: Container(
        color: Colors.black.withValues(alpha: 0.05), // 轻微遮罩（保持一致）
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack, // 轻微弹跳效果
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.8 + (0.2 * value),
                child: Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                   // 背景轻微闪光
                   const Positioned.fill(
                     child: SparkleBackground(),
                   ),
                   
                   // 主卡片
                   Container(
                     margin: const EdgeInsets.symmetric(horizontal: 24),
                     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                     decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                     ),
                     child: Row(
                       mainAxisSize: MainAxisSize.min,
                        children: [
                          // 左侧勾选图标
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: iconBgColor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded, 
                              color: iconColor,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 20),
                          
                          // 右侧内容
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 标题与可选星级
                                Row(
                                  children: [
                                    Text(
                                      title.toUpperCase(),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: accentTextColor,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    // 口语练习显示星级
                                    if (stars > 0) ...[
                                      const SizedBox(width: 8),
                                      ...List.generate(3, (i) => Icon(
                                        i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                                        color: i < stars ? Colors.amber : Colors.grey.shade300,
                                        size: 18,
                                      )),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  word.text,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: accentTextColor,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                     ),
                   ),
                   
                   // 漂浮小闪光图标
                   Positioned(
                     top: -10,
                     right: 15,
                     child: TweenAnimationBuilder<double>(
                       tween: Tween(begin: 0.0, end: 1.0),
                       duration: const Duration(milliseconds: 800),
                       builder: (context, val, child) {
                         return Transform.rotate(
                           angle: val * math.pi / 4,
                           child: Icon(Icons.auto_awesome_rounded, color: accentColor, size: 24),
                         );
                       },
                     ),
                   ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SparkleBackground extends StatefulWidget {
  const SparkleBackground({super.key});

  @override
  State<SparkleBackground> createState() => _SparkleBackgroundState();
}

class _SparkleBackgroundState extends State<SparkleBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<SparkleParticle> particles = List.generate(12, (index) => SparkleParticle());

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: SparklePainter(particles, _controller.value),
        );
      },
    );
  }
}

class SparkleParticle {
  late double x, y;
  late double size;
  late double opacity;
  
  SparkleParticle() {
    reset();
  }
  
  void reset() {
    final random = math.Random();
    x = random.nextDouble() * 300 - 150;
    y = random.nextDouble() * 150 - 75;
    size = random.nextDouble() * 4 + 2;
    opacity = random.nextDouble();
  }
}

class SparklePainter extends CustomPainter {
  final List<SparkleParticle> particles;
  final double animationValue;

  SparklePainter(this.particles, this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.amber.shade300;
    
    for (var particle in particles) {
      final double progress = (animationValue + particle.opacity) % 1.0;
      final double currentOpacity = math.sin(progress * math.pi) * 0.6;
      paint.color = Colors.amber.shade300.withValues(alpha: currentOpacity);
      
      canvas.drawCircle(
        Offset(size.width / 2 + particle.x, size.height / 2 + particle.y),
        particle.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
