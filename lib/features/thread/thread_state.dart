import '../../models/models.dart';

/// 帖子详情页的**只读**状态快照。
///
/// 页面只依赖这个不可变对象渲染，业务状态的变更全部由
/// `ThreadDetailController` 统一触发，避免"一个字段一次 setState"导致的
/// 整页重建。
class ThreadDetailState {
  const ThreadDetailState({
    this.detail,
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
    this.page = 1,
  });

  /// 初始状态
  static const ThreadDetailState initial = ThreadDetailState();

  /// 当前帖子数据（含全部已加载楼层）。
  final ThreadDetail? detail;

  /// 首屏加载中
  final bool loading;

  /// 加载下一页中
  final bool loadingMore;

  /// 是否还有下一页
  final bool hasMore;

  /// 首屏错误信息（加载下一页失败不写入这里，避免打断已有内容）
  final String? error;

  /// 已加载到第几页
  final int page;

  /// 首屏骨架：正在加载且还没有任何数据
  bool get isFirstLoading => loading && detail == null;

  /// 首屏失败：有错误且还没有任何数据
  bool get isFirstError => error != null && detail == null;

  /// 解析成功但没有任何楼层
  bool get isEmpty => detail != null && detail!.posts.isEmpty;

  /// 是否已经拿到可渲染的内容
  bool get hasContent => detail != null && detail!.posts.isNotEmpty;

  ThreadDetailState copyWith({
    ThreadDetail? detail,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    int? page,
    Object? error = _unset,
  }) {
    return ThreadDetailState(
      detail: detail ?? this.detail,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

/// copyWith 用的哨兵：区分"没传"与"显式置 null"。
const Object _unset = Object();
