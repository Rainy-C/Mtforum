import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';

class PasswordSecurityPage extends StatefulWidget {
  const PasswordSecurityPage({super.key});

  @override
  State<PasswordSecurityPage> createState() => _PasswordSecurityPageState();
}

class _PasswordSecurityPageState extends State<PasswordSecurityPage> {
  final _api = ApiService.instance;
  final _oldPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _newPasswordConfirm = TextEditingController();
  final _email = TextEditingController();
  final _answer = TextEditingController();

  PasswordSecurityData? _data;
  bool _loading = true;
  bool _saving = false;
  bool _sending = false;
  bool _hideOld = true;
  bool _hideNew = true;
  int _questionId = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _oldPassword.dispose();
    _newPassword.dispose();
    _newPasswordConfirm.dispose();
    _email.dispose();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _api.getPasswordSecurity();
      if (!mounted) return;
      _email.text = data.email;
      _questionId = data.questionId;
      setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_oldPassword.text.isEmpty) {
      _show('修改安全设置需要输入原密码');
      return;
    }
    if (_newPassword.text != _newPasswordConfirm.text) {
      _show('两次输入的新密码不一致');
      return;
    }

    setState(() => _saving = true);
    final data = _data;
    final result = await _api.updatePasswordSecurity(
      PasswordSecurityUpdate(
        oldPassword: _oldPassword.text,
        newPassword: _newPassword.text,
        newPasswordConfirm: _newPasswordConfirm.text,
        email: _email.text.trim(),
        mobileCountryCode: data?.mobileCountryCode ?? '',
        mobile: data?.mobile ?? '',
        questionId: _questionId,
        answer: _questionId == 0 ? '' : _answer.text.trim(),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    _show(result.message);

    if (result.success) {
      _oldPassword.clear();
      _newPassword.clear();
      _newPasswordConfirm.clear();
      _answer.clear();
      await _load();
    }
  }

  Future<void> _resend() async {
    if (_sending) return;
    setState(() => _sending = true);
    final result = await _api.resendVerificationEmail();
    if (!mounted) return;
    setState(() => _sending = false);
    _show(result.message);
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
    final questions = _data?.questions ?? const <SecurityQuestionOption>[];
    final questionIds = questions.map((e) => e.id).toSet();
    final int? selectedQuestion = questionIds.contains(_questionId)
        ? _questionId
        : (questionIds.contains(0) ? 0 : null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('密码安全'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
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
                    TextField(
                      controller: _oldPassword,
                      obscureText: _hideOld,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: '原密码',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _hideOld = !_hideOld),
                          icon: Icon(
                            _hideOld
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _newPassword,
                      obscureText: _hideNew,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: '新密码（不修改可留空）',
                        prefixIcon: const Icon(Icons.password_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _hideNew = !_hideNew),
                          icon: Icon(
                            _hideNew
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _newPasswordConfirm,
                      obscureText: _hideNew,
                      decoration: const InputDecoration(
                        labelText: '确认新密码',
                        prefixIcon: Icon(Icons.password_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: '邮箱',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: _sending ? null : _resend,
                      icon: _sending
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mark_email_unread_outlined),
                      label: const Text('重新发送验证邮件'),
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<int>(
                      value: selectedQuestion,
                      decoration: const InputDecoration(
                        labelText: '安全提问',
                        prefixIcon: Icon(Icons.help_outline_rounded),
                      ),
                      items: questions
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _questionId = value);
                      },
                    ),
                    if ((selectedQuestion ?? 0) != 0) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _answer,
                        decoration: const InputDecoration(
                          labelText: '安全提问答案',
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '修改密码、邮箱或安全提问时论坛都会验证原密码。手机号绑定请在“短信与手机”中操作。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存安全设置'),
                    ),
                  ],
                ),
    );
  }
}
