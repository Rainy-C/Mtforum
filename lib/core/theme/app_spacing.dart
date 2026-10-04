import 'package:flutter/widgets.dart';

/// 全局间距体系（4dp 基准）。
///
/// 页面只使用这里的常量，避免 `SizedBox(height: 13)` 这类魔法数字，
/// 保证纵向节奏在所有页面完全一致。
abstract final class AppSpacing {
  /// 2dp —— 图标与角标之间的微调
  static const double xxxs = 2;

  /// 4dp —— 紧凑行内间距
  static const double xxs = 4;

  /// 8dp —— 图标与文字、Chip 之间
  static const double xs = 8;

  /// 12dp —— 卡片内部元素间距
  static const double sm = 12;

  /// 16dp —— 页面横向边距、卡片内部主间距
  static const double md = 16;

  /// 20dp —— 卡片之间
  static const double lg = 20;

  /// 24dp —— 区块之间
  static const double xl = 24;

  /// 32dp —— 大区块 / 空态
  static const double xxl = 32;

  /// 48dp —— 页面级留白
  static const double xxxl = 48;

  /// 页面统一横向内边距
  static const EdgeInsets horizontalPage = EdgeInsets.symmetric(horizontal: md);

  /// 列表统一内边距
  static const EdgeInsets listPage = EdgeInsets.fromLTRB(md, xs, md, xl);

  /// 卡片内部统一内边距
  static const EdgeInsets card = EdgeInsets.all(md);

  /// 底部安全区 + 统一间距
  static EdgeInsets bottomSafe(BuildContext context, {double extra = 0}) =>
      EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom + extra);
}

extension AppSpacingX on num {
  /// 快捷生成纵向间距
  SizedBox get vGap => SizedBox(height: toDouble());

  /// 快捷生成横向间距
  SizedBox get hGap => SizedBox(width: toDouble());
}
