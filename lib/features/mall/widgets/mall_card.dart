part of '../../../pages/mall_page.dart';

class _MallCard extends StatelessWidget {
  final MallItem item;
  final VoidCallback onTap;

  const _MallCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ColoredBox(
                color: colors.surfaceContainerHighest,
                child: item.imageUrl == null
                    ? const Icon(Icons.card_giftcard_rounded)
                    : CachedNetworkImage(
                        imageUrl: item.imageUrl!,
                        fit: BoxFit.cover,
                        // 关闭淡入淡出：占位与正式图互换时不闪烁
                        fadeInDuration: Duration.zero,
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 9, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          Icons.monetization_on_rounded,
                          size: 17,
                          color: colors.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.priceGold == null
                              ? '价格未知'
                              : '${item.priceGold} 金币',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.tertiary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (item.remaining != null)
                          '剩 ${item.remaining}',
                        if (item.purchased != null)
                          '已兑 ${item.purchased}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MallInfoItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MallInfoItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: colors.primary),
        const SizedBox(width: 5),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MallCardStatusDialog extends StatelessWidget {
  final MallCardStatus status;

  const _MallCardStatusDialog({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    final orderCount = status.purchases.length;
    final cardCount = status.recordCount;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: maxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.key_rounded,
                      color: colors.onPrimaryContainer,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '卡密记录',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (!status.isEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '$orderCount 个订单 · $cardCount 条卡密',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            Flexible(
              child: status.isEmpty
                  ? _MallCardEmptyState(colors: colors, theme: theme)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                      itemCount: status.purchases.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _MallCardPurchaseTile(
                        purchase: status.purchases[index],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MallCardEmptyState extends StatelessWidget {
  final ColorScheme colors;
  final ThemeData theme;

  const _MallCardEmptyState({
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 38, 24, 42),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.key_off_outlined,
              color: colors.onSurfaceVariant,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '暂无卡密记录',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '兑换卡密类商品后会显示在这里',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MallCardPurchaseTile extends StatelessWidget {
  final MallCardPurchase purchase;

  const _MallCardPurchaseTile({required this.purchase});

  Future<void> _copyCard(BuildContext context, String card) async {
    await Clipboard.setData(ClipboardData(text: card));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('卡密已复制'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    purchase.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (purchase.status?.isNotEmpty == true) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      purchase.status!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (purchase.orderedAt.isNotEmpty) ...[
              const SizedBox(height: 7),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 15,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '下单 ${purchase.orderedAt}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (purchase.loadFailed)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: colors.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '这条卡密加载失败，请关闭后重试',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (purchase.records.isEmpty)
              Text(
                '暂无卡密内容',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              )
            else
              ...purchase.records.map(
                (record) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 9),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.vpn_key_outlined,
                              size: 18,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                record.card,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '复制卡密',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _copyCard(context, record.card),
                              icon: const Icon(Icons.copy_rounded, size: 20),
                            ),
                          ],
                        ),
                        if (record.exchangedAt.isNotEmpty ||
                            record.status?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(26, 2, 6, 0),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              children: [
                                if (record.exchangedAt.isNotEmpty)
                                  Text(
                                    '兑换 ${record.exchangedAt}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                if (record.status?.isNotEmpty == true)
                                  Text(
                                    record.status!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
