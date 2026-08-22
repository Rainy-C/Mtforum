import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/app_state_view.dart';

class InvitePage extends StatefulWidget {
  const InvitePage({super.key});

  @override
  State<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends State<InvitePage> {
  final _api = ApiService.instance;
  InviteStatusData? _data;
  bool _loading = true;
  String? _error;

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
      final data = await _api.getInviteStatus();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('邀请好友'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const AppStateView.loading()
          : _error != null
              ? AppStateView.error(message: _error!, onRetry: _load)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Material(
                      color: colors.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                        side: BorderSide(color: colors.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _data?.canInvite == true
                                  ? Icons.person_add_alt_1_rounded
                                  : Icons.lock_outline_rounded,
                              size: 46,
                              color: _data?.canInvite == true
                                  ? colors.primary
                                  : colors.outline,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _data?.message ?? '未知状态',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (_data?.canInvite == true) ...[
                              const SizedBox(height: 8),
                              Text(
                                '邀请码购买写操作还没有真实抓包，本版本只读取权限状态，不猜测购买请求。',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
