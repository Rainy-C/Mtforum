import 'package:flutter/material.dart';

/// 统一对话框。
///
/// 之前每个页面各自 `showDialog` + 手写 AlertDialog 结构，按钮顺序、圆角、
/// 取消语义都不一致。这里收敛为两个入口，其余场景直接用 [showDialog]。
abstract final class AppDialogs {
  /// 二次确认（危险操作使用 [destructive] = true）。
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    String confirmText = '确定',
    String cancelText = '取消',
    bool destructive = false,
  }) async {
    final colors = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: destructive
            ? Icon(Icons.warning_amber_rounded, color: colors.error)
            : null,
        title: Text(title),
        content: message == null
            ? null
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(message),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(cancelText),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 单输入框编辑（返回 null 表示取消）。
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    String? message,
    String? initialValue,
    String hintText = '',
    String confirmText = '保存',
    bool multiline = false,
  }) async {
    final controller = TextEditingController(text: initialValue ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null) ...[
                Text(message),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                minLines: multiline ? 3 : 1,
                maxLines: multiline ? 8 : 1,
                decoration: InputDecoration(hintText: hintText),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  /// 轻量信息提示。
  static Future<void> info(
    BuildContext context, {
    required String title,
    String? message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: message == null
            ? null
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(message),
              ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
