import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/theme_service.dart';
import '../services/update_service.dart';
import 'login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _api = ApiService.instance;
  final _theme = ThemeService.instance;
  final _updates = UpdateService.instance;

  bool _autoCheck = true;
  bool _checking = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _api.addLoginListener(_refresh);
    _theme.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _api.removeLoginListener(_refresh);
    _theme.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final auto = await _updates.getStartupCheckEnabled();
    String version = '';
    try {
      final info = await _updates.getCurrentVersionInfo();
      version = '${info['versionName'] ?? ''} (${info['versionCode'] ?? ''})';
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _autoCheck = auto;
      _version = version;
    });
  }

  Future<void> _login() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (result == true && mounted) setState(() {});
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出登录')),
    );
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final result = await _updates.check();
      if (!mounted) return;
      if (result.hasUpdate) {
        await showUpdateDialog(context, result);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已是最新版本 v${result.currentVersion}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('检查更新失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(title: Text('设置'), pinned: true),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const _SectionTitle('账号'),
                const SizedBox(height: 6),
                _Group(
                  children: [
                    ListTile(
                      leading: Icon(
                        _api.isLoggedIn
                            ? Icons.verified_user_rounded
                            : Icons.login_rounded,
                      ),
                      title: Text(_api.isLoggedIn ? '已登录' : '登录论坛'),
                      subtitle: Text(
                        _api.isLoggedIn
                            ? '论坛登录状态正常'
                            : '使用论坛账号和密码登录',
                      ),
                      trailing: _api.isLoggedIn
                          ? null
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: _api.isLoggedIn ? null : _login,
                    ),
                    if (_api.isLoggedIn) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          Icons.logout_rounded,
                          color: colors.error,
                        ),
                        title: Text(
                          '退出登录',
                          style: TextStyle(color: colors.error),
                        ),
                        onTap: _logout,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                const _SectionTitle('外观'),
                const SizedBox(height: 6),
                _Group(
                  children: [
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.system,
                      groupValue: _theme.mode,
                      onChanged: (value) {
                        if (value != null) _theme.setMode(value);
                      },
                      title: const Text('跟随系统'),
                      secondary: const Icon(Icons.brightness_auto_rounded),
                    ),
                    const Divider(height: 1),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.light,
                      groupValue: _theme.mode,
                      onChanged: (value) {
                        if (value != null) _theme.setMode(value);
                      },
                      title: const Text('浅色模式'),
                      secondary: const Icon(Icons.light_mode_rounded),
                    ),
                    const Divider(height: 1),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.dark,
                      groupValue: _theme.mode,
                      onChanged: (value) {
                        if (value != null) _theme.setMode(value);
                      },
                      title: const Text('深色模式'),
                      secondary: const Icon(Icons.dark_mode_rounded),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.text_fields_rounded),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Text(
                                  '文字大小',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(
                                '${(_theme.textScale * 100).round()}%',
                                style: TextStyle(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 4),
                              TextButton(
                                onPressed: (_theme.textScale - 1.0).abs() < 0.001
                                    ? null
                                    : _theme.resetTextScale,
                                child: const Text('默认'),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 38, right: 2),
                            child: Slider(
                              value: _theme.textScale,
                              min: 0.85,
                              max: 1.25,
                              divisions: 8,
                              label: '${(_theme.textScale * 100).round()}%',
                              onChanged: _theme.setTextScale,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 54, right: 8),
                            child: Text(
                              '预览文字 · 根据阅读习惯调整全局字号',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _SectionTitle('更新'),
                const SizedBox(height: 6),
                _Group(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.update_rounded),
                      title: const Text('启动时检查更新'),
                      subtitle: const Text('打开应用后自动检测新版本'),
                      value: _autoCheck,
                      onChanged: (value) async {
                        setState(() => _autoCheck = value);
                        await _updates.setStartupCheckEnabled(value);
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _checking
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.system_update_alt_rounded),
                      title: const Text('检查更新'),
                      subtitle: Text(
                        _version.isEmpty ? '读取版本中…' : '当前版本 $_version',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _checking ? null : _checkUpdate,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _SectionTitle('关于'),
                const SizedBox(height: 6),
                _Group(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded),
                      title: const Text('MT论坛'),
                      subtitle: Text(
                        _version.isEmpty
                            ? '第三方 Flutter 客户端'
                            : '版本 $_version',
                      ),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
