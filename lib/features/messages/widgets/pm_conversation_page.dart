part of '../../../pages/account/private_messages_page.dart';

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
