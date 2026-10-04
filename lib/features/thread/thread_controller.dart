import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import 'thread_state.dart';

/// 帖子详情页控制器。
///
/// 负责数据加载、分页、去重、定位楼层的取回，**不持有任何 BuildContext**，
/// 不弹 SnackBar、不导航。页面只监听 [state] 的变化。
///
/// 设计要点（性能相关）：
/// - 同一时刻只允许一次首屏请求（[_loadingGuard]），避免重复请求；
/// - 分页按 `pid` 去重累加，重复页不产生新列表项；
/// - 只有真正发生变化时才 [notifyListeners]，避免无意义重建。
class ThreadDetailController extends ChangeNotifier {
  ThreadDetailController({
    required this.tid,
    this.targetPid,
    this.targetUrl,
    ApiService? api,
  }) : _api = api ?? ApiService.instance;

  final ApiService _api;

  /// 主题 id
  final String tid;

  /// 需要定位的楼层 pid（从外部分享链接进入时使用）
  final String? targetPid;

  /// 定位楼层所在的原始 URL（区分"某页的某个 pid"）
  final String? targetUrl;

  ThreadDetailState _state = ThreadDetailState.initial;

  /// 当前状态快照
  ThreadDetailState get state => _state;

  /// 首屏加载完成、需要被定位的楼层数据（页面据此自动打开评论区）
  ThreadDetail? locatedDetail;

  bool _disposed = false;
  bool _targetCommentsOpened = false;

  bool get targetCommentsOpened => _targetCommentsOpened;

  void markTargetCommentsOpened() => _targetCommentsOpened = true;

  bool get _hasTarget =>
      (targetPid?.trim().isNotEmpty ?? false) &&
      (targetUrl?.trim().isNotEmpty ?? false);

  void _emit(ThreadDetailState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  /// 首屏加载（也可用于"重新加载"）。
  Future<void> load() async {
    if (_state.loading) return;
    _emit(_state.copyWith(loading: true, error: null));

    try {
      late final ThreadDetail detail;
      ThreadDetail? located;
      if (_hasTarget) {
        final results = await Future.wait<ThreadDetail>([
          _api.getThreadDetail(tid, page: 1),
          _api.getThreadDetailAtPost(
            tid: tid,
            pid: targetPid!.trim(),
            targetUrl: targetUrl!.trim(),
          ),
        ]);
        detail = results.first;
        located = results.last;
      } else {
        detail = await _api.getThreadDetail(tid, page: 1);
      }

      locatedDetail = located;
      _emit(
        ThreadDetailState(
          detail: detail,
          loading: false,
          hasMore: detail.posts.isNotEmpty,
          page: 1,
        ),
      );
    } catch (e) {
      final message = e is StateError ? e.message : '加载失败：$e';
      _emit(_state.copyWith(loading: false, error: message));
    }
  }

  /// 加载下一页（按 pid 去重）。
  Future<void> loadMore() async {
    final current = _state;
    final detail = current.detail;
    if (current.loadingMore || !current.hasMore || detail == null) return;

    _emit(current.copyWith(loadingMore: true));
    try {
      final nextPage = current.page + 1;
      final next = await _api.getThreadDetail(tid, page: nextPage);
      final existing = detail.posts.map((e) => e.pid).toSet();
      final additions =
          next.posts.where((e) => !existing.contains(e.pid)).toList();

      if (additions.isEmpty) {
        _emit(_state.copyWith(loadingMore: false, hasMore: false));
        return;
      }
      detail.posts.addAll(additions);
      _emit(_state.copyWith(loadingMore: false, page: nextPage));
    } catch (_) {
      // 下一页失败不破坏当前内容，只解除 loading 态。
      _emit(_state.copyWith(loadingMore: false));
    }
  }

  /// 就地刷新第一页（保留滚动位置由页面负责）。
  Future<void> refreshFirstPage() async {
    try {
      final refreshed = await _api.getThreadDetail(tid, page: 1);
      final detail = _state.detail;
      if (detail == null) return;
      detail.posts
        ..clear()
        ..addAll(refreshed.posts);
      _emit(_state.copyWith(page: 1, hasMore: refreshed.posts.isNotEmpty));
    } catch (_) {
      // 刷新失败保持原内容。
    }
  }

  /// 就地刷新"被定位楼层"所在的页（外部分享链接进入时使用）。
  Future<void> refreshLocatedPage(ThreadDetail detail) async {
    final pid = targetPid?.trim() ?? '';
    final url = targetUrl?.trim() ?? '';
    if (pid.isEmpty || url.isEmpty) return;
    try {
      final refreshed = await _api.getThreadDetailAtPost(
        tid: tid,
        pid: pid,
        targetUrl: url,
      );
      detail.posts
        ..clear()
        ..addAll(refreshed.posts);
      _emit(_state);
    } catch (_) {
      // 忽略：保持当前内容。
    }
  }

  /// 是否允许编辑某楼层（本人且已登录）。
  bool canEdit(Post post) {
    final detail = _state.detail;
    if (detail == null || !_api.isLoggedIn) return false;
    final uid = detail.currentUid.trim();
    return uid.isNotEmpty && uid != '0' && post.authorUid == uid;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
