import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';

Future<bool?> showPokeDialog(
  BuildContext context, {
  required String uid,
  required String username,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _PokeDialog(uid: uid, username: username),
  );
}

class _PokeDialog extends StatefulWidget {
  final String uid;
  final String username;

  const _PokeDialog({
    required this.uid,
    required this.username,
  });

  @override
  State<_PokeDialog> createState() => _PokeDialogState();
}

class _PokeDialogState extends State<_PokeDialog> {
  final _api = ApiService.instance;
  final _note = TextEditingController();

  PokePageData? _data;
  int? _iconId;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getPokePage(widget.uid);
      if (!mounted) return;
      setState(() {
        _data = data;
        _iconId = data.options.isEmpty ? null : data.options.first.iconId;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '招呼方式加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final iconId = _iconId;
    if (_sending || iconId == null) return;

    setState(() => _sending = true);
    final result = await _api.sendPoke(
      uid: widget.uid,
      iconId: iconId,
      note: _note.text,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (result.success) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final options = _data?.options ?? const <PokeOption>[];

    return AlertDialog(
      title: Text('向 ${widget.username} 打招呼'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: _loading
            ? const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? SizedBox(
                    height: 150,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          onPressed: _load,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (options.isEmpty)
                          Text(
                            '论坛没有返回可用的招呼方式',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final option in options)
                                ChoiceChip(
                                  selected: _iconId == option.iconId,
                                  onSelected: (_) =>
                                      setState(() => _iconId = option.iconId),
                                  avatar: option.iconUrl == null
                                      ? null
                                      : CircleAvatar(
                                          backgroundColor: Colors.transparent,
                                          backgroundImage:
                                              CachedNetworkImageProvider(
                                            option.iconUrl!,
                                          ),
                                        ),
                                  label: Text(option.label),
                                ),
                            ],
                          ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _note,
                          maxLength: 120,
                          minLines: 1,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: '附言（可选）',
                            prefixIcon: Icon(Icons.edit_note_rounded),
                            alignLabelWithHint: true,
                          ),
                        ),
                        Text(
                          '招呼名称和图标来自论坛实时返回。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _loading || _error != null || _iconId == null || _sending
              ? null
              : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.waving_hand_rounded),
          label: const Text('发送'),
        ),
      ],
    );
  }
}
