part of '../../../pages/mall_page.dart';

class MallDetailPage extends StatefulWidget {
  final MallItem item;

  const MallDetailPage({
    super.key,
    required this.item,
  });

  @override
  State<MallDetailPage> createState() => _MallDetailPageState();
}

class _MallDetailPageState extends State<MallDetailPage> {
  final _api = ApiService.instance;

  MallDetail? _detail;
  bool _loading = false;
  bool _exchanging = false;
  String? _error;

  String? get _imageUrl {
    final detailImage = _detail?.imageUrl?.trim() ?? '';
    if (detailImage.isNotEmpty) return detailImage;
    final listImage = widget.item.imageUrl?.trim() ?? '';
    return listImage.isEmpty ? null : listImage;
  }

  int? get _remaining => widget.item.remaining;
  int? get _purchased => widget.item.purchased;
  String? get _endTime => widget.item.endTime?.trim();

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
      final detail = await _api.getMallDetail(widget.item.tid);
      if (mounted) {
        setState(() => _detail = detail);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '详情加载失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _exchange() async {
    if (!_api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再兑换')),
      );
      return;
    }

    final detail = _detail;
    if (detail == null) {
      return;
    }
    if (_remaining == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该商品已兑完')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认兑换'),
        content: Text(
          detail.priceGold == null
              ? '确认兑换「${detail.title}」？\n\n成功兑换后将不能取消或更改，不提供退换货服务'
              : '确认使用 ${detail.priceGold} 金币兑换「${detail.title}」？\n\n成功兑换后将不能取消或更改，不提供退换货服务',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认兑换'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _exchanging = true);

    try {
      final result = await _api.exchangeMallItem(tid: widget.item.tid);

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            result.success
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
          ),
          title: Text(result.success ? '兑换成功' : '兑换失败'),
          content: Text(result.message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exchanging = false);
      }
    }
  }

  Future<void> _showCardStatus() async {
    try {
      final status = await _api.getMallCardStatus(widget.item.tid);
      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _MallCardStatusDialog(status: status),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('卡密信息获取失败，请稍后重试')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final imageUrl = _imageUrl;
    final remaining = _remaining;
    final purchased = _purchased;
    final total = (remaining ?? 0) + (purchased ?? 0);
    final progress = total > 0 && purchased != null
        ? (purchased / total).clamp(0.0, 1.0)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('商品详情'),
      ),
      body: _loading && _detail == null
          ? const AppStateView.loading()
          : _error != null && _detail == null
              ? AppStateView.error(message: _error!, onRetry: _load)
              : _detail == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        if (imageUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: AspectRatio(
                              aspectRatio: 16 / 10,
                              child: CachedNetworkImage(
                                imageUrl: imageUrl!,
                                fit: BoxFit.contain,
                                color: null,
                                // 关闭淡入淡出，避免图片加载过程中反复闪烁
                                fadeInDuration: Duration.zero,
                                placeholderFadeInDuration: Duration.zero,
                                placeholder: (_, __) => ColoredBox(
                                  color: colors.surfaceContainerHighest,
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 18),
                        Text(
                          _detail!.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Material(
                          color: colors.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: colors.outlineVariant,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.monetization_on_rounded,
                                  color: colors.tertiary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _detail!.priceGold == null
                                      ? '金币价格未知'
                                      : '${_detail!.priceGold} 金币',
                                  style:
                                      theme.textTheme.titleMedium?.copyWith(
                                    color: colors.tertiary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                if (_detail!.marketPrice != null)
                                  Text(
                                    _detail!.marketPrice!,
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: colors.outline,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (remaining != null ||
                            purchased != null ||
                            _endTime?.isNotEmpty == true)
                          Material(
                            color: colors.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colors.outlineVariant,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '兑换信息',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 8,
                                    children: [
                                      if (remaining != null)
                                        _MallInfoItem(
                                          icon: Icons.inventory_2_outlined,
                                          text: '剩余 $remaining 件',
                                        ),
                                      if (purchased != null)
                                        _MallInfoItem(
                                          icon: Icons.shopping_bag_outlined,
                                          text: '已兑换 $purchased 件',
                                        ),
                                    ],
                                  ),
                                  if (progress != null) ...[
                                    const SizedBox(height: 12),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 7,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '已兑换 ${(progress * 100).toStringAsFixed(1)}%',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  if (_endTime?.isNotEmpty == true) ...[
                                    const SizedBox(height: 10),
                                    _MallInfoItem(
                                      icon: Icons.schedule_rounded,
                                      text: '截止 $_endTime',
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Material(
                          color: colors.tertiaryContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 20,
                                  color: colors.onTertiaryContainer,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '兑换须知',
                                        style:
                                            theme.textTheme.titleSmall?.copyWith(
                                          color: colors.onTertiaryContainer,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '成功兑换后将不能取消或更改，不提供退换货服务',
                                        style:
                                            theme.textTheme.bodyMedium?.copyWith(
                                          color: colors.onTertiaryContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed:
                              _exchanging || remaining == 0 ? null : _exchange,
                          icon: _exchanging
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.shopping_bag_outlined),
                          label: Text(remaining == 0 ? '已兑完' : '立即兑换'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed:
                              _api.isLoggedIn ? _showCardStatus : null,
                          icon: const Icon(Icons.key_outlined),
                          label: const Text('查看卡密记录'),
                        ),
                      ],
                    ),
    );
  }
}
