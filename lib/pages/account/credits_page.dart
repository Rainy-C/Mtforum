import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';

class CreditsPage extends StatefulWidget {
  const CreditsPage({super.key});

  @override
  State<CreditsPage> createState() => _CreditsPageState();
}

class _CreditsPageState extends State<CreditsPage>
    with SingleTickerProviderStateMixin {
  final _api = ApiService.instance;

  late final TabController _tabs;

  CreditSummary? _summary;
  List<CreditRecord>? _log;
  List<CreditRecord>? _base;

  bool _loadingSummary = true;
  bool _loadingLog = false;
  bool _loadingBase = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_onTabChanged);
    _loadSummary();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;

    if (_tabs.index == 1 && _log == null && !_loadingLog) {
      _loadLog();
    } else if (_tabs.index == 2 && _base == null && !_loadingBase) {
      _loadBase();
    }
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loadingSummary = true;
      _error = null;
    });

    try {
      final summary = await _api.getCreditSummary();
      if (mounted) setState(() => _summary = summary);
    } catch (e) {
      if (mounted) setState(() => _error = '积分加载失败：$e');
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  Future<void> _loadLog() async {
    setState(() => _loadingLog = true);
    try {
      final records = await _api.getCreditRecords('log');
      if (mounted) setState(() => _log = records);
    } finally {
      if (mounted) setState(() => _loadingLog = false);
    }
  }

  Future<void> _loadBase() async {
    setState(() => _loadingBase = true);
    try {
      final records = await _api.getCreditRecords('base');
      if (mounted) setState(() => _base = records);
    } finally {
      if (mounted) setState(() => _loadingBase = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('积分中心'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '总览'),
            Tab(text: '记录'),
            Tab(text: '明细'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          RefreshIndicator(
            onRefresh: _loadSummary,
            child: _loadingSummary && _summary == null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 260),
                      Center(child: CircularProgressIndicator()),
                    ],
                  )
                : _error != null && _summary == null
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 200),
                          Center(child: Text(_error!)),
                        ],
                      )
                    : _SummaryView(summary: _summary!),
          ),
          _CreditRecordList(
            loading: _loadingLog,
            records: _log,
            emptyText: '暂无积分记录',
            onRefresh: _loadLog,
          ),
          _CreditRecordList(
            loading: _loadingBase,
            records: _base,
            emptyText: '暂无积分明细',
            onRefresh: _loadBase,
          ),
        ],
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  final CreditSummary summary;

  const _SummaryView({
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget stat(
      String label,
      int? value,
      IconData icon,
      Color accent,
    ) {
      return Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value?.toString() ?? '-',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            stat(
              '总积分',
              summary.total,
              Icons.stars_rounded,
              colors.primary,
            ),
            stat(
              '金币',
              summary.gold,
              Icons.monetization_on_rounded,
              colors.tertiary,
            ),
            stat(
              '好评',
              summary.praise,
              Icons.thumb_up_alt_outlined,
              colors.secondary,
            ),
            stat(
              '信誉',
              summary.reputation,
              Icons.verified_user_outlined,
              colors.primary,
            ),
          ],
        ),
      ],
    );
  }
}

class _CreditRecordList extends StatelessWidget {
  final bool loading;
  final List<CreditRecord>? records;
  final String emptyText;
  final Future<void> Function() onRefresh;

  const _CreditRecordList({
    required this.loading,
    required this.records,
    required this.emptyText,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (loading && records == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = records ?? const <CreditRecord>[];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
        itemCount: data.isEmpty ? 1 : data.length,
        itemBuilder: (context, index) {
          if (data.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 180),
              child: Center(
                child: Text(
                  emptyText,
                  style: TextStyle(color: colors.outline),
                ),
              ),
            );
          }

          final record = data[index];
          final deltaValue =
              int.tryParse(record.delta.replaceFirst('+', ''));
          final positive = deltaValue != null && deltaValue > 0;
          final negative = deltaValue != null && deltaValue < 0;
          final deltaColor = negative
              ? colors.error
              : positive
                  ? colors.primary
                  : colors.onSurfaceVariant;

          final title = record.reason.isNotEmpty
              ? record.reason
              : record.raw;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: deltaColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      negative
                          ? Icons.remove_rounded
                          : Icons.add_rounded,
                      color: deltaColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (record.time.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            record.time,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (record.delta.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          record.delta,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: deltaColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (record.type.isNotEmpty)
                          Text(
                            record.type,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.outline,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
