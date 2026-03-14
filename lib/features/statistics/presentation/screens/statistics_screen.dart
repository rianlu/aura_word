
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/services/global_stats_notifier.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/database/daos/stats_dao.dart';
import '../../../../core/database/daos/user_stats_dao.dart';

import '../widgets/mastery_pie_chart.dart';
import '../widgets/study_heatmap.dart';
import '../widgets/weekly_bar_chart.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final StatsDao _statsDao = StatsDao();
  // 逻辑处理
  // 逻辑处理
  // 逻辑处理
  
  bool _isLoading = true;
  MasteryDistribution? _masteryDistribution;
  List<DailyActivity> _monthlyActivity = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    GlobalStatsNotifier.instance.addListener(_loadData);
  }

  @override
  void dispose() {
    GlobalStatsNotifier.instance.removeListener(_loadData);
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // 逻辑处理
      // 逻辑处理
       // 逻辑处理
       final userStats = await UserStatsDao().getUserStats();
       String bookId = userStats.currentBookId.isNotEmpty ? userStats.currentBookId : 'waiyan_3_1';
      
      final mastery = await _statsDao.getMasteryDistribution(bookId);
      final activity = await _statsDao.getMonthlyActivity();
      
      if (mounted) {
        setState(() {
          _masteryDistribution = mastery;
          _monthlyActivity = activity;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading stats: $e");
      if (mounted) {
        setState(() {
          _isLoading = false; // 逻辑处理
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background, // 配色
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('学习分析', style: GoogleFonts.notoSans(fontWeight: FontWeight.w900, color: AppColors.textHighEmphasis)),
        centerTitle: true,
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 600) {
                  return _buildTabletLayout();
                }
                return _buildMobileLayout();
              },
            ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 逻辑处理
          if (_masteryDistribution != null)
             MasteryPieChart(
               key: ValueKey('pie_${_masteryDistribution!.hashCode}'),
               distribution: _masteryDistribution!
             )
                .animate()
                .fadeIn(duration: 600.ms)
                .scale(
                  begin: const Offset(0.7, 0.7), 
                  curve: Curves.elasticOut, 
                  duration: 1000.ms
                )
                .rotate(begin: -0.1, end: 0, curve: Curves.easeOutBack),
          
          const SizedBox(height: 20),
          
          // 逻辑处理
          WeeklyBarChart(
            key: ValueKey('bar_${_monthlyActivity.length}'),
            weeklyActivity: _monthlyActivity
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 200.ms)
              .slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
          
          const SizedBox(height: 20),
          
          // 逻辑处理
          StudyHeatMap(
            key: ValueKey('heatmap_${_monthlyActivity.length}'),
            activity: _monthlyActivity
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 400.ms)
              .scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOutBack)
              .slideY(begin: 0.15, end: 0, curve: Curves.easeOutBack),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 逻辑处理
          Expanded(
            flex: 4,
            child: Column(
              children: [
                if (_masteryDistribution != null)
                   MasteryPieChart(
                     key: ValueKey('pie_tab_${_masteryDistribution!.hashCode}'),
                     distribution: _masteryDistribution!
                   )
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .scale(
                        begin: const Offset(0.7, 0.7), 
                        curve: Curves.elasticOut, 
                        duration: 1000.ms
                      )
                      .rotate(begin: -0.1, end: 0, curve: Curves.easeOutBack),
              ],
            ),
          ),
          
          const SizedBox(width: 32),
          
          // 逻辑处理
          Expanded(
            flex: 6,
            child: Column(
              children: [
                WeeklyBarChart(
                  key: ValueKey('bar_tab_${_monthlyActivity.length}'),
                  weeklyActivity: _monthlyActivity
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 200.ms)
                    .slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
                
                const SizedBox(height: 24),
                
                StudyHeatMap(
                  key: ValueKey('heatmap_tab_${_monthlyActivity.length}'),
                  activity: _monthlyActivity
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 400.ms)
                    .scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOutBack)
                    .slideY(begin: 0.15, end: 0, curve: Curves.easeOutBack),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
