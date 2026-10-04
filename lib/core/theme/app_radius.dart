import 'package:flutter/widgets.dart';

/// 全局圆角体系。MD3 强调"圆角与控件尺寸成正比"：
/// 小控件小圆角、卡片中圆角、底部弹层大圆角。
abstract final class AppRadius {
  /// 8dp —— 小标签、徽章
  static const double xsValue = 8;

  /// 12dp —— 按钮、输入框内元素
  static const double smValue = 12;

  /// 16dp —— 输入框、列表项
  static const double mdValue = 16;

  /// 20dp —— 卡片
  static const double lgValue = 20;

  /// 28dp —— 底部弹层 / 对话框
  static const double xlValue = 28;

  /// 胶囊
  static const double pillValue = 999;

  static const BorderRadius xs = BorderRadius.all(Radius.circular(xsValue));
  static const BorderRadius sm = BorderRadius.all(Radius.circular(smValue));
  static const BorderRadius md = BorderRadius.all(Radius.circular(mdValue));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(lgValue));
  static const BorderRadius xl = BorderRadius.all(Radius.circular(xlValue));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(pillValue));

  /// 底部弹层顶部圆角
  static const BorderRadius sheet =
      BorderRadius.vertical(top: Radius.circular(xlValue));
}
