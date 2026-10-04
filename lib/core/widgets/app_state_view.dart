import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// 全局统一的加载 / 空状态 / 错误状态。
///
/// 所有页面共用这一份实现，禁止各页再写 `Center(child: CircularProgressIndicator())`
/// 或自绘"加载失败 + 重试"。视觉参数全部来自主题 token。
class AppStateView extends StatelessWidget {
  final IconData? icon;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final bool loading;
  final EdgeInsetsGeometry padding;

  const AppStateView._({
    super.key,
    this.icon,
    this.title,
    this.message,
    this.onRetry,
    this.loading = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.xxl,
      vertical: AppSpacing.xxxl,
    ),
  });

  /// 加载中
  const AppStateView.loading({Key? key})
      : this._(key: key, loading: true);

  /// 空状态
  const AppStateView.empty({
    Key? key,
    required IconData icon,
    required String title,
    String? message,
  }) : this._(key: key, icon: icon, title: title, message: message);

  /// 错误状态（可带重试）
  const AppStateView.error({
    Key? key,
    required String message,
    VoidCallback? onRetry,
  }) : this._(
          key: key,
          icon: Icons.cloud_off_outlined,
          title: '加载失败',
          message: message,
          onRetry: onRetry,
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (loading) {
      return Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: colors.primary,
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: AppRadius.lg,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colors.onSurfaceVariant, size: 26),
            ),
            if (title != null) ...[
              AppSpacing.sm.vGap,
              Text(
                title!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ],
            if (message?.isNotEmpty == true) ...[
              AppSpacing.xxs.vGap,
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (onRetry != null) ...[
              AppSpacing.md.vGap,
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
