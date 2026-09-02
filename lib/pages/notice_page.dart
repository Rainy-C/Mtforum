import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/comment_filter_service.dart';
import '../services/message_badge_service.dart';
import '../widgets/app_state_view.dart';
import 'account/user_group_page.dart';
import 'account/social_center_page.dart';
import 'account/poke_page.dart';
import '../routes/thread_routes.dart';

/// Discuz 论坛通知中心。
///
/// 真实入口：home.php?mod=space&do=notice&view=...&type=...&mobile=2
/// 「我的帖子」「坛友互动」存在二级 type，其余两个分类直接读取 view。
class NoticePage extends StatefulWidget {
  const NoticePage({super.key});

  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage>
    with SingleTickerProviderStateMixin {
  final _api = ApiService.instance;
  final _scrollController = ScrollController();
  final _commentFilter = CommentFilterService.instance;
  late final TabController _tabController;

  static const _sections = <_NoticeSection>[
    _NoticeSection(
      label: '我的帖子',
      view: 'mypost',
      icon: Icons.article_outlined,
      subtypes: [
        _NoticeSubtype('帖子', 'post'),
        _NoticeSubtype('点评', 'pcomment'),
        _NoticeSubtype('活动', 'activity'),
        _NoticeSubtype('悬赏', 'reward'),
        _NoticeSubtype('商品', 'goods'),
        _NoticeSubtype('@我', 'at'),
      ],
    ),
    _NoticeSection(
      label: '坛友互动',
      view: 'interactive',
      icon: Icons.people_alt_outlined,
      subtypes: [
        _NoticeSubtype('打招呼', 'poke'),
        _NoticeSubtype('好友', 'friend'),
        _NoticeSubtype('留言', 'wall'),
        _NoticeSubtype('评论', 'comment'),
        _NoticeSubtype('点击', 'click'),
        _NoticeSubtype('分享', 'sharenotice'),
      ],
    ),
    _NoticeSection(
      label: '系统提醒',
      view: 'system',
      icon: Icons.notifications_active_outlined,
    ),
    _NoticeSection(
      label: '应用提醒',
      view: 'app',
      icon: Icons.extension_outlined,
    ),
  ];

  int _sectionIndex = 0;
  String? _type = _sections.first.subtypes.first.type;
  List<NoticeItem> _items = const [];
  final Map<String, Post> _replyPreviews = {};
  final Set<String> _ignoredNoticeKeys = <String>{};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _showFilteredNotices = false;
  int _page = 1;
  int _totalPages = 1;
  int _generation = 0;
  String? _error;

  _NoticeSection get _section => _sections[_sectionIndex];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _sections.length, vsync: this);
    _tabController.addListener(_handleTabChange);
    _scrollController.addListener(_handleScroll);
    _commentFilter.addListener(_handleFilterChanged);
    _initialize();
  }

  @override
  void dispose() {
    _generation++;
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _commentFilter.removeListener(_handleFilterChanged);
    super.dispose();
  }

  Future<void> _initialize() async {
    await _commentFilter.load();
    await _loadIgnoredNoticeKeys();
    if (mounted) await _reload();
  }

  static const String _ignoredNoticePrefsKey = 'notice_ignored_keys_v1';

  Future<void> _loadIgnoredNoticeKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final saved =
        prefs.getStringList(_ignoredNoticePrefsKey) ?? const <String>[];
    _ignoredNoticeKeys
      ..clear()
      ..addAll(saved.where((key) => key.trim().isNotEmpty));
  }

  Future<void> _persistIgnoredNoticeKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = _ignoredNoticeKeys.toList(growable: false);
    final start = keys.length > 1200 ? keys.length - 1200 : 0;
    await prefs.setStringList(
      _ignoredNoticePrefsKey,
      keys.sublist(start),
    );
  }

  bool _isLocallyIgnored(NoticeItem item) =>
      _ignoredNoticeKeys.contains(_noticeKey(item));

  void _handleFilterChanged() {
    if (!mounted) return;
    setState(() {
      if (_filteredOutItems.isEmpty) _showFilteredNotices = false;
    });
    _scheduleAutoLoadNext();
  }

  bool _shouldHideNotice(
    NoticeItem item, {
    required String view,
    required String? type,
  }) {
    if (!_commentFilter.noticesEnabled || !_commentFilter.hasRules) {
      return false;
    }
    if (view != 'mypost' || type != 'post') return false;
    final post = _replyPreviews[item.pid];
    final preview = post == null ? '' : ApiService.buildPostPreview(post).trim();
    return preview.isNotEmpty && _commentFilter.matches(preview);
  }

  List<NoticeItem> get _filteredOutItems => _items
      .where((item) => !_isLocallyIgnored(item))
      .where(
        (item) => _shouldHideNotice(
          item,
          view: _section.view,
          type: _type,
        ),
      )
      .toList(growable: false);

  List<NoticeItem> get _visibleItems {
    if (_showFilteredNotices) return _filteredOutItems;
    return _items
        .where((item) => !_isLocallyIgnored(item))
        .where(
          (item) => !_shouldHideNotice(
            item,
            view: _section.view,
            type: _type,
          ),
        )
        .toList(growable: false);
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging ||
        _sectionIndex == _tabController.index) {
      return;
    }

    final next = _sections[_tabController.index];
    setState(() {
      _sectionIndex = _tabController.index;
      _type = next.subtypes.isEmpty ? null : next.subtypes.first.type;
      _showFilteredNotices = false;
    });
    _reload();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    if (_scrollController.position.extentAfter < 1000) {
      _loadMore();
    }
  }

  void _scheduleAutoLoadNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _loading ||
          _loadingMore ||
          !_hasMore ||
          !_scrollController.hasClients) {
        return;
      }
      // 首屏内容不足以产生滚动事件时也继续加载；列表较长时则在距底部
      // 1000px 内预取，避免用户看到明显的分页停顿。
      if (_scrollController.position.extentAfter < 1000) {
        unawaited(_loadMore());
      }
    });
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    final requestedView = _section.view;
    final requestedType = _type;

    if (!_api.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _replyPreviews.clear();
        _page = 1;
        _totalPages = 1;
        _hasMore = false;
        _loading = false;
        _loadingMore = false;
        _showFilteredNotices = false;
        _error = '请先登录后查看论坛通知';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _items = const [];
        _replyPreviews.clear();
        _page = 1;
        _totalPages = 1;
        _hasMore = false;
        _loading = true;
        _loadingMore = false;
        _showFilteredNotices = false;
        _error = null;
      });
    }

    try {
      final data = await _api.getNoticePage(
        view: requestedView,
        type: requestedType,
        page: 1,
      );
      if (!mounted ||
          generation != _generation ||
          _section.view != requestedView ||
          _type != requestedType) {
        return;
      }
      final visibleDataItems = data.items
          .where((item) => !_isLocallyIgnored(item))
          .toList(growable: false);
      setState(() {
        _items = visibleDataItems;
        _page = 1;
        _totalPages = data.totalPages;
        _hasMore = data.hasMore || _page < _totalPages;
      });
      unawaited(MessageBadgeService.instance.markNoticesSeen(data.items));
      if (requestedView == 'mypost' && requestedType == 'post') {
        unawaited(_loadReplyPreviews(visibleDataItems, generation));
      }
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '通知加载失败：$e');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
        _scheduleAutoLoadNext();
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;

    final generation = _generation;
    final requestedView = _section.view;
    final requestedType = _type;
    final nextPage = _page + 1;
    var loadSucceeded = false;

    setState(() => _loadingMore = true);
    try {
      final data = await _api.getNoticePage(
        view: requestedView,
        type: requestedType,
        page: nextPage,
      );
      if (!mounted ||
          generation != _generation ||
          _section.view != requestedView ||
          _type != requestedType) {
        return;
      }

      final pageItems = data.items
          .where((item) => !_isLocallyIgnored(item))
          .toList(growable: false);
      final merged = <NoticeItem>[..._items];
      final keys = merged.map(_noticeKey).toSet();
      var addedCount = 0;
      for (final item in pageItems) {
        if (keys.add(_noticeKey(item))) {
          merged.add(item);
          addedCount++;
        }
      }

      setState(() {
        _items = merged;
        _page = nextPage;
        if (data.totalPages > _totalPages) {
          _totalPages = data.totalPages;
        }
        _hasMore = nextPage < _totalPages ||
            (addedCount > 0 && data.hasMore);
      });
      unawaited(MessageBadgeService.instance.markNoticesSeen(data.items));
      if (requestedView == 'mypost' && requestedType == 'post') {
        unawaited(_loadReplyPreviews(pageItems, generation));
      }
      loadSucceeded = true;
    } catch (e) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下一页加载失败：$e')),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
        if (loadSucceeded) _scheduleAutoLoadNext();
      }
    }
  }

  Future<void> _loadReplyPreviews(
    Iterable<NoticeItem> items,
    int generation,
  ) async {
    final targets = items
        .where(
          (item) =>
              item.pid?.isNotEmpty == true &&
              item.tid?.isNotEmpty == true &&
              item.targetUrl?.isNotEmpty == true &&
              !_replyPreviews.containsKey(item.pid),
        )
        .toList(growable: false);
    final failed = <NoticeItem>[];
    // 限制并发，覆盖整页通知而不是只给前 10 条加载预览。
    for (var offset = 0; offset < targets.length; offset += 4) {
      final end = offset + 4 < targets.length ? offset + 4 : targets.length;
      await Future.wait(
        targets.sublist(offset, end).map((item) async {
          try {
            final preview = await _api.getNoticeReplyPreview(item);
            if (!mounted || generation != _generation || preview == null) {
              return;
            }
            setState(() => _replyPreviews[item.pid!] = preview);
          } catch (_) {
            failed.add(item);
          }
        }),
      );
      if (!mounted || generation != _generation) return;
      _scheduleAutoLoadNext();
    }
    // 网络瞬时失败的通知再串行补一次，避免一批请求失败后整组缺预览。
    for (final item in failed) {
      if (!mounted || generation != _generation) return;
      try {
        final preview = await _api.getNoticeReplyPreview(item);
        if (!mounted || generation != _generation || preview == null) continue;
        setState(() => _replyPreviews[item.pid!] = preview);
      } catch (_) {
        // 单条预览最终失败不影响通知列表和跳转。
      }
    }
    _scheduleAutoLoadNext();
  }

  String _noticeKey(NoticeItem item) {
    if (item.id.isNotEmpty) return 'id:${item.id}';
    return '${item.type}|${item.authorUid}|${item.time}|${item.content}|${item.pid ?? ''}';
  }

  void _selectSubtype(String type) {
    if (_type == type) return;
    setState(() {
      _type = type;
      _showFilteredNotices = false;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _reload();
  }

  Future<void> _ignore(NoticeItem item) async {
    final approved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '屏蔽此类通知',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                item.username.isEmpty
                    ? '确认屏蔽此来源的这类通知吗？以后同类提醒可能不会再显示。'
                    : '确认屏蔽来自“${item.username}”的这类通知吗？以后同类提醒可能不会再显示。',
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.notifications_off_outlined),
                      label: const Text('确认屏蔽'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (approved != true) return;

    final result = await _api.ignoreNotice(item.ignoreUrl);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    if (result.success) {
      final ignoredKey = _noticeKey(item);
      setState(() {
        _ignoredNoticeKeys.add(ignoredKey);
        _items = _items
            .where((notice) => _noticeKey(notice) != ignoredKey)
            .toList(growable: false);
        _replyPreviews.remove(item.pid);
      });
      await _persistIgnoredNoticeKeys();
    }
  }

  Future<void> _pokeBack(NoticeItem item) async {
    if (item.authorUid.isEmpty) return;
    final sent = await showPokeDialog(
      context,
      uid: item.authorUid,
      username: item.username.isEmpty ? 'UID ${item.authorUid}' : item.username,
    );
    if (sent == true && mounted) _reload();
  }

  void _openTarget(NoticeItem item) {
    if (_type == 'friend' || item.type == 'friend') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FriendRequestsPage()),
      ).then((_) => _reload());
      return;
    }
    if (item.hasThreadTarget) {
      Navigator.push(
        context,
        buildThreadRoute(
          item.tid!,
          targetPid: item.pid,
          targetUrl: item.targetUrl,
        ),
      );
      return;
    }

    final url = item.targetUrl ?? '';
    if (url.contains('ac=usergroup') || url.contains('op=usergroup')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UserGroupPage()),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这条提醒暂时没有可直接打开的 App 页面')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('论坛通知'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: TabBar(
            controller: _tabController,
            isScrollable: false,
            dividerHeight: 0.8,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              for (final section in _sections)
                Tab(
                  height: 68,
                  icon: Icon(section.icon, size: 21),
                  text: section.label,
                ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_section.subtypes.isNotEmpty)
            Material(
              color: colors.surface,
              child: SizedBox(
                height: 50,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 7, 16, 6),
                  scrollDirection: Axis.horizontal,
                  itemCount: _section.subtypes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 7),
                  itemBuilder: (context, index) {
                    final subtype = _section.subtypes[index];
                    return FilterChip(
                      label: Text(subtype.label),
                      selected: _type == subtype.type,
                      visualDensity: VisualDensity.compact,
                      showCheckmark: true,
                      onSelected: (_) => _selectSubtype(subtype.type),
                    );
                  },
                ),
              ),
            ),
          if (_filteredOutItems.isNotEmpty)
            Material(
              color: colors.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 7, 10, 7),
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_alt_outlined,
                      size: 19,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _showFilteredNotices
                            ? '正在查看 ${_filteredOutItems.length} 条已过滤回复'
                            : '已过滤 ${_filteredOutItems.length} 条回复通知'
                                '${_totalPages > 1 ? ' · 已加载 $_page/$_totalPages 页' : ''}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showFilteredNotices = !_showFilteredNotices;
                        });
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                      },
                      child: Text(_showFilteredNotices ? '返回通知' : '查看'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final items = _visibleItems;
    if (_loading && items.isEmpty) {
      return const AppStateView.loading();
    }

    if (_error != null && items.isEmpty) {
      return AppStateView.error(
        message: _error!,
        onRetry: _reload,
      );
    }

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 150),
            AppStateView.empty(
              icon: Icons.notifications_none_rounded,
              title: '暂无通知',
              message: _items.isNotEmpty
                  ? '当前页提醒均已被过滤，可点击上方入口查看。'
                  : '这个分类目前没有提醒内容。',
            ),
            if (_hasMore)
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: _loadingMore ? null : _loadMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: const Text('继续加载'),
                ),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        itemCount: items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item = items[index];
          return _NoticeCard(
            item: item,
            sectionLabel: _section.label,
            replyPreview: _replyPreviews[item.pid],
            hasLocalAction: _type == 'friend' || item.type == 'friend',
            onPokeBack: (_type == 'poke' || item.type == 'poke') &&
                    item.authorUid.isNotEmpty
                ? () => _pokeBack(item)
                : null,
            onOpen: () => _openTarget(item),
            onIgnore: item.ignoreUrl == null ? null : () => _ignore(item),
          );
        },
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final NoticeItem item;
  final String sectionLabel;
  final VoidCallback onOpen;
  final VoidCallback? onIgnore;
  final Post? replyPreview;
  final bool hasLocalAction;
  final VoidCallback? onPokeBack;

  const _NoticeCard({
    required this.item,
    required this.sectionLabel,
    required this.onOpen,
    this.replyPreview,
    this.onIgnore,
    this.hasLocalAction = false,
    this.onPokeBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = item.isSystem
        ? sectionLabel
        : (item.username.isEmpty ? sectionLabel : item.username);
    final canOpen =
        hasLocalAction || item.targetUrl != null || item.hasThreadTarget;
    final action = item.actionText.isEmpty ? item.content : item.actionText;

    return Card(
      margin: EdgeInsets.zero,
      color: item.isUnread
          ? Color.alphaBlend(
              colors.primary.withValues(alpha: 0.055),
              colors.surfaceContainerLow,
            )
          : colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canOpen ? onOpen : null,
        onLongPress: onIgnore,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NoticeAvatar(item: item),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (item.isUnread) ...[
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                            ],
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (item.time.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                item.time,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.outline,
                                ),
                              ),
                            ],
                            if (onIgnore != null) ...[
                              const SizedBox(width: 3),
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: IconButton(
                                  tooltip: '忽略这条通知',
                                  onPressed: onIgnore,
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  iconSize: 18,
                                  color: colors.outline,
                                  icon: const Icon(
                                    Icons.notifications_off_outlined,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (action.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            action.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (replyPreview != null) ...[
                const SizedBox(height: 8),
                _NoticeReplyPreview(post: replyPreview!),
              ],
              if (canOpen) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasLocalAction
                            ? Icons.group_add_outlined
                            : item.hasThreadTarget
                                ? Icons.article_outlined
                                : Icons.open_in_new_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.targetTitle ??
                              (hasLocalAction
                                  ? '处理好友申请'
                                  : item.hasThreadTarget
                                      ? '查看相关帖子'
                                      : '查看相关页面'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.primary,
                      ),
                    ],
                  ),
                ),
              ],
              if (onPokeBack != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ActionChip(
                    onPressed: onPokeBack,
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      Icons.waving_hand_outlined,
                      size: 17,
                      color: colors.primary,
                    ),
                    label: const Text('回打招呼'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeReplyPreview extends StatelessWidget {
  final Post post;

  const _NoticeReplyPreview({required this.post});

  int get _imageCount {
    final seen = <String>{};

    void collect(Iterable<PostContent> contents) {
      for (final content in contents) {
        if (content.type == PostContentType.image) {
          final url = content.url?.trim() ?? '';
          if (url.isNotEmpty) seen.add(url);
        }
        if (content.children.isNotEmpty) collect(content.children);
      }
    }

    collect(post.richContent);
    for (final rawUrl in post.images) {
      final url = rawUrl.trim();
      if (url.isNotEmpty) seen.add(url);
    }
    return seen.length;
  }

  String get _summary {
    var value = ApiService.buildPostPreview(post).trim();
    if (value.isEmpty) return '';

    // 通知只做快速预览，不把图片占位符或大段换行带进卡片。
    value = value
        .replaceAll(RegExp(r'\[图片\]', caseSensitive: false), ' ')
        .replaceAll(
          RegExp(r'\[img\][\s\S]*?\[/img\]', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = _summary;
    final imageCount = _imageCount;

    if (text.isEmpty && imageCount == 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(9),
        border: Border(
          left: BorderSide(
            color: colors.primary.withValues(alpha: 0.72),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (text.isNotEmpty)
            Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.42,
              ),
            ),
          if (imageCount > 0) ...[
            if (text.isNotEmpty) const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_outlined,
                  size: 14,
                  color: colors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  imageCount == 1 ? '含图片' : '含 $imageCount 张图片',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NoticeAvatar extends StatelessWidget {
  final NoticeItem item;

  const _NoticeAvatar({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = item.avatarUrl;

    if (item.isSystem) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: colors.tertiaryContainer,
        child: Icon(
          Icons.campaign_outlined,
          color: colors.onTertiaryContainer,
        ),
      );
    }

    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: colors.secondaryContainer,
        child: Icon(
          Icons.person_outline_rounded,
          color: colors.onSecondaryContainer,
        ),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 40,
          height: 40,
          color: colors.surfaceContainerHighest,
        ),
        errorWidget: (_, __, ___) => Container(
          width: 40,
          height: 40,
          color: colors.secondaryContainer,
          alignment: Alignment.center,
          child: Icon(
            Icons.person_outline_rounded,
            color: colors.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _NoticeEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function()? action;

  const _NoticeEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: colors.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.outline,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => action!(),
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

class _NoticeSection {
  final String label;
  final String view;
  final IconData icon;
  final List<_NoticeSubtype> subtypes;

  const _NoticeSection({
    required this.label,
    required this.view,
    required this.icon,
    this.subtypes = const [],
  });
}

class _NoticeSubtype {
  final String label;
  final String type;

  const _NoticeSubtype(this.label, this.type);
}
