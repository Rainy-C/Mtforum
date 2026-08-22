import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_state_view.dart';

class MallPage extends StatefulWidget {
  const MallPage({super.key});

  @override
  State<MallPage> createState() => _MallPageState();
}

class _MallPageState extends State<MallPage> {
  final _api = ApiService.instance;
  final _scrollController = ScrollController();

  final List<MallItem> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore || !_scrollController.hasClients) {
      return;
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _api.getMallItems(page: 1);
      if (!mounted) {
        return;
      }

      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _page = 1;
        _hasMore = items.isNotEmpty;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = '商城加载失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }

    setState(() => _loadingMore = true);

    try {
      final next = _page + 1;
      final items = await _api.getMallItems(page: next);

      if (!mounted) {
        return;
      }

      setState(() {
        if (items.isEmpty) {
          _hasMore = false;
          return;
        }

        final seen = _items.map((item) => item.tid).toSet();
        _items.addAll(items.where((item) => !seen.contains(item.tid)));
        _page = next;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadFirst,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text('积分商城'),
              pinned: true,
              actions: [
                IconButton(
                  tooltip: '刷新',
                  onPressed: _loading ? null : _loadFirst,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.monetization_on_rounded,
                      color: colors.onSecondaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _api.isLoggedIn
                            ? '使用论坛金币兑换商品'
                            : '可浏览商城；兑换商品需要先登录',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading && _items.isEmpty)
              const SliverFillRemaining(
                child: AppStateView.loading(),
              )
            else if (_error != null && _items.isEmpty)
              SliverFillRemaining(
                child: AppStateView.error(
                  message: _error!,
                  onRetry: _loadFirst,
                ),
              )
            else if (_items.isEmpty)
              SliverFillRemaining(
                child: const AppStateView.empty(
                  icon: Icons.shopping_bag_outlined,
                  title: '暂无商品',
                  message: '商城目前还没有可兑换商品。',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 420,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.28,
                  ),
                  itemCount: _items.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _items.length) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    final item = _items[index];
                    return _MallCard(
                      item: item,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MallDetailPage(tid: item.tid),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MallCard extends StatelessWidget {
  final MallItem item;
  final VoidCallback onTap;

  const _MallCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ColoredBox(
                color: colors.surfaceContainerHighest,
                child: item.imageUrl == null
                    ? const Icon(Icons.card_giftcard_rounded)
                    : CachedNetworkImage(
                        imageUrl: item.imageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 9, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          Icons.monetization_on_rounded,
                          size: 17,
                          color: colors.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.priceGold == null
                              ? '价格未知'
                              : '${item.priceGold} 金币',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.tertiary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (item.remaining != null)
                          '剩 ${item.remaining}',
                        if (item.purchased != null)
                          '已兑 ${item.purchased}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MallDetailPage extends StatefulWidget {
  final String tid;

  const MallDetailPage({
    super.key,
    required this.tid,
  });

  @override
  State<MallDetailPage> createState() => _MallDetailPageState();
}

class _MallDetailPageState extends State<MallDetailPage> {
  final _api = ApiService.instance;

  MallDetail? _detail;
  bool _loading = false;
  bool _exchanging = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await _api.getMallDetail(widget.tid);
      if (mounted) {
        setState(() => _detail = detail);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '详情加载失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _exchange() async {
    if (!_api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再兑换')),
      );
      return;
    }

    final detail = _detail;
    if (detail == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认兑换'),
        content: Text(
          detail.priceGold == null
              ? '确认兑换「${detail.title}」？'
              : '确认使用 ${detail.priceGold} 金币兑换「${detail.title}」？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认兑换'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _exchanging = true);

    try {
      final result = await _api.exchangeMallItem(tid: widget.tid);

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            result.success
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
          ),
          title: Text(result.success ? '兑换成功' : '兑换失败'),
          content: Text(result.message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exchanging = false);
      }
    }
  }

  Future<void> _showCardStatus() async {
    try {
      final text = await _api.getMallCardStatus(widget.tid);
      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('卡密状态'),
          content: SelectableText(
            text.isEmpty ? '暂无卡密信息' : text,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('商品详情'),
      ),
      body: _loading && _detail == null
          ? const AppStateView.loading()
          : _error != null && _detail == null
              ? AppStateView.error(message: _error!, onRetry: _load)
              : _detail == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        if (_detail!.imageUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: AspectRatio(
                              aspectRatio: 16 / 10,
                              child: CachedNetworkImage(
                                imageUrl: _detail!.imageUrl!,
                                fit: BoxFit.contain,
                                color: null,
                                placeholder: (_, __) => ColoredBox(
                                  color: colors.surfaceContainerHighest,
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 18),
                        Text(
                          _detail!.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Material(
                          color: colors.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: colors.outlineVariant,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.monetization_on_rounded,
                                  color: colors.tertiary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _detail!.priceGold == null
                                      ? '金币价格未知'
                                      : '${_detail!.priceGold} 金币',
                                  style:
                                      theme.textTheme.titleMedium?.copyWith(
                                    color: colors.tertiary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                if (_detail!.marketPrice != null)
                                  Text(
                                    _detail!.marketPrice!,
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: colors.outline,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _exchanging ? null : _exchange,
                          icon: _exchanging
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.shopping_bag_outlined),
                          label: const Text('立即兑换'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed:
                              _api.isLoggedIn ? _showCardStatus : null,
                          icon: const Icon(Icons.key_outlined),
                          label: const Text('查看卡密状态'),
                        ),
                      ],
                    ),
    );
  }
}
