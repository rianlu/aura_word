import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/services/backup_service.dart';
import 'features/main/presentation/screens/main_navigation_screen.dart';
import 'features/practice/presentation/screens/word_selection_screen.dart';
import 'features/splash/presentation/screens/splash_screen.dart';

import 'features/practice/presentation/screens/spelling_practice_screen.dart';
import 'features/statistics/presentation/screens/statistics_screen.dart';

import 'core/database/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper().database;
  final prefs = await SharedPreferences.getInstance();
  final hasSeenSplash = prefs.getBool('seen_splash') ?? false;
  runApp(MyApp(showSplash: !hasSeenSplash));
}

class MyApp extends StatefulWidget {
  final bool showSplash;

  const MyApp({super.key, required this.showSplash});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const _channel = MethodChannel('com.aura.word/file_handler');
  static const _eventChannel = EventChannel('com.aura.word/file_handler/events');
  
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initFileHandler();
  }

  Future<void> _initFileHandler() async {
    // 监听应用运行中的文件分享
    _eventChannel.receiveBroadcastStream().listen((dynamic filePath) {
      if (filePath != null && filePath is String && filePath.isNotEmpty) {
        _handleSharedFile(filePath);
      }
    });

    // 检查是否通过文件分享启动应用
    try {
      final String? initialFile = await _channel.invokeMethod('getInitialSharedFile');
      if (initialFile != null && initialFile.isNotEmpty) {
        // 延迟以确保界面就绪
        await Future.delayed(const Duration(milliseconds: 800));
        _handleSharedFile(initialFile);
      }
    } catch (e) {
      debugPrint('Error getting initial shared file: $e');
    }
  }

  void _handleSharedFile(String filePath) {
    debugPrint('Received shared file: $filePath');
    
    // 校验文件扩展名
    if (!filePath.endsWith('.wcc') && !filePath.endsWith('.json')) {
      debugPrint('Invalid file type: $filePath');
      return;
    }

    // 获取当前上下文并导入
    final context = _navigatorKey.currentState?.overlay?.context;
    if (context != null) {
      BackupService().importDataFromFile(File(filePath), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: '灵听单词 (AuraWord)',
      theme: AppTheme.lightTheme,
      initialRoute: widget.showSplash ? SplashScreen.routeName : '/',
      routes: {
        SplashScreen.routeName: (context) => const SplashScreen(),
        '/': (context) => const MainNavigationScreen(),
        '/practice/selection': (context) => const WordSelectionScreen(),

        '/practice/spelling': (context) => const SpellingPracticeScreen(),
        '/statistics': (context) => const StatisticsScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
