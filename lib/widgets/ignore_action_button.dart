import 'package:flutter/material.dart';

/// 统一用于好友申请、打招呼和通知卡片的低强调“忽略”操作。
class IgnoreActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;

  const IgnoreActionButton({
    super.key,
    required this.onPressed,
    this.icon = Icons.visibility_off_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: colors.onSurfaceVariant,
        disabledForegroundColor: colors.outline.withValues(alpha: 0.55),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        minimumSize: const Size(0, 36),
        visualDensity: VisualDensity.compact,
        shape: const StadiumBorder(),
      ),
      icon: Icon(icon, size: 16),
      label: const Text('忽略'),
    );
  }
}
