import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';

class ContactProfilePage extends StatefulWidget {
  const ContactProfilePage({super.key});

  @override
  State<ContactProfilePage> createState() => _ContactProfilePageState();
}

class _ContactProfilePageState extends State<ContactProfilePage> {
  final _api = ApiService.instance;
  final _qq = TextEditingController();
  final _mobile = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  int _privacyQq = 0;
  int _privacyMobile = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qq.dispose();
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final form = await _api.getContactProfile();
      if (!mounted) return;
      _qq.text = form.qq;
      _mobile.text = form.mobile;
      setState(() {
        _privacyQq = form.privacyQq;
        _privacyMobile = form.privacyMobile;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final result = await _api.updateContactProfile(
      ContactProfileForm(
        qq: _qq.text.trim(),
        privacyQq: _privacyQq,
        mobile: _mobile.text.trim(),
        privacyMobile: _privacyMobile,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    if (result.success) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('联系方式'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: const Text('保存'),
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
                      controller: _qq,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'QQ',
                        prefixIcon: Icon(Icons.chat_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _PrivacyField(
                      label: 'QQ 可见范围',
                      value: _privacyQq,
                      onChanged: (value) => setState(() => _privacyQq = value),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: '资料页手机号',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _PrivacyField(
                      label: '手机号可见范围',
                      value: _privacyMobile,
                      onChanged: (value) =>
                          setState(() => _privacyMobile = value),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存联系方式'),
                    ),
                  ],
                ),
    );
  }
}

class _PrivacyField extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _PrivacyField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = value == 0 || value == 1 || value == 3 ? value : 0;
    return DropdownButtonFormField<int>(
      value: safeValue,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.visibility_outlined),
      ),
      items: const [
        DropdownMenuItem(value: 0, child: Text('公开')),
        DropdownMenuItem(value: 1, child: Text('好友可见')),
        DropdownMenuItem(value: 3, child: Text('仅自己可见')),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
