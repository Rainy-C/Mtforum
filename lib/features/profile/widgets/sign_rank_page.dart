part of '../../../pages/profile_page.dart';

// 签到页面
class _SignRankPage extends StatefulWidget {
  const _SignRankPage();

  @override
  State<_SignRankPage> createState() => _SignRankPageState();
}

class _SignRankPageState extends State<_SignRankPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _api = ApiService.instance;
  final _signs = SignService.instance;

  List<SignRecord> _records = [];
  bool _loading = false;
  bool _signing = false;
  bool _autoSign = false;
  bool _signedToday = false;

  final _tabs = const ['今日', '本月', '总排行'];
  final _types = const ['today', 'month', 'zong'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadData();
      }
    });
    _loadState();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final autoSign = await _signs.getAutoSignEnabled();
    final signedToday = await _signs.syncTodayStatus();

    if (!mounted) {
      return;
    }

    setState(() {
      _autoSign = autoSign;
      _signedToday = signedToday;
    });
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final records = await _api.getSignRank(
        _types[_tabController.index],
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _signNow() async {
    if (_signing) {
      return;
    }

    setState(() => _signing = true);

    try {
      final result = await _signs.signNow();

      if (!mounted) {
        return;
      }

      if (result.success) {
        setState(() => _signedToday = true);
        await _loadData();
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } finally {
      if (mounted) {
        setState(() => _signing = false);
      }
    }
  }

  Future<void> _setAutoSign(bool value) async {
    setState(() => _autoSign = value);
    await _signs.setAutoSignEnabled(value);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? '自动签到已开启：每天首次打开 App 自动签到'
              : '自动签到已关闭',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('签到'),
            pinned: true,
            bottom: TabBar(
              controller: _tabController,
              tabs: _tabs.map((tab) => Tab(text: tab)).toList(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Material(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _signedToday
                            ? colors.primaryContainer
                            : colors.surfaceContainerHighest,
                        child: Icon(
                          _signedToday
                              ? Icons.check_rounded
                              : Icons.calendar_today_rounded,
                          color: _signedToday
                              ? colors.onPrimaryContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      title: Text(
                        _signedToday ? '今日已签到' : '今日尚未签到',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _signedToday
                            ? '今天无需重复操作'
                            : '点击右侧按钮立即签到',
                      ),
                      trailing: FilledButton(
                        onPressed: _signing || _signedToday ? null : _signNow,
                        child: _signing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_signedToday ? '已签到' : '签到'),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.autorenew_rounded),
                      title: const Text('自动签到'),
                      subtitle: const Text(
                        '开启后每天第一次打开软件自动签到；失败会在下次启动重试',
                      ),
                      value: _autoSign,
                      onChanged: _setAutoSign,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
            sliver: SliverToBoxAdapter(
              child: Text(
                '${_tabs[_tabController.index]}签到排行',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_records.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  '暂无签到记录',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.outline,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final record = _records[index];
                    final topThree = index < 3;

                    final accent = switch (index) {
                      0 => const Color(0xFFE7A300),
                      1 => const Color(0xFF7D8897),
                      2 => const Color(0xFFA76438),
                      _ => colors.primary,
                    };

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: topThree
                            ? accent.withValues(alpha: 0.10)
                            : colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: topThree
                              ? accent.withValues(alpha: 0.32)
                              : colors.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: topThree
                                    ? accent
                                    : colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              alignment: Alignment.center,
                              child: topThree
                                  ? Icon(
                                      index == 0
                                          ? Icons.emoji_events_rounded
                                          : Icons.workspace_premium_rounded,
                                      color: Colors.white,
                                      size: 21,
                                    )
                                  : Text(
                                      '${index + 1}',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          record.username,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (topThree) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          '#${index + 1}',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: accent,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      if (record.signTime.isNotEmpty)
                                        record.signTime,
                                      if (record.totalDays.isNotEmpty)
                                        record.totalDays,
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
                            if (record.reward.trim().isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 120),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.secondaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  record.reward.replaceAll(
                                    RegExp(r'\s+'),
                                    ' ',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.onSecondaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _records.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
