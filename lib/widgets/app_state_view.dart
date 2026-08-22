import 'package:flutter/material.dart';

/// 全局统一的加载 / 空状态 / 错误状态。
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
    this.padding = const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
  });

  const AppStateView.loading({Key? key})
      : this._(key: key, loading: true);

  const AppStateView.empty({
    Key? key,
    required IconData icon,
    required String title,
    String? message,
  }) : this._(key: key, icon: icon, title: title, message: message);

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
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
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
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colors.onSurfaceVariant, size: 28),
            ),
            const SizedBox(height: 14),
            if (title != null)
              Text(
                title!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            if (message?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
