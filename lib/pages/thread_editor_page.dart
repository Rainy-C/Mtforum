import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/smiley_catalog.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_state_view.dart';
import '../widgets/bbcode_preview.dart';

class ThreadEditorPage extends StatefulWidget {
  final bool editing;
  final String fid;
  final String forumName;
  final String tid;
  final String pid;
  final int page;
  final bool editSubject;

  const ThreadEditorPage.newThread({
    super.key,
    required this.fid,
    required this.forumName,
  })  : editing = false,
        tid = '',
        pid = '',
        page = 1,
        editSubject = true;

  const ThreadEditorPage.edit({
    super.key,
    required this.fid,
    required this.tid,
    required this.pid,
    required this.page,
    required this.editSubject,
  })  : editing = true,
        forumName = '';

  @override
  State<ThreadEditorPage> createState() => _ThreadEditorPageState();
}

enum _EditorPanel { none, smiley, mention, insert, attachment, advanced }

class _ThreadEditorPageState extends State<ThreadEditorPage> {
  final _api = ApiService.instance;
  final _subjectController = TextEditingController();
  final _messageController = _ForumSmileyEditingController();
  final _messageFocusNode = FocusNode();
  final _mentionController = TextEditingController();
  final _imagePicker = ImagePicker();

  PostEditorForm? _form;
  String _editReplyQuotePrefix = '';
  bool _loading = true;
  bool _submitting = false;
  bool _allowNoticeAuthor = true;
  bool _useSig = true;
  String? _error;
  _EditorPanel _panel = _EditorPanel.none;

  final List<PostAttachmentUploadResult> _uploadedAttachments = [];
  final Set<String> _deletingAttachmentAids = <String>{};
  bool _uploadingAttachment = false;
  String? _attachmentError;

  List<FriendItem> _friends = const [];
  bool _friendsLoading = false;
  String? _friendsError;

  @override
  void initState() {
    super.initState();
    _loadForm();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _mentionController.dispose();
    super.dispose();
  }

  (String, String) _splitGeneratedReplyQuote(String raw) {
    final leading = RegExp(r'^\s*').firstMatch(raw)?.end ?? 0;
    if (!raw.toLowerCase().startsWith('[quote]', leading)) {
      return ('', raw);
    }

    final remaining = raw.substring(leading);
    final generatedHeader = RegExp(
      r'^\[quote\]\s*\[color=#999999\][^\r\n]*发表于[^\r\n]*\[/color\]\s*(?:\r?\n)?\s*\[color=#999999\]',
      caseSensitive: false,
    );
    if (!generatedHeader.hasMatch(remaining)) {
      return ('', raw);
    }

    var depth = 0;
    int? quoteEnd;
    final tokenPattern = RegExp(r'\[/?quote\]', caseSensitive: false);
    for (final match in tokenPattern.allMatches(remaining)) {
      final token = match.group(0)!.toLowerCase();
      if (token == '[quote]') {
        depth++;
      } else {
        depth--;
        if (depth == 0) {
          quoteEnd = leading + match.end;
          break;
        }
      }
    }
    if (quoteEnd == null) return ('', raw);

    final separator = RegExp(r'^[ \t]*(?:\r?\n)+')
        .firstMatch(raw.substring(quoteEnd));
    final prefixEnd = quoteEnd + (separator?.end ?? 0);
    return (raw.substring(0, prefixEnd), raw.substring(prefixEnd));
  }

  Future<void> _loadForm() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final form = widget.editing
          ? await _api.getEditPostForm(
              fid: widget.fid,
              tid: widget.tid,
              pid: widget.pid,
              page: widget.page,
            )
          : await _api.getNewThreadForm(widget.fid);

      if (!mounted) return;

      _form = form;
      _subjectController.text = form.subject;

