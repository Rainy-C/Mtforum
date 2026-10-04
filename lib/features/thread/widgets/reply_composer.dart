part of '../thread_detail_page.dart';

class _CommentComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loggedIn;
  final bool sending;
  final bool uploadingImage;
  final int attachmentCount;
  final bool canSend;
  final bool showSmileys;
  final String? replyTargetName;
  final VoidCallback onTapInput;
  final VoidCallback onToggleSmileys;
  final VoidCallback onPickImage;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;
  final ValueChanged<String> onSmileySelected;

  const _CommentComposer({
    required this.controller,
    required this.focusNode,
    required this.loggedIn,
    required this.sending,
    required this.uploadingImage,
    required this.attachmentCount,
    required this.canSend,
    required this.showSmileys,
    required this.replyTargetName,
    required this.onTapInput,
    required this.onToggleSmileys,
    required this.onPickImage,
    required this.onCancelReply,
    required this.onSend,
    required this.onSmileySelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyTargetName?.trim().isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 2, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.reply_rounded,
                      size: 16,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '回复 @$replyTargetName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '取消回复',
                      visualDensity: VisualDensity.compact,
                      onPressed: onCancelReply,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '表情',
                  isSelected: showSmileys,
                  onPressed: loggedIn ? onToggleSmileys : null,
                  icon: Icon(
                    showSmileys
                        ? Icons.keyboard_rounded
                        : Icons.sentiment_satisfied_alt_rounded,
                  ),
                ),
                IconButton(
                  tooltip: attachmentCount > 0
                      ? '已添加 $attachmentCount 张图片'
                      : '添加图片',
                  onPressed: loggedIn && !sending && !uploadingImage
                      ? onPickImage
                      : null,
                  icon: uploadingImage
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Badge(
                          isLabelVisible: attachmentCount > 0,
                          label: Text('$attachmentCount'),
                          child: const Icon(Icons.image_outlined),
                        ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    readOnly: !loggedIn,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    onTap: onTapInput,
                    decoration: InputDecoration(
                      hintText: loggedIn
                          ? (replyTargetName?.trim().isNotEmpty == true
                              ? '回复 @$replyTargetName…'
                              : '写下你的评论…')
                          : '登录后参与评论',
                      filled: true,
                      fillColor: colors.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: '发送',
                  onPressed: canSend ? onSend : null,
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: showSmileys
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        height: 220,
                        child: _SmileyPicker(
                          onSelected: onSmileySelected,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
