import 'package:flutter/animation.dart';

/// 全局动效体系。
///
/// 原则：短、快、自然、克制。禁止叠加缩放 + 旋转 + 淡入。
/// 页面切换只用横向位移（见 [AppTheme] 中的 PageTransitionsTheme）。
abstract final class AppMotion {
  /// 120ms —— 状态切换、图标变化
  static const Duration fast = Duration(milliseconds: 120);

  /// 200ms —— 常规进入/退出
  static const Duration medium = Duration(milliseconds: 200);

  /// 320ms —— 页面切换
  static const Duration slow = Duration(milliseconds: 320);

  /// 标准减速曲线（进入）
  static const Curve enter = Curves.easeOutCubic;

  /// 标准加速曲线（退出）
  static const Curve exit = Curves.easeInCubic;

  /// 强调减速，用于底部弹层
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);

  /// 页面切换时长
  static Duration get pageTransition => slow;
}
