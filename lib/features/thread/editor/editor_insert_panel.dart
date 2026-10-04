part of '../../../pages/thread_editor_page.dart';

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
