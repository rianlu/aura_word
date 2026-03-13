import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../features/home/presentation/screens/home_dashboard_screen.dart';
import '../../../../features/dictionary/presentation/screens/dictionary_screen.dart';
import 'package:aura_word/features/statistics/presentation/screens/statistics_screen.dart';
import '../../../../features/mine/presentation/screens/mine_screen.dart';
import '../../../../core/widgets/animated_indexed_stack.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  List<Widget> get _screens => [
    const HomeDashboardScreen(),
    const DictionaryScreen(),
    const StatisticsScreen(),
    const MineScreen(),
  ];

  final List<_NavigationItem> _navItems = [
    const _NavigationItem(
      icon: Icons.auto_stories,
      label: '学习',
    ),
    const _NavigationItem(
      icon: Icons.menu_book,
      label: '词典',
    ),
    const _NavigationItem(
      icon: Icons.bar_chart,
      label: '分析',
    ),
    const _NavigationItem(
      icon: Icons.person,
      label: '我的',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    // 桌面或大屏使用侧边导航栏
    final isWideScreen = width >= 840 || (width >= 600 && width >= height);

    return Scaffold(
      body: Row(
        children: [
          if (isWideScreen)
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              labelType: NavigationRailLabelType.all,
              selectedLabelTextStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 0.5,
                color: AppColors.primary,
              ),
              unselectedLabelTextStyle: const TextStyle(
                 fontWeight: FontWeight.w900,
                 fontSize: 12,
                 letterSpacing: 0.5,
                 color: AppColors.textMediumEmphasis,
              ),
              destinations: _navItems.map((item) => NavigationRailDestination(
                icon: Icon(item.icon),
                label: Text(item.label),
              )).toList(),
            ),
          if (isWideScreen)
            const VerticalDivider(thickness: 1, width: 1),
          
          Expanded(
            child: AnimatedIndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWideScreen
          ? null
          : Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey, width: 0.2)),
                boxShadow: [
                   BoxShadow(
                     color: Colors.black12,
                     offset: Offset(0, -4),
                     blurRadius: 16,
                   )
                ]
              ),
              child: BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: AppColors.primary,
                unselectedItemColor: AppColors.textMediumEmphasis,
                selectedLabelStyle: const TextStyle(
                   fontWeight: FontWeight.w900, 
                   fontSize: 10, 
                   letterSpacing: 0.5
                ),
                unselectedLabelStyle: const TextStyle(
                   fontWeight: FontWeight.w900, 
                   fontSize: 10, 
                   letterSpacing: 0.5
                ),
                items: _navItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final isSelected = _currentIndex == index;
                  
                  return BottomNavigationBarItem(
                    icon: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      transform: isSelected
                          ? (Matrix4.identity()
                            ..translate(0.0, -4.0) // 向上漂浮 4 像素
                            ..scale(1.15))
                          : Matrix4.identity(),
                      child: Icon(item.icon)
                        .animate(target: isSelected ? 1 : 0)
                        .scale(
                          begin: const Offset(1, 1),
                          end: const Offset(1.1, 1.1),
                          curve: Curves.elasticOut,
                          duration: 500.ms,
                        ),
                    ),
                    label: item.label,
                  );
                }).toList(),
              ),
            ),
    );
  }
}

class _NavigationItem {
  final IconData icon;
  final String label;

  const _NavigationItem({required this.icon, required this.label});
}
