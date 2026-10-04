import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/smiley_catalog.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/image_host_service.dart';
import '../../services/message_badge_service.dart';
import '../../widgets/app_state_view.dart';
import 'user_profile_page.dart';

part '../../features/messages/widgets/pm_conversation_page.dart';
part '../../features/messages/widgets/pm_message_text.dart';
part '../../features/messages/widgets/pm_smiley_picker.dart';

class PrivateMessagesPage extends StatefulWidget {
  const PrivateMessagesPage({super.key});

  @override
  State<PrivateMessagesPage> createState() => _PrivateMessagesPageState();
}

class _PrivateMessagesPageState extends State<PrivateMessagesPage> {
  final _api = ApiService.instance;

  List<PmConversationSummary> _items = const [];
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
      final items = await _api.getPmConversations();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '私信加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('私信'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _items.isEmpty
          ? const AppStateView.loading()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _items.isEmpty ? 1 : _items.length,
                itemBuilder: (context, index) {
                  if (_items.isEmpty) {
                    return SizedBox(
                      height: 360,
                      child: _error != null
                          ? AppStateView.error(
                              message: _error!,
                              onRetry: _load,
                            )
                          : const AppStateView.empty(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: '暂无私信',
                              message: '还没有私信会话。',
                            ),
                    );
                  }

                  final item = _items[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -2),
                      minVerticalPadding: 6,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundImage: item.avatarUrl == null
                                ? null
                                : CachedNetworkImageProvider(item.avatarUrl!),
                            child: item.avatarUrl == null
                                ? const Icon(Icons.person_outline_rounded)
                                : null,
                          ),
                          if (item.hasUnread)
                            Positioned(
                              top: -1,
                              right: -1,
                              child: Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: colors.error,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colors.surface,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        item.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        item.lastMessage?.isNotEmpty == true
                            ? item.lastMessage!
                            : '暂无消息',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: item.hasUnread
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: item.hasUnread
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      trailing: item.lastTime?.isNotEmpty == true
                          ? Text(
                              _expandedPmListTime(item.lastTime!),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: item.hasUnread
                                        ? colors.primary
                                        : colors.outline,
                                    fontWeight: item.hasUnread
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                  ),
                            )
                          : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PmConversationPage(
                            touid: item.touid,
                            initialName: item.username,
                          ),
                        ),
                      ).then((_) => _load()),
                    ),
                  );
                },
              ),
            ),
    );
  }
}


String _formatCalendarDate(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

String _formatClock(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

String _normalizedPmDate(String raw, {DateTime? reference}) {
  final now = reference ?? DateTime.now();
  final text = raw.trim();
  if (text.isEmpty) return '';
  if (text.contains('今天')) return _formatCalendarDate(now);
  if (text.contains('昨天')) {
    return _formatCalendarDate(now.subtract(const Duration(days: 1)));
  }
  if (text.contains('前天')) {
    return _formatCalendarDate(now.subtract(const Duration(days: 2)));
  }

  final full = RegExp(
    r'(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})',
  ).firstMatch(text);
  if (full != null) {
    return _formatCalendarDate(
      DateTime(
        int.parse(full.group(1)!),
        int.parse(full.group(2)!),
        int.parse(full.group(3)!),
      ),
    );
  }

  final short = RegExp(
    r'(\d{1,2})\s*[-/.月]\s*(\d{1,2})(?:\s*日)?',
  ).firstMatch(text);
  if (short != null) {
    return _formatCalendarDate(
      DateTime(
        now.year,
        int.parse(short.group(1)!),
        int.parse(short.group(2)!),
      ),
    );
  }
  return '';
}

String _normalizedPmClock(String raw) {
  final text = raw.trim();
  final match = RegExp(r'(上午|下午)?\s*(\d{1,2}):(\d{2})(?::(\d{2}))?')
      .firstMatch(text);
  if (match == null) return text;
  var hour = int.parse(match.group(2)!);
  final period = match.group(1);
  if (period == '下午' && hour < 12) hour += 12;
  if (period == '上午' && hour == 12) hour = 0;
  final minute = match.group(3)!;
  final second = match.group(4);
  return '${hour.toString().padLeft(2, '0')}:$minute'
      '${second == null ? '' : ':$second'}';
}

String _pmBubbleTime(PmMessage message) {
  for (final raw in [message.time, message.date]) {
    if (RegExp(r'(?:上午|下午)?\s*\d{1,2}:\d{2}(?::\d{2})?')
        .hasMatch(raw)) {
      return _normalizedPmClock(raw);
    }
  }
  return '';
}

String _expandedPmListTime(String raw, {DateTime? reference}) {
  final now = reference ?? DateTime.now();
  final text = raw.trim();
  if (text.isEmpty) return '';

  DateTime? value;
  if (text.contains('刚刚')) {
    value = now;
  } else if (text.contains('半小时前')) {
    value = now.subtract(const Duration(minutes: 30));
  } else {
    final relative = RegExp(r'(\d+)\s*(分钟|小时|天)前').firstMatch(text);
    if (relative != null) {
      final amount = int.parse(relative.group(1)!);
      value = switch (relative.group(2)) {
        '分钟' => now.subtract(Duration(minutes: amount)),
        '小时' => now.subtract(Duration(hours: amount)),
        _ => now.subtract(Duration(days: amount)),
      };
    }
  }

  final date = _normalizedPmDate(text, reference: now);
  final clock = _normalizedPmClock(text);
  if (value != null) {
    return '${_formatCalendarDate(value)} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
  if (date.isNotEmpty && RegExp(r'\d{1,2}:\d{2}').hasMatch(clock)) {
    return '$date $clock';
  }
  return text;
}
