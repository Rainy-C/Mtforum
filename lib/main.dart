import 'dart:async';

import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/community_page.dart';
import 'pages/messages_page.dart';
import 'pages/profile_page.dart';
import 'services/analytics_service.dart';
import 'services/api_service.dart';
import 'services/message_badge_service.dart';
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
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(
                  media.textScaler.scale(1.0) * ThemeService.instance.textScale,
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
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

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _autoSignRunning = false;

  final _pages = const [
    HomePage(),
    CommunityPage(),
    MessagesPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ApiService.instance.addLoginListener(_onLoginChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupTasks());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ApiService.instance.removeLoginListener(_onLoginChanged);
    super.dispose();
  }

  void _onLoginChanged() {
    if (ApiService.instance.isLoggedIn) {
      _runAutoSign();
      MessageBadgeService.instance.refresh(force: true);
    } else {
      MessageBadgeService.instance.clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MessageBadgeService.instance.refresh(force: true);
    }
  }

  Future<void> _runStartupTasks() async {
    // 匿名启动统计使用独立网络客户端，不携带论坛 Cookie，也不阻塞启动流程。
    unawaited(AnalyticsService.instance.reportLaunch());
    await _runAutoSign();
    await MessageBadgeService.instance.refresh(force: true);
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
      body: _AnimatedTabStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: MessageBadgeService.instance,
        builder: (context, _) {
          final messageBadge = MessageBadgeService.instance.summary.totalLabel;
          return NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              if (index == _currentIndex) return;
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() => _currentIndex = index);
              if (index == 2) {
                MessageBadgeService.instance.refresh(force: true);
              }
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: '首页',
              ),
              const NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: '社区',
              ),
              NavigationDestination(
                icon: _NavigationIconWithBadge(
                  icon: Icons.chat_bubble_outline_rounded,
                  badge: messageBadge,
                ),
                selectedIcon: _NavigationIconWithBadge(
                  icon: Icons.chat_bubble_rounded,
                  badge: messageBadge,
                ),
                label: '消息',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: '我的',
              ),
            ],
          );
        },
      ),
    );
  }
}


class _AnimatedTabStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _AnimatedTabStack({
    required this.index,
    required this.children,
  });

  @override
  State<_AnimatedTabStack> createState() => _AnimatedTabStackState();
}

class _AnimatedTabStackState extends State<_AnimatedTabStack>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 320);
  static const _curve = Cubic(0.16, 1.0, 0.30, 1.0);

  late final AnimationController _controller;
  late int _currentIndex;
  int? _previousIndex;
  int _direction = 1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: 1,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _previousIndex = null);
        }
      });
  }

  @override
  void didUpdateWidget(covariant _AnimatedTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == _currentIndex) return;

    _previousIndex = _currentIndex;
    _direction = widget.index > _currentIndex ? 1 : -1;
    _currentIndex = widget.index;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Z 轴顺序必须与切换方向无关：隐藏页在底层，旧页居中，
    // 新页永远放在最上层。旧实现直接按 tab 索引堆 Stack，导致
    // 0 -> 3 正常，但 3 -> 0 时旧的“我的”页仍压在“首页”上面，
    // 于是反向动画看起来像卡住/穿模。
    final hidden = <Widget>[];
    for (var i = 0; i < widget.children.length; i++) {
      if (i == _currentIndex || i == _previousIndex) continue;
      hidden.add(_buildPage(i, widget.children[i]));
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ...hidden,
          if (_previousIndex != null)
            _buildPage(_previousIndex!, widget.children[_previousIndex!]),
          _buildPage(_currentIndex, widget.children[_currentIndex]),
        ],
      ),
    );
  }

  Widget _buildPage(int index, Widget child) {
    final isCurrent = index == _currentIndex;
    final isPrevious = index == _previousIndex;
    final isVisible = isCurrent || isPrevious;

    // 每个 Tab 始终保持完全相同的 Widget 包装层，并通过稳定 key 识别。
    // Stack 为了保证动画 Z 轴会把 current / previous 移到末尾；如果隐藏态
    // 使用 Offstage、显示态改成 AnimatedBuilder，Flutter 会因为父节点类型变化
    // 销毁原来的 State。HomePage 被重新创建后 initState 会再次请求首页，表现为
    // “切回首页就自动刷新”。固定结构后只改变 offstage / translation，不再重建页面。
    final page = TickerMode(
      enabled: isVisible,
      child: ExcludeSemantics(
        excluding: !isCurrent,
        child: IgnorePointer(
          ignoring: !isCurrent || _controller.isAnimating,
          child: RepaintBoundary(child: child),
        ),
      ),
    );

    return KeyedSubtree(
      key: ValueKey<int>(index),
      child: Offstage(
        offstage: !isVisible,
        child: AnimatedBuilder(
          animation: _controller,
          child: page,
          builder: (context, page) {
            final t = _curve.transform(_controller.value);
            var x = 0.0;
            if (isVisible) {
              if (isCurrent) {
                x = _direction * (1 - t);
              } else if (isPrevious) {
                // 底层页只做极轻的反向视差，减少大面积像素移动。
                x = -_direction * 0.06 * t;
              }
            }

            return FractionalTranslation(
              translation: Offset(x, 0),
              child: page,
            );
          },
        ),
      ),
    );
  }
}


class _NavigationIconWithBadge extends StatelessWidget {
  final IconData icon;
  final String? badge;

  const _NavigationIconWithBadge({required this.icon, this.badge});

  @override
  Widget build(BuildContext context) {
    final value = badge;
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(icon),
          if (value != null)
            Positioned(
              right: -3,
              top: 3,
              child: _NavigationBadge(value: value),
            ),
        ],
      ),
    );
  }
}

class _NavigationBadge extends StatelessWidget {
  final String value;

  const _NavigationBadge({required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 18,
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: colors.error,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colors.surfaceContainerLow,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        value,
        textAlign: TextAlign.center,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
        style: TextStyle(
          color: colors.onError,
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w800,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    );
  }
}
