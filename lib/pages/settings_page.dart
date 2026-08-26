import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/comment_filter_service.dart';
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
  final _commentFilter = CommentFilterService.instance;

  bool _autoCheck = true;
  bool _checking = false;
  bool _fontChanging = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _api.addLoginListener(_refresh);
    _theme.addListener(_refresh);
    _commentFilter.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _api.removeLoginListener(_refresh);
    _theme.removeListener(_refresh);
    _commentFilter.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await _commentFilter.load();
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

  Future<void> _editFilterKeywords() async {
    final controller = TextEditingController(
      text: _commentFilter.keywords.join('\n'),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('评论过滤关键词'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 5,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: '每行一个关键词\n也支持逗号或分号分隔',
              helperText: _commentFilter.keywordContainsEnabled
                  ? '模糊过滤：内容中包含任一关键词即隐藏'
                  : '精确过滤：整条内容与关键词一致才隐藏',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await _commentFilter.setKeywordsFromText(controller.text);
    }
    controller.dispose();
  }

  Future<void> _editMaxMatchedContentLength() async {
    final controller = TextEditingController(
      text: '${_commentFilter.maxMatchedContentLength}',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置关键词过滤长度上限'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '最大内容字数',
            helperText: '可设置 1–500，超过此长度的内容将被保留',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text);
              if (parsed == null || parsed < 1 || parsed > 500) return;
              Navigator.pop(context, parsed);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) {
      await _commentFilter.setMaxMatchedContentLength(value);
    }
  }

  Future<void> _pickCustomFont() async {
    if (_fontChanging) return;
    setState(() => _fontChanging = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('无法读取字体文件');
      }
      await _theme.installCustomFont(bytes, file.name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已应用字体：${file.name}')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('字体导入失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _fontChanging = false);
    }
  }

  Future<void> _resetCustomFont() async {
    if (_fontChanging) return;
    setState(() => _fontChanging = true);
    try {
      await _theme.clearCustomFont();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已恢复系统字体')),
        );
      }
    } finally {
      if (mounted) setState(() => _fontChanging = false);
    }
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
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.font_download_outlined),
                      title: const Text('自定义字体'),
                      subtitle: Text(
                        _theme.hasCustomFont
                            ? _theme.customFontName ?? '已应用自定义字体'
                            : '从本地选择 TTF 或 OTF 字体',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _fontChanging
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : _theme.hasCustomFont
                              ? TextButton(
                                  onPressed: _resetCustomFont,
                                  child: const Text('恢复'),
                                )
                              : const Icon(Icons.chevron_right_rounded),
                      onTap: _fontChanging ? null : _pickCustomFont,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _SectionTitle('内容过滤'),
                const SizedBox(height: 6),
                _Group(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.filter_alt_outlined),
                      title: const Text('过滤关键词'),
                      subtitle: Text(
                        _commentFilter.hasKeywords
                            ? '已设置 ${_commentFilter.keywords.length} 个关键词 · '
                                '${_commentFilter.fuzzyMatchingEnabled ? '模糊过滤' : '精确过滤'}'
                            : '尚未设置关键词',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _editFilterKeywords,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.manage_search_rounded),
                      title: const Text('关键词匹配方式'),
                      subtitle: Text(
                        _commentFilter.fuzzyMatchingEnabled
                            ? '模糊匹配：内容中包含任一关键词即过滤'
                            : '精确匹配：整条内容与关键词一致才过滤',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: false,
                              icon: Icon(Icons.filter_alt_outlined),
                              label: Text('精确匹配'),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              icon: Icon(Icons.saved_search_rounded),
                              label: Text('模糊匹配'),
                            ),
                          ],
                          selected: {_commentFilter.fuzzyMatchingEnabled},
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) {
                            _commentFilter.setFuzzyMatchingEnabled(
                              selection.first,
                            );
                          },
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.shield_outlined),
                      title: const Text('关键词过滤最大长度'),
                      subtitle: Text(
                        '超过 ${_commentFilter.maxMatchedContentLength} 字的内容'
                        '即使命中关键词也不会隐藏',
                      ),
                      value: _commentFilter.matchLengthLimitEnabled,
                      onChanged: _commentFilter.setMatchLengthLimitEnabled,
                    ),
                    if (_commentFilter.matchLengthLimitEnabled) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const SizedBox(width: 24),
                        title: const Text('最大匹配内容长度'),
                        subtitle: const Text('点击修改，可设置 1–500'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('≤ ${_commentFilter.maxMatchedContentLength}'),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                        onTap: _editMaxMatchedContentLength,
                      ),
                    ],
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.forum_outlined),
                      title: const Text('评论区过滤'),
                      subtitle: const Text('在评论区应用关键词过滤规则'),
                      value: _commentFilter.commentsEnabled,
                      onChanged: _commentFilter.setCommentsEnabled,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_off_outlined),
                      title: const Text('回复通知过滤'),
                      subtitle: const Text('将过滤规则同步应用到回复提醒'),
                      value: _commentFilter.noticesEnabled,
                      onChanged: _commentFilter.setNoticesEnabled,
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
