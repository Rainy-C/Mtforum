part of '../thread_detail_page.dart';

class _ReplySheet extends StatefulWidget {
  final String tid, fid, noticeauthor;
  final String? repquotePid, replyToName;
  final VoidCallback onReplied;

  const _ReplySheet({
    required this.tid,
    required this.fid,
    required this.noticeauthor,
    this.repquotePid,
    this.replyToName,
    required this.onReplied,
  });

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final _controller = _SmileyEditingController();
  final _focusNode = FocusNode();

  bool _sending = false;
  bool _uploadingImage = false;
  bool _showSmileys = false;
  PostEditorForm? _replyForm;
  final List<PostAttachmentUploadResult> _replyAttachments = [];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleSmileys() {
    if (_showSmileys) {
      setState(() => _showSmileys = false);
      _focusNode.requestFocus();
      return;
    }

    _focusNode.unfocus();
    setState(() => _showSmileys = true);
  }

  void _hideSmileysForKeyboard() {
    if (_showSmileys) {
      setState(() => _showSmileys = false);
    }
  }

  void _insertSmiley(String url) {
    final marker = SmileyCatalog.markerForUrl(url);
    if (marker == null) {
      return;
    }

    final value = _controller.value;
    final selection = value.selection;
    final hasSelection = selection.isValid &&
        selection.start >= 0 &&
        selection.end >= 0;

    final start = hasSelection ? selection.start : value.text.length;
    final end = hasSelection ? selection.end : start;

    final nextText = value.text.replaceRange(start, end, marker);
    final nextOffset = start + marker.length;

    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  Future<void> _pickImage() async {
    if (_sending || _uploadingImage) return;
    setState(() {
      _uploadingImage = true;
      _showSmileys = false;
    });
    try {
      final result = await _pickAndUploadReplyImage(
        tid: widget.tid,
        fid: widget.fid,
        repquotePid: widget.repquotePid,
        currentForm: _replyForm,
      );
      if (!mounted || result == null) return;
      _replyForm = result.form;
      _replyAttachments.add(result.attachment);
      _insertAtSelection(
        _controller,
        '[attachimg]${result.attachment.aid}[/attachimg]\n',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片已上传并插入回复')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片上传失败：${_replyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _send() async {
    if (_sending || _uploadingImage) return;
    final editorValue = _controller.text.trim();
    if (editorValue.isEmpty) {
      return;
    }

    final message = SmileyCatalog.toForumBbCode(editorValue).trim();
    if (message.isEmpty) {
      return;
    }

    setState(() => _sending = true);

    try {
      final result = await ApiService.instance.replyThread(
        tid: widget.tid,
        fid: widget.fid,
        noticeauthor: widget.noticeauthor,
        message: message,
        repquotePid: widget.repquotePid,
        replyForm: _replyForm,
        uploadedAttachmentAids:
            _replyAttachments.map((attachment) => attachment.aid),
      );

      if (!mounted) {
        return;
      }

      if (result.success) {
        widget.onReplied();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('回复成功'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('回复失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final media = MediaQuery.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: media.size.height * 0.82,
          ),
          child: Material(
            color: colors.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.replyToName != null
                              ? '回复 @${widget.replyToName}'
                              : '回复帖子',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 8,
                    autofocus: true,
                    onTap: _hideSmileysForKeyboard,
                    decoration: InputDecoration(
                      hintText: widget.replyToName != null
                          ? '回复 @${widget.replyToName}...'
                          : '输入回复内容...',
                      filled: true,
                      fillColor: colors.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: '表情',
                        isSelected: _showSmileys,
                        onPressed: _toggleSmileys,
                        icon: Icon(
                          _showSmileys
                              ? Icons.keyboard_rounded
                              : Icons.sentiment_satisfied_alt_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: _replyAttachments.isEmpty
                            ? '添加图片'
                            : '已添加 ${_replyAttachments.length} 张图片',
                        onPressed:
                            _sending || _uploadingImage ? null : _pickImage,
                        icon: _uploadingImage
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Badge(
                                isLabelVisible: _replyAttachments.isNotEmpty,
                                label: Text('${_replyAttachments.length}'),
                                child: const Icon(Icons.image_outlined),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _showSmileys
                              ? '点击表情插入到当前光标位置'
                              : '支持 QQ / COMCOM 表情',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.outline,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed:
                            _sending || _uploadingImage ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: const Text('发送'),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: _showSmileys
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SizedBox(
                              height: 286,
                              child: _SmileyPicker(
                                onSelected: _insertSmiley,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
