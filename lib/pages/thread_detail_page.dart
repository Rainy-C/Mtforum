/// 兼容入口。
///
/// 帖子详情页已经迁移到 `lib/features/thread/thread_detail_page.dart`，
/// 并按控制器 / 状态 / 部件拆分。这里保留原路径的转发，避免一次性修改
/// 全项目几十处 `import '../pages/thread_detail_page.dart'`。
export '../features/thread/thread_detail_page.dart';
