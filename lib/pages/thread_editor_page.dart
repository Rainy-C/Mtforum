import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/smiley_catalog.dart';
import '../models/models.dart';
import '../services/api_service.dart';

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

  PostEditorForm? _form;
  bool _loading = true;
  bool _submitting = false;
  bool _allowNoticeAuthor = true;
  bool _useSig = true;
  String? _error;
  _EditorPanel _panel = _EditorPanel.none;

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
      _messageController.text = SmileyCatalog.fromForumBbCode(form.message);
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

    final subject = _subjectController.text.trim();
    final message = SmileyCatalog.toForumBbCode(_messageController.text).trim();

    if (!widget.editing && subject.isEmpty) {
      _showMessage('请输入帖子标题');
      return;
    }
    if (message.isEmpty) {
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
            )
          : await _api.submitNewThread(
              form: form,
              subject: subject,
              message: message,
              allowNoticeAuthor: _allowNoticeAuthor,
              useSig: _useSig,
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = widget.editing
        ? (widget.editSubject ? '编辑主题' : '编辑回复')
        : '发布新帖';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              onPressed: _loading || _submitting ? null : _submit,
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
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _loadForm)
              : SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      if (!widget.editing)
                        _ForumHeader(
                          forumName: widget.forumName,
                          colors: colors,
                        ),
                      if (!widget.editing) const _PostTypeBar(),
                      Expanded(
                        child: ListView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.zero,
                          children: [
                            if (!widget.editing || widget.editSubject)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                                child: TextField(
                                  controller: _subjectController,
                                  maxLength: 80,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    hintText: '标题  必填',
                                    counterText: '',
                                    border: UnderlineInputBorder(),
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                              child: SizedBox(
                                height: 280,
                                child: TextField(
                                  controller: _messageController,
                                  focusNode: _messageFocusNode,
                                  expands: true,
                                  minLines: null,
                                  maxLines: null,
                                  textAlignVertical: TextAlignVertical.top,
                                  keyboardType: TextInputType.multiline,
                                  onTap: () {
                                    if (_panel != _EditorPanel.none) {
                                      setState(() => _panel = _EditorPanel.none);
                                    }
                                  },
                                  decoration: InputDecoration(
                                    hintText: widget.editing
                                        ? '编辑帖子内容…'
                                        : '想和大家分享点什么…',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: colors.outlineVariant.withValues(alpha: 0.65),
                            ),
                            _EditorModeBar(
                              selected: _panel,
                              onSelected: _setPanel,
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: _buildPanel(context),
                            ),
                          ],
                        ),
                      ),
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
        return _AttachmentPanel(
          key: const ValueKey('attachment'),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      color: colors.surfaceContainerLow,
      child: Row(
        children: [
          Icon(Icons.forum_outlined, size: 17, color: colors.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              forumName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostTypeBar extends StatelessWidget {
  const _PostTypeBar();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 46,
      color: colors.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '发表帖子',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 5),
              Container(
                width: 34,
                height: 3,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
          const SizedBox(width: 32),
          Tooltip(
            message: '投票发帖接口尚未抓取',
            child: Text(
              '发投票',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.outline,
                  ),
            ),
          ),
        ],
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
  final VoidCallback onNetworkImage;

  const _AttachmentPanel({super.key, required this.onNetworkImage});

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
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('上传附件'),
              ),
              const SizedBox(width: 12),
              Text(
                '论坛附件上传接口待适配',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: onNetworkImage,
            icon: const Icon(Icons.image_outlined),
            label: const Text('插入网络图片'),
          ),
          const SizedBox(height: 8),
          Text(
            '本地附件不猜写操作；拿到真实 Filedata 上传请求后再接入。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
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