      var editableMessage = form.message;
      _editReplyQuotePrefix = '';
      if (widget.editing) {
        final parts = _splitGeneratedReplyQuote(form.message);
        _editReplyQuotePrefix = parts.$1;
        editableMessage = parts.$2;
      }
      _messageController.text = SmileyCatalog.fromForumBbCode(editableMessage);
      _messageController.selection = TextSelection.collapsed(
        offset: _messageController.text.length,
      );
      _allowNoticeAuthor = form.allowNoticeAuthor != '0';
      _useSig = form.useSig != '0';
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _readableError(e);
      });
    }
  }

  String _readableError(Object error) {
    final text = error.toString();
    return text.replaceFirst(
      RegExp(r'^(Bad state|StateError|Exception):\s*'),
      '',
    );
  }

  void _setPanel(_EditorPanel panel) {
    final next = _panel == panel ? _EditorPanel.none : panel;
    if (next == _EditorPanel.none) {
      setState(() => _panel = next);
      _messageFocusNode.requestFocus();
      return;
    }

    _messageFocusNode.unfocus();
    setState(() => _panel = next);
    if (next == _EditorPanel.mention) {
      _ensureFriends();
    }
  }

  Future<void> _ensureFriends() async {
    if (_friendsLoading || _friends.isNotEmpty) return;
    setState(() {
      _friendsLoading = true;
      _friendsError = null;
    });
    try {
      final items = await _api.getMyFriends(page: 1);
      if (!mounted) return;
      setState(() => _friends = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _friendsError = _readableError(e));
    } finally {
      if (mounted) setState(() => _friendsLoading = false);
    }
  }

  void _insertSmiley(String url) {
    final marker = SmileyCatalog.markerForUrl(url);
    if (marker == null) return;
    _replaceSelection('$marker ');
  }

  void _insertMention(String username) {
    final clean = username.trim().replaceFirst(RegExp(r'^@+'), '');
    if (clean.isEmpty) return;
    _replaceSelection('@$clean ');
    _mentionController.clear();
  }

  void _replaceSelection(String replacement, {int? cursorOffset}) {
    final value = _messageController.value;
    final selection = value.selection;
    final valid = selection.isValid && selection.start >= 0 && selection.end >= 0;
    final start = valid ? selection.start : value.text.length;
    final end = valid ? selection.end : start;
    final nextText = value.text.replaceRange(start, end, replacement);
    final offset = cursorOffset == null
        ? start + replacement.length
        : start + cursorOffset;

    _messageController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(
        offset: offset.clamp(0, nextText.length).toInt(),
      ),
      composing: TextRange.empty,
    );
  }

  void _wrapSelection(String open, String close) {
    final value = _messageController.value;
    final selection = value.selection;
    final valid = selection.isValid && selection.start >= 0 && selection.end >= 0;
    final start = valid ? selection.start : value.text.length;
    final end = valid ? selection.end : start;
    final selected = value.text.substring(start, end);
    final replacement = '$open$selected$close';
    final nextText = value.text.replaceRange(start, end, replacement);
    final nextOffset = selected.isEmpty ? start + open.length : start + replacement.length;

    _messageController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
    _panel = _EditorPanel.none;
    setState(() {});
    _messageFocusNode.requestFocus();
  }

  Future<void> _insertLink() async {
    final values = await _showTwoFieldDialog(
      title: '文字链接',
      firstLabel: '链接网址',
      firstHint: 'https://example.com',
      secondLabel: '链接文字',
      secondHint: '显示文字（可留空）',
    );
    if (values == null || values.first.trim().isEmpty) return;
    final url = values.first.trim();
    final label = values.second.trim().isEmpty ? url : values.second.trim();
    _replaceSelection('[url=$url]$label[/url]');
    _closePanelAndFocus();
  }

  Future<void> _insertSingleUrl({
    required String title,
    required String hint,
    required String Function(String value) build,
  }) async {
    final value = await _showSingleFieldDialog(title: title, hint: hint);
    if (value == null || value.trim().isEmpty) return;
    _replaceSelection(build(value.trim()));
    _closePanelAndFocus();
  }

  void _closePanelAndFocus() {
    setState(() => _panel = _EditorPanel.none);
    _messageFocusNode.requestFocus();
  }

  Future<void> _pickAndUploadImages() async {
    final form = _form;
    if (form == null || _uploadingAttachment) return;
    if (!form.canUploadImages) {
      _showMessage('当前页面没有附件上传凭证，请重新打开发帖页');
      return;
    }

    try {
      final files = await _imagePicker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 2560,
        maxHeight: 2560,
      );
      if (files.isEmpty || !mounted) return;

      setState(() {
        _uploadingAttachment = true;
        _attachmentError = null;
      });

      final maxBytes = form.maxUploadSizeKb * 1024;
      var successCount = 0;
      final failures = <String>[];

      for (final file in files) {
        try {
          final bytes = await file.readAsBytes();
          if (bytes.length > maxBytes) {
            failures.add('${file.name} 超过 ${form.maxUploadSizeKb}KB');
            continue;
          }

          final result = await _api.uploadPostImage(
            form: form,
            bytes: bytes,
            fileName: file.name,
          );
          if (!mounted) return;

          if (result.success && result.aid.isNotEmpty) {
            setState(() => _uploadedAttachments.add(result));
            _replaceSelection('[attachimg]${result.aid}[/attachimg]\n');
            successCount++;
          } else {
            failures.add('${file.name}：${result.message}');
          }
        } catch (e) {
          failures.add('${file.name}：${_readableError(e)}');
        }
      }

      if (!mounted) return;
      setState(() {
        _attachmentError = failures.isEmpty ? null : failures.join('；');
      });
      if (successCount > 0) {
        _showMessage('已上传 $successCount 张图片并插入正文');
      } else if (failures.isNotEmpty) {
        _showMessage(failures.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _attachmentError = _readableError(e));
      _showMessage(_readableError(e));
    } finally {
      if (mounted) setState(() => _uploadingAttachment = false);
    }
  }

  Future<void> _deleteUploadedAttachment(
    PostAttachmentUploadResult attachment,
  ) async {
    final form = _form;
    if (form == null || attachment.aid.isEmpty) return;
    if (_deletingAttachmentAids.contains(attachment.aid)) return;

    setState(() => _deletingAttachmentAids.add(attachment.aid));
    try {
      final deleted = await _api.deletePostAttachment(
        form: form,
        aid: attachment.aid,
      );
      if (!mounted) return;
      if (!deleted) {
        _showMessage('删除附件失败，请稍后重试');
        return;
      }

      final marker = '[attachimg]${attachment.aid}[/attachimg]';
      final nextText = _messageController.text
          .replaceAll('$marker\n', '')
          .replaceAll(marker, '');
      _messageController.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
      setState(() {
        _uploadedAttachments.removeWhere((item) => item.aid == attachment.aid);
      });
      _showMessage('附件已删除');
    } catch (e) {
      if (mounted) _showMessage(_readableError(e));
    } finally {
      if (mounted) {
        setState(() => _deletingAttachmentAids.remove(attachment.aid));
      }
    }
  }

  Future<String?> _showSingleFieldDialog({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (_) => Navigator.pop(context, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('插入'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<({String first, String second})?> _showTwoFieldDialog({
    required String title,
    required String firstLabel,
    required String firstHint,
    required String secondLabel,
    required String secondHint,
  }) async {
    final first = TextEditingController();
    final second = TextEditingController();
    final result = await showDialog<({String first, String second})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: first,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: firstLabel,
                hintText: firstHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: second,
              decoration: InputDecoration(
                labelText: secondLabel,
                hintText: secondHint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              (first: first.text, second: second.text),
            ),
            child: const Text('插入'),
          ),
        ],
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  Future<void> _submit() async {
    final form = _form;
    if (form == null || _submitting) return;
    if (_uploadingAttachment) {
      _showMessage('请等待图片上传完成');
      return;
    }

    final subject = _subjectController.text.trim();
    final editableMessage =
        SmileyCatalog.toForumBbCode(_messageController.text).trim();
    final message = widget.editing && _editReplyQuotePrefix.isNotEmpty
        ? '$_editReplyQuotePrefix$editableMessage'
        : editableMessage;

    if (!widget.editing && subject.isEmpty) {
      _showMessage('请输入帖子标题');
      return;
    }
    if (editableMessage.isEmpty) {
      _showMessage('请输入帖子正文');
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = widget.editing
          ? await _api.submitEditPost(
              form: form,
              subject: subject,
              message: message,
              allowNoticeAuthor: _allowNoticeAuthor,
              useSig: _useSig,
              uploadedAttachmentAids:
                  _uploadedAttachments.map((item) => item.aid),
            )
          : await _api.submitNewThread(
              form: form,
              subject: subject,
              message: message,
              allowNoticeAuthor: _allowNoticeAuthor,
              useSig: _useSig,
              uploadedAttachmentAids:
                  _uploadedAttachments.map((item) => item.aid),
            );

      if (!mounted) return;
      if (result.success) {
        Navigator.pop(context, result);
      } else {
        _showMessage(result.message);
      }
    } catch (e) {
      if (mounted) _showMessage(_readableError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showPreview() async {
    final editableMessage =
        SmileyCatalog.toForumBbCode(_messageController.text).trim();
    if (editableMessage.isEmpty) {
      _showMessage('请输入帖子正文后再预览');
      return;
    }
    final message = widget.editing && _editReplyQuotePrefix.isNotEmpty
        ? '$_editReplyQuotePrefix$editableMessage'
        : editableMessage;
    final attachmentUrls = <String, String>{
      for (final attachment in _uploadedAttachments)
        if (attachment.aid.isNotEmpty && attachment.url.isNotEmpty)
          attachment.aid: attachment.url,
    };

    _messageFocusNode.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.92,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      '发帖预览',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: BbCodePreview(
                subject: _subjectController.text,
                bbcode: message,
                attachmentUrls: attachmentUrls,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = widget.editing
        ? (widget.editSubject ? '编辑主题' : '编辑回复')
        : '发布新帖';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '预览帖子',
            onPressed: _loading || _uploadingAttachment ? null : _showPreview,
            icon: const Icon(Icons.visibility_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              onPressed: _loading || _submitting || _uploadingAttachment
                  ? null
                  : _submit,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.editing ? '保存' : '发布'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const AppStateView.loading()
          : _error != null
              ? AppStateView.error(message: _error!, onRetry: _loadForm)
              : SafeArea(
                  top: false,
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                    children: [
                      if (!widget.editing) ...[
                        _ForumHeader(
                          forumName: widget.forumName,
                          colors: colors,
                        ),
                        const SizedBox(height: 10),
                      ],
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            if (!widget.editing || widget.editSubject) ...[
                              TextField(
                                controller: _subjectController,
                                maxLength: 80,
                                textInputAction: TextInputAction.next,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                                decoration: const InputDecoration(
                                  hintText: '帖子标题',
                                  counterText: '',
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.fromLTRB(
                                    16,
                                    15,
                                    16,
                                    13,
                                  ),
                                ),
                              ),
                              Divider(
                                height: 1,
                                color: colors.outlineVariant
                                    .withValues(alpha: 0.65),
                              ),
                            ],
                            TextField(
                              controller: _messageController,
                              focusNode: _messageFocusNode,
                              minLines: 10,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              textAlignVertical: TextAlignVertical.top,
                              onTap: () {
                                if (_panel != _EditorPanel.none) {
                                  setState(() => _panel = _EditorPanel.none);
                                }
                              },
                              decoration: InputDecoration(
                                hintText: widget.editing
                                    ? '编辑帖子内容…'
                                    : '分享你的内容、代码、图片或链接…',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  16,
                                ),
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: colors.outlineVariant
                                  .withValues(alpha: 0.65),
                            ),
                            _EditorModeBar(
                              selected: _panel,
                              onSelected: _setPanel,
                            ),
                          ],
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _panel == _EditorPanel.none
                            ? const SizedBox.shrink(key: ValueKey('none-gap'))
                            : Padding(
                                key: ValueKey(_panel),
                                padding: const EdgeInsets.only(top: 10),
                                child: Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: _buildPanel(context),
                                ),
                              ),
                      ),
                      if (_uploadingAttachment) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    switch (_panel) {
      case _EditorPanel.none:
        return const SizedBox.shrink(key: ValueKey('none'));
      case _EditorPanel.smiley:
        return Padding(
          key: const ValueKey('smiley'),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: SizedBox(
            height: 280,
            child: _ForumSmileyPicker(onSelected: _insertSmiley),
          ),
        );
      case _EditorPanel.mention:
        return _MentionPanel(
          key: const ValueKey('mention'),
          controller: _mentionController,
          friends: _friends,
          loading: _friendsLoading,
          error: _friendsError,
          onAdd: () => _insertMention(_mentionController.text),
          onFriend: (friend) => _insertMention(friend.username),
          onRetry: _ensureFriends,
        );
      case _EditorPanel.insert:
        return _InsertPanel(
          key: const ValueKey('insert'),
          onBold: () => _wrapSelection('[b]', '[/b]'),
          onItalic: () => _wrapSelection('[i]', '[/i]'),
          onTextLink: _insertLink,
          onNetworkImage: () => _insertSingleUrl(
            title: '网络图片',
            hint: 'https://example.com/image.jpg',
            build: (value) => '[img]$value[/img]',
          ),
          onAudio: () => _insertSingleUrl(
            title: 'MP3 音乐',
            hint: '音频直链',
            build: (value) => '[audio]$value[/audio]',
          ),
          onVideo: () => _insertSingleUrl(
            title: '网络视频',
            hint: '视频链接',
            build: (value) => '[media=x,500,375]$value[/media]',
          ),
          onFlash: () => _insertSingleUrl(
            title: 'Flash',
            hint: 'Flash 链接',
            build: (value) => '[flash]$value[/flash]',
          ),
          onQuote: () => _wrapSelection('[quote]', '[/quote]'),
          onCode: () => _wrapSelection('[code]', '[/code]'),
          onFree: () => _wrapSelection('[free]', '[/free]'),
          onHide: () => _wrapSelection('[hide]', '[/hide]'),
        );
      case _EditorPanel.attachment:
        final form = _form;
        return _AttachmentPanel(
          key: const ValueKey('attachment'),
          canUpload: form?.canUploadImages ?? false,
          uploading: _uploadingAttachment,
          maxSizeKb: form?.maxUploadSizeKb ?? 1024,
          attachments: _uploadedAttachments,
          deletingAids: _deletingAttachmentAids,
          error: _attachmentError,
          onUpload: _pickAndUploadImages,
          onDelete: _deleteUploadedAttachment,
          onNetworkImage: () => _insertSingleUrl(
            title: '网络图片',
            hint: 'https://example.com/image.jpg',
            build: (value) => '[img]$value[/img]',
          ),
        );
      case _EditorPanel.advanced:
        return _AdvancedPanel(
          key: const ValueKey('advanced'),
          allowNoticeAuthor: _allowNoticeAuthor,
          useSig: _useSig,
          onAllowNoticeAuthorChanged: (value) {
            setState(() => _allowNoticeAuthor = value);
          },
          onUseSigChanged: (value) {
            setState(() => _useSig = value);
          },
        );
    }
  }
}

class _ForumHeader extends StatelessWidget {
  final String forumName;
  final ColorScheme colors;

  const _ForumHeader({required this.forumName, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.primaryContainer.withValues(alpha: 0.48),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.forum_outlined, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              '发布到',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                forumName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorModeBar extends StatelessWidget {
  final _EditorPanel selected;
  final ValueChanged<_EditorPanel> onSelected;

  const _EditorModeBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final items = <({
      _EditorPanel panel,
      IconData icon,
      String label,
    })>[
      (
        panel: _EditorPanel.smiley,
        icon: Icons.sentiment_satisfied_alt_outlined,
        label: '表情',
      ),
      (panel: _EditorPanel.mention, icon: Icons.alternate_email, label: '@好友'),
      (panel: _EditorPanel.insert, icon: Icons.send_outlined, label: '插入'),
      (panel: _EditorPanel.attachment, icon: Icons.attach_file, label: '附件'),
      (panel: _EditorPanel.advanced, icon: Icons.tune_rounded, label: '高级'),
    ];

    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _ModeButton(
                icon: item.icon,
                label: item.label,
                selected: selected == item.panel,
                onTap: () => onSelected(item.panel),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: foreground),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MentionPanel extends StatelessWidget {
  final TextEditingController controller;
  final List<FriendItem> friends;
  final bool loading;
  final String? error;
  final VoidCallback onAdd;
  final ValueChanged<FriendItem> onFriend;
  final VoidCallback onRetry;

  const _MentionPanel({
    super.key,
    required this.controller,
    required this.friends,
    required this.loading,
    required this.error,
    required this.onAdd,
    required this.onFriend,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      color: colors.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: '请输入用户名',
                    isDense: true,
                  ),
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.alternate_email, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            const LinearProgressIndicator()
          else if (error != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(color: colors.error),
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('重试')),
              ],
            )
          else if (friends.isEmpty)
            Text(
              '暂无好友，可直接输入用户名添加 @',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            )
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final friend in friends.take(12))
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('@${friend.username}'),
                    onPressed: () => onFriend(friend),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            '插入 @用户名到正文',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.tertiary,
                ),
          ),
        ],
      ),
    );
  }
}

class _InsertPanel extends StatelessWidget {
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onTextLink;
  final VoidCallback onNetworkImage;
  final VoidCallback onAudio;
  final VoidCallback onVideo;
  final VoidCallback onFlash;
  final VoidCallback onQuote;
  final VoidCallback onCode;
  final VoidCallback onFree;
  final VoidCallback onHide;

  const _InsertPanel({
    super.key,
    required this.onBold,
    required this.onItalic,
    required this.onTextLink,
    required this.onNetworkImage,
    required this.onAudio,
    required this.onVideo,
    required this.onFlash,
    required this.onQuote,
    required this.onCode,
    required this.onFree,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String label, VoidCallback onTap})>[
      (icon: Icons.format_bold_rounded, label: '粗体', onTap: onBold),
      (icon: Icons.format_italic_rounded, label: '斜体', onTap: onItalic),
      (icon: Icons.title_rounded, label: '文字链接', onTap: onTextLink),
      (icon: Icons.image_outlined, label: '网络图片', onTap: onNetworkImage),
      (icon: Icons.music_note_rounded, label: 'MP3 音乐', onTap: onAudio),
      (icon: Icons.movie_outlined, label: '网络视频', onTap: onVideo),
      (icon: Icons.bolt_outlined, label: 'Flash', onTap: onFlash),
      (icon: Icons.format_quote_rounded, label: '引用', onTap: onQuote),
      (icon: Icons.code_rounded, label: '代码', onTap: onCode),
      (icon: Icons.star_outline_rounded, label: '免费信息', onTap: onFree),
      (icon: Icons.visibility_off_outlined, label: '隐藏内容', onTap: onHide),
    ];
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      color: colors.surfaceContainerLowest,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 3.0,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return OutlinedButton.icon(
            onPressed: item.onTap,
            icon: Icon(item.icon, size: 17),
            label: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }
}

class _AttachmentPanel extends StatelessWidget {
  final bool canUpload;
  final bool uploading;
  final int maxSizeKb;
  final List<PostAttachmentUploadResult> attachments;
  final Set<String> deletingAids;
  final String? error;
  final VoidCallback onUpload;
  final ValueChanged<PostAttachmentUploadResult> onDelete;
  final VoidCallback onNetworkImage;

  const _AttachmentPanel({
    super.key,
    required this.canUpload,
    required this.uploading,
    required this.maxSizeKb,
    required this.attachments,
    required this.deletingAids,
    required this.error,
    required this.onUpload,
    required this.onDelete,
    required this.onNetworkImage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      color: colors.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: canUpload && !uploading ? onUpload : null,
                  icon: uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(uploading ? '正在上传…' : '选择并上传图片'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onNetworkImage,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('网络图片'),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            canUpload
                ? '支持多选图片，单张最大 ${maxSizeKb}KB；上传成功后会自动插入正文。'
                : '当前发帖页没有返回 uid/hash 上传凭证，请重新打开发帖页后再试。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: canUpload ? colors.onSurfaceVariant : colors.error,
                ),
          ),
          if (error != null && error!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
            ),
          ],
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '已上传 ${attachments.length} 张',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            for (final attachment in attachments)
              _AttachmentItem(
                attachment: attachment,
                deleting: deletingAids.contains(attachment.aid),
                onDelete: () => onDelete(attachment),
              ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentItem extends StatelessWidget {
  final PostAttachmentUploadResult attachment;
  final bool deleting;
  final VoidCallback onDelete;

  const _AttachmentItem({
    required this.attachment,
    required this.deleting,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              width: 52,
              height: 52,
              child: attachment.url.isEmpty
                  ? ColoredBox(
                      color: colors.surfaceContainerHighest,
                      child: Icon(Icons.image_outlined, color: colors.primary),
                    )
                  : CachedNetworkImage(
                      imageUrl: attachment.url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => ColoredBox(
                        color: colors.surfaceContainerHighest,
                      ),
                      errorWidget: (_, __, ___) => ColoredBox(
                        color: colors.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName.isEmpty
                      ? '图片附件'
                      : attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  'AID ${attachment.aid} · 已插入正文',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '删除附件',
            onPressed: deleting ? null : onDelete,
            icon: deleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _AdvancedPanel extends StatelessWidget {
  final bool allowNoticeAuthor;
  final bool useSig;
  final ValueChanged<bool> onAllowNoticeAuthorChanged;
  final ValueChanged<bool> onUseSigChanged;

  const _AdvancedPanel({
    super.key,
    required this.allowNoticeAuthor,
    required this.useSig,
    required this.onAllowNoticeAuthorChanged,
    required this.onUseSigChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerLowest,
      child: Column(
        children: [
          const _DisabledAdvancedTile(
            title: '回复仅作者可见',
            subtitle: '开启时的真实提交参数尚未抓取',
          ),
          const Divider(height: 1),
          const _DisabledAdvancedTile(
            title: '回复倒序排列',
            subtitle: '开启时的真实提交参数尚未抓取',
          ),
          const Divider(height: 1),
          SwitchListTile(
            dense: true,
            title: const Text('接收回复通知'),
            value: allowNoticeAuthor,
            onChanged: onAllowNoticeAuthorChanged,
          ),
          const Divider(height: 1),
          SwitchListTile(
            dense: true,
            title: const Text('使用个人签名'),
            value: useSig,
            onChanged: onUseSigChanged,
          ),
        ],
      ),
    );
  }
}

class _DisabledAdvancedTile extends StatelessWidget {
  final String title;
  final String subtitle;

  const _DisabledAdvancedTile({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      title: Text(title),
      subtitle: Text(subtitle),
      value: false,
      onChanged: null,
    );
  }
}

class _ForumSmileyEditingController extends TextEditingController {
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
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
        ),
      );
    }

    flushText();
    return TextSpan(style: style, children: spans);
  }
}

class _ForumSmileyPicker extends StatelessWidget {
  final ValueChanged<String> onSelected;

  const _ForumSmileyPicker({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: SmileyCatalog.packs.length,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
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
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 58,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: pack.urls.length,
                      itemBuilder: (context, index) {
                        final url = pack.urls[index];
                        return Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => onSelected(url),
                            child: Center(
                              child: CachedNetworkImage(
                                imageUrl: url,
                                width: 34,
                                height: 34,
                                fit: BoxFit.contain,
                                placeholder: (_, __) => SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: colors.outline,
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Icon(
                                  Icons.broken_image_outlined,
                                  size: 20,
                                  color: colors.outline,
                                ),
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

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 44),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
