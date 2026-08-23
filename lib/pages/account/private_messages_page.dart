import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/message_badge_service.dart';
import '../../widgets/app_state_view.dart';

class PrivateMessagesPage extends StatefulWidget {
  const PrivateMessagesPage({super.key});

  @override
  State<PrivateMessagesPage> createState() => _PrivateMessagesPageState();
}

class _PrivateMessagesPageState extends State<PrivateMessagesPage> {
  final _api = ApiService.instance;

  List<PmConversationSummary> _items = const [];
  bool _loading = true;
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
      final items = await _api.getPmConversations();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '私信加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('私信'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _items.isEmpty
          ? const AppStateView.loading()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _items.isEmpty ? 1 : _items.length,
                itemBuilder: (context, index) {
                  if (_items.isEmpty) {
                    return SizedBox(
                      height: 360,
                      child: _error != null
                          ? AppStateView.error(
                              message: _error!,
                              onRetry: _load,
                            )
                          : const AppStateView.empty(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: '暂无私信',
                              message: '还没有私信会话。',
                            ),
                    );
                  }

                  final item = _items[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -2),
                      minVerticalPadding: 6,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundImage: item.avatarUrl == null
                            ? null
                            : CachedNetworkImageProvider(item.avatarUrl!),
                        child: item.avatarUrl == null
                            ? const Icon(Icons.person_outline_rounded)
                            : null,
                      ),
                      title: Text(
                        item.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        item.lastMessage?.isNotEmpty == true
                            ? item.lastMessage!
                            : '暂无消息',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PmConversationPage(
                            touid: item.touid,
                            initialName: item.username,
                          ),
                        ),
                      ).then((_) => _load()),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class PmConversationPage extends StatefulWidget {
  final String touid;
  final String? initialName;

  const PmConversationPage({
    super.key,
    required this.touid,
    this.initialName,
  });

  @override
  State<PmConversationPage> createState() => _PmConversationPageState();
}

class _PmConversationPageState extends State<PmConversationPage> {
  final _api = ApiService.instance;
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  PmConversationData? _conversation;
  final List<PmMessage> _messages = [];

  Timer? _timer;
  bool _loading = true;
  bool _sending = false;
  bool _polling = false;
  int _endTimestamp = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _api.getPmConversation(widget.touid);
      if (!mounted) return;

      _conversation = data;
      _endTimestamp = data.endTimestamp;
      _messages
        ..clear()
        ..addAll(data.messages);

      setState(() {});
      _startPolling();
      _scrollToBottom();

      // 打开具体会话后论坛会清除该会话的 kmnums 未读标记。
      // 立即同步一次，从系统通知栏撤销已经读过的这条私信。
      unawaited(MessageBadgeService.instance.refresh(force: true));
    } catch (e) {
      if (mounted) setState(() => _error = '对话加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _poll(),
    );
  }

  Future<void> _poll() async {
    final conversation = _conversation;
    if (_polling ||
        conversation == null ||
        conversation.pmid.isEmpty ||
        !mounted) {
      return;
    }

    _polling = true;
    try {
      final next = await _api.pollPrivateMessages(
        touid: widget.touid,
        pmid: conversation.pmid,
        endTimestamp: _endTimestamp,
      );

      if (!mounted) return;

      if (next.isNotEmpty) {
        final existing = _messages
            .map((m) => '${m.senderUid}|${m.time}|${m.content}')
            .toSet();

        final additions = next
            .where(
              (m) => !existing.contains(
                '${m.senderUid}|${m.time}|${m.content}',
              ),
            )
            .toList();

        if (additions.isNotEmpty) {
          setState(() => _messages.addAll(additions));
          _scrollToBottom();
        }
      }

      _endTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    } finally {
      _polling = false;
    }
  }

  Future<void> _send() async {
    final conversation = _conversation;
    final text = _controller.text.trim();

    if (_sending ||
        conversation == null ||
        conversation.pmid.isEmpty ||
        text.isEmpty) {
      return;
    }

    setState(() => _sending = true);

    final result = await _api.sendPrivateMessage(
      touid: widget.touid,
      pmid: conversation.pmid,
      message: text,
    );

    if (!mounted) return;

    setState(() => _sending = false);

    if (result.success) {
      _controller.clear();

      final displayTime = TimeOfDay.now().format(context);

      setState(() {
        _messages.add(
          PmMessage(
            senderUid: _api.currentUid,
            content: text,
            time: displayTime,
            isMine: true,
          ),
        );
        _endTimestamp =
            DateTime.now().millisecondsSinceEpoch ~/ 1000;
      });

      _scrollToBottom();
      unawaited(_poll());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final parsedName = _conversation?.peerName.trim() ?? '';
    final initialName = widget.initialName?.trim() ?? '';

    final title = initialName.isNotEmpty &&
            !initialName.startsWith('UID ')
        ? initialName
        : parsedName.isNotEmpty &&
                !parsedName.startsWith('UID ')
            ? parsedName
            : '私信';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                    ? Center(child: Text(_error!))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];

                          return Column(
                            children: [
                              if (message.date.isNotEmpty &&
                                  (index == 0 ||
                                      _messages[index - 1].date !=
                                          message.date))
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: Text(
                                    message.date,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.outline,
                                    ),
                                  ),
                                ),
                              Align(
                                alignment: message.isMine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  constraints:
                                      const BoxConstraints(maxWidth: 320),
                                  margin:
                                      const EdgeInsets.only(bottom: 7),
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    9,
                                    12,
                                    7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: message.isMine
                                        ? colors.primaryContainer
                                        : colors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: Radius.circular(
                                        message.isMine ? 16 : 4,
                                      ),
                                      bottomRight: Radius.circular(
                                        message.isMine ? 4 : 16,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(message.content),
                                      if (message.time.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          message.time,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: colors.outline,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 7,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: '发送私信…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
