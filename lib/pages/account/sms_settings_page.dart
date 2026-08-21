import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';

class SmsSettingsPage extends StatefulWidget {
  const SmsSettingsPage({super.key});

  @override
  State<SmsSettingsPage> createState() => _SmsSettingsPageState();
}

class _SmsSettingsPageState extends State<SmsSettingsPage> {
  final _api = ApiService.instance;
  final _phone = TextEditingController();
  final _code = TextEditingController();

  SmsBindingData? _data;
  bool _loading = true;
  bool _requesting = false;
  bool _confirming = false;
  bool _codeSent = false;
  int _cooldown = 0;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getSmsBinding();
      if (!mounted) return;
      _data = data;
      _phone.text = data.phone ?? '';
      _code.clear();
      _codeSent = false;
      _stopCountdown();
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isBound => _data?.phone?.isNotEmpty == true;
  String get _action => _isBound ? 'Unbundling' : 'binding';

  String _masked(String phone) {
    if (phone.length < 7) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }

  Future<void> _requestCode() async {
    final phone = _phone.text.trim();
    if (_requesting || _cooldown > 0) return;
    if (!RegExp(r'^\d{7,15}$').hasMatch(phone)) {
      _show('请输入正确的手机号');
      return;
    }

    setState(() => _requesting = true);
    final result = await _api.requestSmsCode(
      action: _action,
      phone: phone,
    );
    if (!mounted) return;
    setState(() {
      _requesting = false;
      _codeSent = result.success;
    });
    _show(result.message);
    if (result.success) {
      _startCountdown(result.cooldownSeconds > 0 ? result.cooldownSeconds : 60);
    }
  }

  Future<void> _confirm() async {
    final phone = _phone.text.trim();
    final code = _code.text.trim();
    if (_confirming) return;
    if (!_codeSent) {
      _show('请先获取验证码');
      return;
    }
    if (code.isEmpty) {
      _show('请输入短信验证码');
      return;
    }

    setState(() => _confirming = true);
    final result = await _api.confirmSmsBinding(
      action: _action,
      phone: phone,
      code: code,
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    _show(result.message);
    if (result.success) await _load();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown -= 1);
      }
    });
  }

  void _stopCountdown() {
    _timer?.cancel();
    _timer = null;
    _cooldown = 0;
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final boundPhone = _data?.phone;

    return Scaffold(
      appBar: AppBar(
        title: const Text('短信与手机'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                  children: [
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _isBound
                              ? colors.primaryContainer
                              : colors.surfaceContainerHighest,
                          child: Icon(
                            _isBound
                                ? Icons.phone_android_rounded
                                : Icons.phone_disabled_outlined,
                          ),
                        ),
                        title: Text(_isBound ? '已绑定手机' : '尚未绑定手机'),
                        subtitle: Text(
                          _isBound && boundPhone != null
                              ? _masked(boundPhone)
                              : '绑定后可使用短信安全功能',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _phone,
                      readOnly: _isBound,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: _isBound ? '当前手机号' : '新手机号',
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _code,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '短信验证码',
                              prefixIcon: Icon(Icons.sms_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _requesting || _cooldown > 0
                              ? null
                              : _requestCode,
                          child: Text(
                            _requesting
                                ? '发送中'
                                : _cooldown > 0
                                    ? '${_cooldown}s'
                                    : '获取验证码',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _confirming ? null : _confirm,
                      icon: _confirming
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _isBound
                                  ? Icons.link_off_rounded
                                  : Icons.link_rounded,
                            ),
                      label: Text(_isBound ? '确认解除绑定' : '确认绑定'),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isBound
                          ? '解绑必须先向当前绑定手机号发送验证码，验证码通过后才会真正解除绑定。'
                          : '绑定必须先向新手机号发送验证码，验证码通过后才会真正绑定。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.outline,
                      ),
                    ),
                  ],
                ),
    );
  }
}
