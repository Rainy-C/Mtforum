import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_state_view.dart';
import 'account/user_group_page.dart';
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
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  int _generation = 0;
  String? _error;

  _NoticeSection get _section => _sections[_sectionIndex];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _sections.length, vsync: this);
    _tabController.addListener(_handleTabChange);
    _scrollController.addListener(_handleScroll);
    _reload();
  }

  @override
  void dispose() {
    _generation++;
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
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
    if (_scrollController.position.extentAfter < 420) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    final requestedView = _section.view;
    final requestedType = _type;

    if (!_api.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _page = 1;
        _hasMore = false;
        _loading = false;
        _loadingMore = false;
        _error = '请先登录后查看论坛通知';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _items = const [];
        _page = 1;
        _hasMore = false;
        _loading = true;
        _loadingMore = false;
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
      setState(() {
        _items = data.items;
        _page = 1;
        _hasMore = data.hasMore;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '通知加载失败：$e');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;

    final generation = _generation;
    final requestedView = _section.view;
    final requestedType = _type;
    final nextPage = _page + 1;

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

      final merged = <NoticeItem>[..._items];
      final keys = merged.map(_noticeKey).toSet();
      for (final item in data.items) {
        if (keys.add(_noticeKey(item))) merged.add(item);
      }

      setState(() {
        _items = merged;
        _page = nextPage;
        _hasMore = data.hasMore && data.items.isNotEmpty;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下一页加载失败：$e')),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  String _noticeKey(NoticeItem item) {
    if (item.id.isNotEmpty) return 'id:${item.id}';
    return '${item.type}|${item.authorUid}|${item.time}|${item.content}|${item.pid ?? ''}';
  }

  void _selectSubtype(String type) {
    if (_type == type) return;
    setState(() => _type = type);
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
      setState(() {
        _items = _items.where((notice) => _noticeKey(notice) != _noticeKey(item)).toList();
      });
    }
  }

  void _openTarget(NoticeItem item) {
    if (item.hasThreadTarget) {
      Navigator.push(
        context,
        buildThreadRoute(item.tid!),
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
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const AppStateView.loading();
    }

    if (_error != null && _items.isEmpty) {
      return AppStateView.error(
        message: _error!,
        onRetry: _reload,
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 150),
            AppStateView.empty(
              icon: Icons.notifications_none_rounded,
              title: '暂无通知',
              message: '这个分类目前没有提醒内容。',
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
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item = _items[index];
          return _NoticeCard(
            item: item,
            sectionLabel: _section.label,
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

  const _NoticeCard({
    required this.item,
    required this.sectionLabel,
    required this.onOpen,
    this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = item.isSystem
        ? sectionLabel
        : (item.username.isEmpty ? sectionLabel : item.username);
    final canOpen = item.targetUrl != null || item.hasThreadTarget;
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
          padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
          child: Row(
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
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.outline,
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
                          height: 1.38,
                        ),
                      ),
                    ],
                    if (canOpen) ...[
                      const SizedBox(height: 7),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.hasThreadTarget
                                ? Icons.article_outlined
                                : Icons.open_in_new_rounded,
                            size: 16,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              item.targetTitle ??
                                  (item.hasThreadTarget ? '查看相关帖子' : '查看相关页面'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 1),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: colors.primary,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onIgnore != null)
                PopupMenuButton<String>(
                  tooltip: '更多',
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.more_vert_rounded, color: colors.outline),
                  onSelected: (value) {
                    if (value == 'ignore') onIgnore?.call();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'ignore',
                      child: Row(
                        children: [
                          Icon(Icons.notifications_off_outlined, size: 19),
                          SizedBox(width: 10),
                          Text('屏蔽此类通知'),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
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
