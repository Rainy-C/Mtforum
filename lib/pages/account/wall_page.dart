import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/app_state_view.dart';

class WallPage extends StatefulWidget {
  final String uid;
  final String? username;

  const WallPage({
    super.key,
    required this.uid,
    this.username,
  });

  @override
  State<WallPage> createState() => _WallPageState();
}

class _WallPageState extends State<WallPage> {
  final _api = ApiService.instance;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  List<WallComment> _comments = const [];
  bool _loading = true;
  bool _submitting = false;
  final Set<String> _deleting = <String>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final comments = await _api.getWallComments(widget.uid);
      if (!mounted) return;
      setState(() => _comments = comments);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '留言加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入留言内容')),
      );
      return;
    }

    setState(() => _submitting = true);
    final result = await _api.postWallComment(
      uid: widget.uid,
      message: text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );

    if (result.success) {
      _controller.clear();
      _focusNode.unfocus();
      await _load();
    }
  }

  Future<void> _delete(WallComment comment) async {
    if (_deleting.contains(comment.cid)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除留言'),
        content: const Text('确定删除这条留言吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting.add(comment.cid));
    final result = await _api.deleteWallComment(
      uid: widget.uid,
      cid: comment.cid,
    );
    if (!mounted) return;

    setState(() {
      _deleting.remove(comment.cid);
      if (result.success) {
        _comments = _comments
            .where((item) => item.cid != comment.cid)
            .toList(growable: false);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final titleName = widget.username?.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          titleName == null || titleName.isEmpty
              ? '留言墙'
              : '$titleName 的留言墙',
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Material(
          color: colors.surface,
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: _api.isLoggedIn
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          minLines: 1,
                          maxLines: 7,
                          maxLength: 500,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: '写下留言…',
                            counterText: '',
                            filled: true,
                            fillColor: colors.surfaceContainerLow,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: '发送留言',
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  )
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    child: Text(
                      '登录后可以发表留言',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _comments.isEmpty) {
      return const AppStateView.loading();
    }

    if (_error != null && _comments.isEmpty) {
      return AppStateView.error(message: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _comments.isEmpty ? 1 : _comments.length,
        itemBuilder: (context, index) {
          if (_comments.isEmpty) {
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.46,
              child: const AppStateView.empty(
                icon: Icons.chat_bubble_outline_rounded,
                title: '暂无留言',
                message: '成为第一个在这里留言的人吧。',
              ),
            );
          }

          final comment = _comments[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _WallCommentCard(
              comment: comment,
              canDelete: _api.currentUid != null &&
                  _api.currentUid == comment.uid,
              deleting: _deleting.contains(comment.cid),
              onDelete: () => _delete(comment),
            ),
          );
        },
      ),
    );
  }
}

class _WallCommentCard extends StatelessWidget {
  final WallComment comment;
  final bool canDelete;
  final bool deleting;
  final VoidCallback onDelete;

  const _WallCommentCard({
    required this.comment,
    required this.canDelete,
    required this.deleting,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(url: comment.avatarUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          comment.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (comment.time.isNotEmpty)
                        Text(
                          comment.time,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    comment.content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            if (canDelete) ...[
              const SizedBox(width: 4),
              deleting
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: '删除留言',
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;

  const _Avatar({this.url});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final imageUrl = url?.trim();

    if (imageUrl == null || imageUrl.isEmpty) {
      return CircleAvatar(
        radius: 21,
        backgroundColor: colors.surfaceContainerHighest,
        child: const Icon(Icons.person_outline_rounded),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: 42,
        height: 42,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 42,
          height: 42,
          color: colors.surfaceContainerHighest,
        ),
        errorWidget: (_, __, ___) => Container(
          width: 42,
          height: 42,
          color: colors.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Icon(Icons.person_outline_rounded),
        ),
      ),
    );
  }
}
