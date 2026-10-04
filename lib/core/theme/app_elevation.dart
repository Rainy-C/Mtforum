/// 高度体系。MD3 用"色阶 + 描边"表达层级，而不是阴影。
///
/// 因此绝大多数容器使用 [flat]，仅在浮层（FAB、菜单）使用轻阴影。
abstract final class AppElevation {
  /// 0 —— 卡片、列表、AppBar（用 surfaceContainer 色阶区分层级）
  static const double flat = 0;

  /// 1 —— 顶部导航滚动后
  static const double raised = 1;

  /// 3 —— FAB、PopupMenu
  static const double overlay = 3;
}
