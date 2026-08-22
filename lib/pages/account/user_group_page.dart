import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/app_state_view.dart';

class UserGroupPage extends StatefulWidget {
  const UserGroupPage({super.key});

  @override
  State<UserGroupPage> createState() => _UserGroupPageState();
}

class _UserGroupPageState extends State<UserGroupPage> {
  final _api = ApiService.instance;

  UserGroupData? _data;
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
      final data = await _api.getUserGroupData();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('用户组'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _data == null) {
      return const AppStateView.loading();
    }

    if (_error != null && _data == null) {
      return AppStateView.error(message: _error!, onRetry: _load);
    }

    final data = _data;
    if (data == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          _LevelCard(data: data),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '当前权限',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          if (data.permissions.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: Text('暂无权限信息')),
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < data.permissions.length; i++) ...[
                    _PermissionRow(permission: data.permissions[i]),
                    if (i != data.permissions.length - 1)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                ],
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  final UserGroupData data;

  const _LevelCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final progress = data.progress.clamp(0.0, 1.0).toDouble();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.groupName.isEmpty ? '当前用户组' : data.groupName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (data.currentLevel.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            data.currentLevel,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  data.currentLevel.isEmpty ? '当前' : data.currentLevel,
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: colors.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  data.nextLevel.isEmpty ? '下一等级' : data.nextLevel,
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Text(
                  '${(progress * 100).round()}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (data.pointsNeeded.isNotEmpty ||
                    data.nextGroupName.isNotEmpty)
                  Flexible(
                    child: Text(
                      _upgradeText(data),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _upgradeText(UserGroupData data) {
    final buffer = StringBuffer();
    if (data.pointsNeeded.isNotEmpty) {
      buffer.write('还需 ${data.pointsNeeded} 积分');
    }
    if (data.nextGroupName.isNotEmpty) {
      if (buffer.length > 0) buffer.write(' · ');
      buffer.write('升级到 ${data.nextGroupName}');
    }
    return buffer.toString();
  }
}

class _PermissionRow extends StatelessWidget {
  final UserGroupPermission permission;

  const _PermissionRow({required this.permission});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final allowed = permission.allowed;

    Widget value;
    if (allowed != null) {
      value = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            allowed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: allowed ? colors.primary : colors.outline,
          ),
          const SizedBox(width: 6),
          Text(
            permission.value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: allowed ? colors.primary : colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    } else {
      value = Text(
        permission.value,
        textAlign: TextAlign.end,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              permission.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(flex: 6, child: value),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 46,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
