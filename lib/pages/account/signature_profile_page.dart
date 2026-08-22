import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/app_state_view.dart';

class SignatureProfilePage extends StatefulWidget {
  const SignatureProfilePage({super.key});

  @override
  State<SignatureProfilePage> createState() => _SignatureProfilePageState();
}

class _SignatureProfilePageState extends State<SignatureProfilePage> {
  final _api = ApiService.instance;
  final _bioController = TextEditingController();
  final _signatureController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  int _privacyBio = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _api.getSignatureProfile();
      if (!mounted) return;

      _bioController.text = data.bio;
      _signatureController.text = data.signature;
      setState(() => _privacyBio = data.privacyBio);
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);

    final result = await _api.updateSignatureProfile(
      SignatureProfileForm(
        bio: _bioController.text.trim(),
        signature: _signatureController.text.trim(),
        privacyBio: _privacyBio,
      ),
    );

    if (!mounted) return;

    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );

    if (result.success) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('简介与签名'),
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
          ? const AppStateView.loading()
          : _error != null
              ? AppStateView.error(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    TextField(
                      controller: _bioController,
                      minLines: 1,
                      maxLines: 6,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: '个人简介',
                        hintText: '一句话介绍自己',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      value: _privacyBio == 0 ||
                              _privacyBio == 1 ||
                              _privacyBio == 3
                          ? _privacyBio
                          : 0,
                      decoration: const InputDecoration(
                        labelText: '简介可见范围',
                        prefixIcon: Icon(Icons.visibility_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('公开')),
                        DropdownMenuItem(value: 1, child: Text('好友可见')),
                        DropdownMenuItem(value: 3, child: Text('仅自己可见')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _privacyBio = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _signatureController,
                      minLines: 1,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        labelText: '个性签名',
                        hintText: '支持论坛可接受的文本 / BBCode',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.draw_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '论坛移动版会自行处理签名格式；这里不会直接执行 HTML。',
                      style: TextStyle(color: colors.outline),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存简介与签名'),
                    ),
                  ],
                ),
    );
  }
}
