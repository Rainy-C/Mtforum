import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/app_state_view.dart';

class RenamePage extends StatefulWidget {
  const RenamePage({super.key});

  @override
  State<RenamePage> createState() => _RenamePageState();
}

class _RenamePageState extends State<RenamePage> {
  final _api = ApiService.instance;

  RenameStatusData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _api.getRenameStatus();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = '改名状态加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('改名'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _data == null
          ? const AppStateView.loading()
          : _error != null && _data == null
              ? AppStateView.error(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
                    children: [
                      _RenameHero(data: _data ?? const RenameStatusData()),
                      const SizedBox(height: 14),
                      const _InfoCard(),
                    ],
                  ),
                ),
    );
  }
}

class _RenameHero extends StatelessWidget {
  final RenameStatusData data;

  const _RenameHero({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final insufficient = data.insufficientGold;
    final hasForm = data.hasRenameForm && !insufficient;
    final icon = insufficient
        ? Icons.savings_outlined
        : hasForm
            ? Icons.check_circle_outline_rounded
            : Icons.drive_file_rename_outline_rounded;
    final accent = insufficient
        ? colors.error
        : hasForm
            ? colors.primary
            : colors.tertiary;
    final container = insufficient
        ? colors.errorContainer
        : hasForm
            ? colors.primaryContainer
            : colors.tertiaryContainer;
    final onContainer = insufficient
        ? colors.onErrorContainer
        : hasForm
            ? colors.onPrimaryContainer
            : colors.onTertiaryContainer;

    final cost = data.costGold ?? 200;
    final title = insufficient
        ? '金币余额不足'
        : hasForm
            ? '已满足页面条件'
            : '改名状态';
    final message = data.message.isNotEmpty
        ? data.message
        : '每次改名需要消耗 $cost 金币。';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: container,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: onContainer, size: 28),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '论坛改名插件 · nimba_rename',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: container.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  Icon(Icons.monetization_on_outlined, color: accent),
                  const SizedBox(width: 9),
                  Text(
                    '$cost 金币 / 次',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
            if (insufficient) ...[
              const SizedBox(height: 12),
              Text(
                '余额不足时论坛不会返回改名输入表单，因此 App 不会显示无效的用户名输入框。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.outline,
                  height: 1.45,
                ),
              ),
            ] else if (hasForm) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 20,
                      color: colors.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '已经检测到真实改名表单，但提交字段尚未完成抓包验证。为避免错误提交或扣除金币，当前版本不会猜测字段名。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSecondaryContainer,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  '说明',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '改名状态直接读取论坛 plugin.php?id=nimba_rename 页面。当前已确认每次改名消耗 200 金币；只有论坛真实返回表单后，才会继续适配提交操作。',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: colors.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
