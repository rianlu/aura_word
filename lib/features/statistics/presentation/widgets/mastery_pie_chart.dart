import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/database/daos/stats_dao.dart';
import '../../../../core/theme/app_colors.dart';

class MasteryPieChart extends StatefulWidget {
  final MasteryDistribution distribution;

  const MasteryPieChart({super.key, required this.distribution});

  @override
  State<MasteryPieChart> createState() => _MasteryPieChartState();
}

class _MasteryPieChartState extends State<MasteryPieChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    // 逻辑处理
    const colorMastered = Color(0xFF22C55E); // 绿色 500
    const colorReviewing = Color(0xFFF59E0B); // 配色
    const colorNew = Color(0xFF94A3B8); // 配色

    final total = widget.distribution.newWords + 
                  widget.distribution.learning + 
                  widget.distribution.mastered;
                  
    // 逻辑处理
    final safeTotal = total == 0 ? 1 : total; 

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: const [
          BoxShadow(color: AppColors.shadowWhite, offset: Offset(0, 4), blurRadius: 16)
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.pie_chart_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text('词汇掌握度', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textHighEmphasis)),
            ],
          ),
          const SizedBox(height: 24),
          
          SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            _touchedIndex = -1;
                            return;
                          }
                          _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                    borderData: FlBorderData(show: false),
                    sectionsSpace: 2,
                    centerSpaceRadius: 60,
                    startDegreeOffset: -90,
                    sections: [
                      // 逻辑处理
                      PieChartSectionData(
                        color: colorMastered,
                        value: widget.distribution.mastered.toDouble(),
                        title: '${((widget.distribution.mastered / safeTotal) * 100).round()}%',
                        radius: _touchedIndex == 0 ? 30 : 25,
                        titleStyle: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        showTitle: widget.distribution.mastered > 0,
                      ),
                      // 逻辑处理
                      PieChartSectionData(
                        color: colorReviewing,
                        value: widget.distribution.learning.toDouble(),
                        title: '${((widget.distribution.learning / safeTotal) * 100).round()}%',
                        radius: _touchedIndex == 1 ? 30 : 25,
                        titleStyle: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        showTitle: widget.distribution.learning > 0,
                      ),
                      // 逻辑处理
                      PieChartSectionData(
                        color: colorNew,
                        value: widget.distribution.newWords.toDouble(),
                        title: '${((widget.distribution.newWords / safeTotal) * 100).round()}%',
                        radius: _touchedIndex == 2 ? 30 : 25,
                        titleStyle: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        showTitle: widget.distribution.newWords > 0,
                      ),
                    ],
                  ),
                ),
                
                // 逻辑处理
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "$total",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textHighEmphasis
                      ),
                    ),
                    Text(
                      "总词汇量",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMediumEmphasis
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 逻辑处理
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendItem("已掌握", widget.distribution.mastered, colorMastered, "≥21天"),
              _buildLegendItem("学习中", widget.distribution.learning, colorReviewing, "<21天"),
              _buildLegendItem("未学习", widget.distribution.newWords, colorNew, "0天"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, int count, Color color, String hint) {
    return Column(
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textMediumEmphasis)),
          ],
        ),
        const SizedBox(height: 4),
        Text("$count", style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHighEmphasis)),
      ],
    );
  }
}
