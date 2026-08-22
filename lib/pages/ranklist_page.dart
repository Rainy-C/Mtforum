import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_state_view.dart';
import 'account/user_profile_page.dart';

class RanklistPage extends StatefulWidget {
  const RanklistPage({super.key});

  @override
  State<RanklistPage> createState() => _RanklistPageState();
}

class _RanklistPageState extends State<RanklistPage>
    with SingleTickerProviderStateMixin {
  final _api = ApiService.instance;
  late TabController _tabController;

  static const _tabs = [
    ('积分榜', 'credit', Icons.star_rounded),
    ('发帖榜', 'post', Icons.edit_note_rounded),
    ('活跃榜', 'onlinetime', Icons.access_time_rounded),
    ('美女榜', 'beauty', Icons.face_3_outlined),
    ('帅哥榜', 'handsome', Icons.face_outlined),
  ];

  final _data = <int, List<RankItem>>{};
  final _loading = <int, bool>{};
  final _error = <int, String?>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _load(_tabController.index);
    });
    _load(0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load(int index) async {
    if (_loading[index] == true) return;
    setState(() {
      _loading[index] = true;
      _error[index] = null;
    });
    try {
      final items = await _api.getRanklist(view: _tabs[index].$2);
      if (!mounted) return;
      setState(() {
        _data[index] = items;
        _loading[index] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error[index] = '$e';
        _loading[index] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final index = _tabController.index;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶部标题 + 关闭
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.emoji_events_rounded,
                      color: colors.primary, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    '排行榜',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            // Tab 栏
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerHeight: 0,
                indicator: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: colors.onPrimaryContainer,
                unselectedLabelColor: colors.onSurfaceVariant,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                tabs: [
                  for (final t in _tabs)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(t.$3, size: 15),
                          const SizedBox(width: 4),
                          Text(t.$1),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // 内容
            Expanded(
              child: _loading[index] == true
                  ? const AppStateView.loading()
                  : _error[index] != null
                      ? AppStateView.error(
                          message: '加载失败：${_error[index]}',
                          onRetry: () => _load(index),
                        )
                      : (_data[index]?.isEmpty ?? true)
                          ? const AppStateView.empty(
                              icon: Icons.emoji_events_outlined,
                              title: '暂无排行数据',
                              message: '当前排行榜暂时没有数据。',
                            )
                          : RefreshIndicator(
                              onRefresh: () => _load(index),
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 4, 16, 24),
                                itemCount: _data[index]!.length,
                                itemBuilder: (context, i) =>
                                    _RankCard(item: _data[index]![i]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 排行榜用户卡片。
class _RankCard extends StatelessWidget {
  final RankItem item;

  const _RankCard({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.rank >= 1 && item.rank <= 3) {
      return _TopRankCard(item: item);
    }
    return _RegularRankCard(item: item);
  }
}

class _TopRankCard extends StatelessWidget {
  final RankItem item;

  const _TopRankCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = switch (item.rank) {
      1 => const Color(0xFFE5A000),
      2 => const Color(0xFF78909C),
      _ => const Color(0xFFC47745),
    };
    final label = switch (item.rank) {
      1 => '冠军',
      2 => '亚军',
      _ => '季军',
    };
    final icon = switch (item.rank) {
      1 => Icons.workspace_premium_rounded,
      2 => Icons.military_tech_rounded,
      _ => Icons.military_tech_rounded,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openProfile(context, item.uid),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.18),
                  colors.surfaceContainerLow,
                  colors.surfaceContainerLow,
                ],
                stops: const [0, 0.52, 1],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accent.withValues(alpha: 0.42),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 58,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 18, color: accent),
                        const SizedBox(height: 1),
                        Text(
                          '${item.rank}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            height: 0.95,
                          ),
                        ),
                        Text(
                          '名',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 11),
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.20),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: _RankAvatar(item: item, radius: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (item.gender != null) ...[
                              const SizedBox(width: 5),
                              _GenderIcon(gender: item.gender!),
                            ],
                          ],
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (item.value.trim().isNotEmpty)
                              Text(
                                item.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: accent,
                    ),
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

class _RegularRankCard extends StatelessWidget {
  final RankItem item;

  const _RegularRankCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _openProfile(context, item.uid),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '#${item.rank}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 7),
            _RankAvatar(item: item, radius: 21),
          ],
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                item.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (item.gender != null) ...[
              const SizedBox(width: 5),
              _GenderIcon(gender: item.gender!),
            ],
          ],
        ),
        subtitle: item.value.trim().isEmpty
            ? null
            : Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _RankAvatar extends StatelessWidget {
  final RankItem item;
  final double radius;

  const _RankAvatar({required this.item, required this.radius});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initial = item.username.trim().isEmpty
        ? '?'
        : item.username.trim().characters.first;
    final fallback = Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceContainerHighest,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    final url = item.avatarUrl?.trim() ?? '';
    if (url.isEmpty) return fallback;

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}

class _GenderIcon extends StatelessWidget {
  final String gender;

  const _GenderIcon({required this.gender});

  @override
  Widget build(BuildContext context) {
    final isFemale = gender == '女';
    return Icon(
      isFemale ? Icons.female_rounded : Icons.male_rounded,
      size: 15,
      color: isFemale ? const Color(0xFFE85B8D) : const Color(0xFF4F8EDB),
    );
  }
}

void _openProfile(BuildContext context, String uid) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => UserProfilePage(uid: uid),
    ),
  );
}
