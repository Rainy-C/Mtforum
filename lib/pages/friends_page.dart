import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _api = ApiService.instance;
  final _scrollController = ScrollController();

  List<FriendItem> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore ||
        _loading ||
        !_hasMore ||
        !_scrollController.hasClients) {
      return;
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 220) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _page = 1;
      _hasMore = true;
      _error = null;
      _items = [];
    });

    try {
      final items = await _api.getMyFriends(page: 1);
      if (!mounted) {
        return;
      }

      setState(() {
        _items = items;
        _hasMore = items.isNotEmpty;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = '加载失败：$e');
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
      final nextPage = _page + 1;
      final next = await _api.getMyFriends(page: nextPage);
      if (!mounted) {
        return;
      }

      final known = _items.map((e) => e.uid).toSet();
      final additions = next.where((e) => !known.contains(e.uid)).toList();

      setState(() {
        if (additions.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(additions);
          _page = nextPage;
        }
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

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            title: const Text('我的好友'),
            pinned: true,
            actions: [
              IconButton(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _reload,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          else if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  '暂无好友',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == _items.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: _loadingMore
                              ? const CircularProgressIndicator()
                              : Text(
                                  _hasMore ? '继续下滑加载' : '没有更多了',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                        ),
                      );
                    }

                    final item = _items[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 7),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: item.avatarUrl != null
                              ? CachedNetworkImageProvider(item.avatarUrl!)
                              : null,
                          child: item.avatarUrl == null
                              ? Text(
                                  item.username.isEmpty
                                      ? '?'
                                      : item.username.substring(0, 1),
                                )
                              : null,
                        ),
                        title: Text(item.username),
                        subtitle: Text('UID ${item.uid}'),
                        trailing: item.messageUrl == null
                            ? null
                            : Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: theme.colorScheme.primary,
                              ),
                      ),
                    );
                  },
                  childCount: _items.length + 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
