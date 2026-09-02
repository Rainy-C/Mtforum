import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/smiley_catalog.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/image_host_service.dart';
import '../../services/message_badge_service.dart';
import '../../widgets/app_state_view.dart';
import 'user_profile_page.dart';

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
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundImage: item.avatarUrl == null
                                ? null
                                : CachedNetworkImageProvider(item.avatarUrl!),
                            child: item.avatarUrl == null
                                ? const Icon(Icons.person_outline_rounded)
                                : null,
                          ),
                          if (item.hasUnread)
                            Positioned(
                              top: -1,
                              right: -1,
                              child: Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: colors.error,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colors.surface,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
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
                        style: TextStyle(
                          fontWeight: item.hasUnread
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: item.hasUnread
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      trailing: item.lastTime?.isNotEmpty == true
                          ? Text(
                              _expandedPmListTime(item.lastTime!),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: item.hasUnread
                                        ? colors.primary
                                        : colors.outline,
                                    fontWeight: item.hasUnread
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                  ),
                            )
                          : null,
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
  final _controller = _PmSmileyEditingController();
  final _scroll = ScrollController();

  PmConversationData? _conversation;
  final List<PmMessage> _messages = [];

  Timer? _timer;
  bool _loading = true;
  bool _sending = false;
  bool _uploadingImage = false;
  bool _showSmileys = false;
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
      // 与论坛原生 comiis_getpmlist 的轮询周期保持一致。
      const Duration(seconds: 10),
      (_) => _poll(),
    );
  }

  String _messageKey(PmMessage message) {
    return '${message.senderUid}|${message.date}|${message.time}|'
        '${message.content}|${message.imageUrls.join(',')}';
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
        final today = _formatCalendarDate(DateTime.now());
        final normalizedNext = next
            .map(
              (message) => message.date.isNotEmpty
                  ? message
                  : PmMessage(
                      pmid: message.pmid,
                      senderUid: message.senderUid,
                      content: message.content,
                      time: message.time,
                      date: today,
                      isMine: message.isMine,
                      imageUrls: message.imageUrls,
                    ),
            )
            .toList(growable: false);
        final existing = _messages.map(_messageKey).toSet();

        final additions = normalizedNext
            .where((message) => existing.add(_messageKey(message)))
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

  Future<void> _send({
    String? overrideMessage,
    List<String> displayImageUrls = const [],
  }) async {
    final conversation = _conversation;
    final editorText = (overrideMessage ?? _controller.text).trim();
    final text = overrideMessage == null
        ? SmileyCatalog.toForumBbCode(editorText).trim()
        : editorText;

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
      final optimisticImages = <String>[...displayImageUrls];
      var optimisticText = displayImageUrls.isEmpty ? editorText : '';
      if (overrideMessage == null) {
        // 保留编辑器中的表情标记及其原始位置，发送后立即按行内表情显示。
        optimisticText = editorText;
        _controller.clear();
      }

      final now = DateTime.now();
      final displayTime = _formatClock(now);
      final displayDate = _formatCalendarDate(now);

      setState(() {
        _messages.add(
          PmMessage(
            senderUid: _api.currentUid,
            content: optimisticText,
            time: displayTime,
            date: displayDate,
            isMine: true,
            imageUrls: optimisticImages,
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

  void _toggleSmileys() {
    FocusScope.of(context).unfocus();
    setState(() => _showSmileys = !_showSmileys);
  }

  void _insertSmiley(String url) {
    final marker = SmileyCatalog.markerForUrl(url);
    if (marker == null) return;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.text.length;
    final end = selection.isValid ? selection.end : start;
    final next = _controller.text.replaceRange(start, end, marker);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + marker.length),
    );
  }

  Future<void> _sendImage() async {
    if (_sending || _uploadingImage) return;
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;

    setState(() => _uploadingImage = true);
    try {
      final uploaded = await ImageHostService.instance.uploadImage(image.path);
      if (!mounted) return;
      await _send(
        overrideMessage: uploaded.bbcode,
        displayImageUrls: [uploaded.url],
      );
    } catch (e) {
      if (mounted) {
        final message = e is StateError ? e.message : '图片上传失败：$e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _previewImage(String url) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, __) => const SizedBox(
                  width: 280,
                  height: 280,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => const SizedBox(
                  width: 280,
                  height: 180,
                  child: Center(child: Text('图片加载失败')),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
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

    final peerOnline = _conversation?.peerOnline;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.touid.trim().isEmpty ||
                        widget.touid.trim() == '0'
                    ? null
                    : () {
                        final uid = widget.touid.trim();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            settings: RouteSettings(name: '/user/$uid'),
                            builder: (_) => UserProfilePage(uid: uid),
                          ),
                        );
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            if (peerOnline != null) ...[
              const SizedBox(width: 8),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: peerOnline
                      ? const Color(0xFF35C46A)
                      : colors.outline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                peerOnline ? '在线' : '离线',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: peerOnline
                      ? const Color(0xFF35C46A)
                      : colors.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
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
                          final messageIndex = index;
                          final message = _messages[messageIndex];
                          final calendarDate = _normalizedPmDate(
                            message.date.isNotEmpty
                                ? message.date
                                : message.time,
                          );
                          final previousDate = messageIndex == 0
                              ? ''
                              : _normalizedPmDate(
                                  _messages[messageIndex - 1].date.isNotEmpty
                                      ? _messages[messageIndex - 1].date
                                      : _messages[messageIndex - 1].time,
                                );
                          final bubbleTime = _pmBubbleTime(message);

                          return Column(
                            children: [
                              if (calendarDate.isNotEmpty &&
                                  calendarDate != previousDate)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: Text(
                                    calendarDate,
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
                                      for (final imageUrl in message.imageUrls)
                                        Padding(
                                          padding: EdgeInsets.only(
                                            bottom: message.content.isEmpty ? 0 : 7,
                                          ),
                                          child: GestureDetector(
                                            onTap: SmileyCatalog.isForumSmileyUrl(imageUrl)
                                                ? null
                                                : () => _previewImage(imageUrl),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: CachedNetworkImage(
                                                imageUrl: imageUrl,
                                                width: SmileyCatalog.isForumSmileyUrl(imageUrl)
                                                    ? 30
                                                    : 180,
                                                height: SmileyCatalog.isForumSmileyUrl(imageUrl)
                                                    ? 30
                                                    : null,
                                                fit: SmileyCatalog.isForumSmileyUrl(imageUrl)
                                                    ? BoxFit.contain
                                                    : BoxFit.fitWidth,
                                                placeholder: (_, __) => SizedBox(
                                                  width: SmileyCatalog.isForumSmileyUrl(imageUrl)
                                                      ? 30
                                                      : 180,
                                                  height: SmileyCatalog.isForumSmileyUrl(imageUrl)
                                                      ? 30
                                                      : 110,
                                                  child: Center(
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  ),
                                                ),
                                                errorWidget: (_, __, ___) => SizedBox(
                                                  width: SmileyCatalog.isForumSmileyUrl(imageUrl)
                                                      ? 30
                                                      : 180,
                                                  height: SmileyCatalog.isForumSmileyUrl(imageUrl)
                                                      ? 30
                                                      : 100,
                                                  child: Center(
                                                    child: Text('图片加载失败'),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (message.content.isNotEmpty)
                                        _PmInlineMessageText(
                                          text: message.content,
                                        ),
                                      if (bubbleTime.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          bubbleTime,
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
                  IconButton(
                    tooltip: '选择图片并发送',
                    onPressed: _sending || _uploadingImage ? null : _sendImage,
                    icon: _uploadingImage
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image_outlined),
                  ),
                  IconButton(
                    tooltip: _showSmileys ? '收起表情' : '论坛表情',
                    isSelected: _showSmileys,
                    onPressed: _sending || _uploadingImage
                        ? null
                        : _toggleSmileys,
                    icon: const Icon(Icons.sentiment_satisfied_alt_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onTap: () {
                        if (_showSmileys) {
                          setState(() => _showSmileys = false);
                        }
                      },
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
                    onPressed: _sending || _uploadingImage
                        ? null
                        : () => _send(),
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
          if (_showSmileys)
            SafeArea(
              top: false,
              child: SizedBox(
                height: 236,
                child: _PmSmileyPicker(onSelected: _insertSmiley),
              ),
            ),
        ],
      ),
    );
  }
}

String _formatCalendarDate(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

String _formatClock(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

String _normalizedPmDate(String raw, {DateTime? reference}) {
  final now = reference ?? DateTime.now();
  final text = raw.trim();
  if (text.isEmpty) return '';
  if (text.contains('今天')) return _formatCalendarDate(now);
  if (text.contains('昨天')) {
    return _formatCalendarDate(now.subtract(const Duration(days: 1)));
  }
  if (text.contains('前天')) {
    return _formatCalendarDate(now.subtract(const Duration(days: 2)));
  }

  final full = RegExp(
    r'(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})',
  ).firstMatch(text);
  if (full != null) {
    return _formatCalendarDate(
      DateTime(
        int.parse(full.group(1)!),
        int.parse(full.group(2)!),
        int.parse(full.group(3)!),
      ),
    );
  }

  final short = RegExp(
    r'(\d{1,2})\s*[-/.月]\s*(\d{1,2})(?:\s*日)?',
  ).firstMatch(text);
  if (short != null) {
    return _formatCalendarDate(
      DateTime(
        now.year,
        int.parse(short.group(1)!),
        int.parse(short.group(2)!),
      ),
    );
  }
  return '';
}

String _normalizedPmClock(String raw) {
  final text = raw.trim();
  final match = RegExp(r'(上午|下午)?\s*(\d{1,2}):(\d{2})(?::(\d{2}))?')
      .firstMatch(text);
  if (match == null) return text;
  var hour = int.parse(match.group(2)!);
  final period = match.group(1);
  if (period == '下午' && hour < 12) hour += 12;
  if (period == '上午' && hour == 12) hour = 0;
  final minute = match.group(3)!;
  final second = match.group(4);
  return '${hour.toString().padLeft(2, '0')}:$minute'
      '${second == null ? '' : ':$second'}';
}

String _pmBubbleTime(PmMessage message) {
  for (final raw in [message.time, message.date]) {
    if (RegExp(r'(?:上午|下午)?\s*\d{1,2}:\d{2}(?::\d{2})?')
        .hasMatch(raw)) {
      return _normalizedPmClock(raw);
    }
  }
  return '';
}

String _expandedPmListTime(String raw, {DateTime? reference}) {
  final now = reference ?? DateTime.now();
  final text = raw.trim();
  if (text.isEmpty) return '';

  DateTime? value;
  if (text.contains('刚刚')) {
    value = now;
  } else if (text.contains('半小时前')) {
    value = now.subtract(const Duration(minutes: 30));
  } else {
    final relative = RegExp(r'(\d+)\s*(分钟|小时|天)前').firstMatch(text);
    if (relative != null) {
      final amount = int.parse(relative.group(1)!);
      value = switch (relative.group(2)) {
        '分钟' => now.subtract(Duration(minutes: amount)),
        '小时' => now.subtract(Duration(hours: amount)),
        _ => now.subtract(Duration(days: amount)),
      };
    }
  }

  final date = _normalizedPmDate(text, reference: now);
  final clock = _normalizedPmClock(text);
  if (value != null) {
    return '${_formatCalendarDate(value)} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
  if (date.isNotEmpty && RegExp(r'\d{1,2}:\d{2}').hasMatch(clock)) {
    return '$date $clock';
  }
  return text;
}

class _PmInlineMessageText extends StatelessWidget {
  final String text;

  const _PmInlineMessageText({required this.text});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();

    void flushText() {
      if (buffer.isEmpty) return;
      spans.add(TextSpan(text: buffer.toString()));
      buffer.clear();
    }

    void appendEmoji(String url) {
      flushText();
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const SizedBox(
                width: 28,
                height: 28,
                child: Icon(Icons.sentiment_satisfied_alt_rounded, size: 20),
              ),
            ),
          ),
        ),
      );
    }

    void appendTextWithMarkers(String value) {
      for (final codeUnit in value.codeUnits) {
        final url = SmileyCatalog.urlForCodeUnit(codeUnit);
        if (url == null) {
          buffer.writeCharCode(codeUnit);
        } else {
          appendEmoji(url);
        }
      }
    }

    final bbSmileyPattern = RegExp(
      r'\[img\](https?://[^\[]+)\[/img\]',
      caseSensitive: false,
    );
    var cursor = 0;
    for (final match in bbSmileyPattern.allMatches(text)) {
      if (match.start > cursor) {
        appendTextWithMarkers(text.substring(cursor, match.start));
      }
      final url = match.group(1)?.trim() ?? '';
      if (SmileyCatalog.isForumSmileyUrl(url)) {
        appendEmoji(url);
      } else {
        buffer.write(match.group(0));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      appendTextWithMarkers(text.substring(cursor));
    }
    flushText();

    return SelectableText.rich(
      TextSpan(style: style, children: spans),
    );
  }
}

class _PmSmileyEditingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();

    void flushText() {
      if (buffer.isEmpty) return;
      spans.add(TextSpan(text: buffer.toString(), style: style));
      buffer.clear();
    }

    for (final codeUnit in text.codeUnits) {
      final url = SmileyCatalog.urlForCodeUnit(codeUnit);
      if (url == null) {
        buffer.writeCharCode(codeUnit);
        continue;
      }
      flushText();
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: CachedNetworkImage(
            imageUrl: url,
            width: 26,
            height: 26,
            fit: BoxFit.contain,
            errorWidget: (_, __, ___) => const SizedBox(
              width: 26,
              height: 26,
              child: Icon(Icons.sentiment_satisfied_alt_rounded, size: 20),
            ),
          ),
        ),
      );
    }
    flushText();
    return TextSpan(style: style, children: spans);
  }
}

class _PmSmileyPicker extends StatelessWidget {
  final ValueChanged<String> onSelected;

  const _PmSmileyPicker({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: SmileyCatalog.packs.length,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: Column(
          children: [
            TabBar(
              dividerHeight: 1,
              tabs: [
                for (final pack in SmileyCatalog.packs)
                  Tab(text: '${pack.title}  ${pack.urls.length}'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final pack in SmileyCatalog.packs)
                    GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 54,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: pack.urls.length,
                      itemBuilder: (context, index) {
                        final url = pack.urls[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () => onSelected(url),
                          child: Center(
                            child: CachedNetworkImage(
                              imageUrl: url,
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => Icon(
                                Icons.broken_image_outlined,
                                size: 19,
                                color: colors.outline,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
