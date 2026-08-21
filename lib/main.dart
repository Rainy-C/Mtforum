import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/community_page.dart';
import 'pages/profile_page.dart';
import 'pages/search_page.dart';
import 'services/api_service.dart';
import 'services/theme_service.dart';
import 'services/sign_service.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    ApiService.instance.init(),
    ThemeService.instance.init(),
  ]);
  runApp(const MTForumApp());
}

class MTForumApp extends StatelessWidget {
  const MTForumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'MT论坛',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeService.instance.mode,
          home: const MainPage(),
        );
      },
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  bool _autoSignRunning = false;

  final _pages = const [
    HomePage(),
    CommunityPage(),
    SearchPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    ApiService.instance.addLoginListener(_onLoginChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupTasks());
  }

  @override
  void dispose() {
    ApiService.instance.removeLoginListener(_onLoginChanged);
    super.dispose();
  }

  void _onLoginChanged() {
    if (ApiService.instance.isLoggedIn) {
      _runAutoSign();
    }
  }

  Future<void> _runStartupTasks() async {
    await _runAutoSign();
    await _checkUpdate();
  }

  Future<void> _runAutoSign() async {
    if (_autoSignRunning) {
      return;
    }

    _autoSignRunning = true;
    try {
      final result = await SignService.instance.runStartupAutoSign();
      if (!mounted || !result.attempted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? '自动签到：${result.message}'
                : result.message,
          ),
        ),
      );
    } finally {
      _autoSignRunning = false;
    }
  }

  Future<void> _checkUpdate() async {
    try {
      final updates = UpdateService.instance;
      if (!await updates.getStartupCheckEnabled()) return;
      final result = await updates.check();
      if (!mounted || !result.hasUpdate) return;
      await showUpdateDialog(context, result);
    } catch (_) {
      // 自动检查更新失败时保持静默，不阻塞应用启动。
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: '社区',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search_rounded),
            label: '搜索',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
