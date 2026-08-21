import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _api = ApiService.instance;

  final _realname = TextEditingController();
  final _province = TextEditingController();
  final _occupation = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  int _privacyRealname = 3;
  int _gender = 0;
  int _privacyGender = 0;
  int _birthyear = 0;
  int _birthmonth = 0;
  int _birthday = 0;
  int _privacyBirthday = 0;
  int _privacyResideCity = 0;
  int _privacyOccupation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _realname.dispose();
    _province.dispose();
    _occupation.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final form = await _api.getBasicProfileForm();
      if (!mounted) {
        return;
      }

      _realname.text = form.realname;
      _province.text = form.resideProvince;
      _occupation.text = form.occupation;

      setState(() {
        _privacyRealname = form.privacyRealname;
        _gender = form.gender;
        _privacyGender = form.privacyGender;
        _birthyear = form.birthyear;
        _birthmonth = form.birthmonth;
        _birthday = form.birthday;
        _privacyBirthday = form.privacyBirthday;
        _privacyResideCity = form.privacyResideCity;
        _privacyOccupation = form.privacyOccupation;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = '资料加载失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }

    setState(() => _saving = true);

    final result = await _api.updateBasicProfile(
      BasicProfileForm(
        realname: _realname.text.trim(),
        privacyRealname: _privacyRealname,
        gender: _gender,
        privacyGender: _privacyGender,
        birthyear: _birthyear,
        birthmonth: _birthmonth,
        birthday: _birthday,
        privacyBirthday: _privacyBirthday,
        resideProvince: _province.text.trim(),
        privacyResideCity: _privacyResideCity,
        occupation: _occupation.text.trim(),
        privacyOccupation: _privacyOccupation,
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );

    if (result.success) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑基本资料'),
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _load,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                  children: [
                    _Section(
                      title: '基本信息',
                      children: [
                        TextField(
                          controller: _realname,
                          decoration: const InputDecoration(
                            labelText: '真实姓名',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _PrivacySelector(
                          value: _privacyRealname,
                          onChanged: (value) =>
                              setState(() => _privacyRealname = value),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int>(
                          value: _gender,
                          decoration: const InputDecoration(
                            labelText: '性别',
                            prefixIcon: Icon(Icons.wc_rounded),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('保密')),
                            DropdownMenuItem(value: 1, child: Text('男')),
                            DropdownMenuItem(value: 2, child: Text('女')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _gender = value);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        _PrivacySelector(
                          value: _privacyGender,
                          onChanged: (value) =>
                              setState(() => _privacyGender = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _Section(
                      title: '生日',
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                value: _safeYear(_birthyear),
                                decoration:
                                    const InputDecoration(labelText: '年份'),
                                items: [
                                  const DropdownMenuItem(
                                    value: 0,
                                    child: Text('不设置'),
                                  ),
                                  for (var year = DateTime.now().year;
                                      year >= 1940;
                                      year--)
                                    DropdownMenuItem(
                                      value: year,
                                      child: Text('$year'),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _birthyear = value);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _safeRange(_birthmonth, 12),
                                decoration:
                                    const InputDecoration(labelText: '月'),
                                items: [
                                  const DropdownMenuItem(
                                    value: 0,
                                    child: Text('-'),
                                  ),
                                  for (var i = 1; i <= 12; i++)
                                    DropdownMenuItem(
                                      value: i,
                                      child: Text('$i'),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _birthmonth = value);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _safeRange(_birthday, 31),
                                decoration:
                                    const InputDecoration(labelText: '日'),
                                items: [
                                  const DropdownMenuItem(
                                    value: 0,
                                    child: Text('-'),
                                  ),
                                  for (var i = 1; i <= 31; i++)
                                    DropdownMenuItem(
                                      value: i,
                                      child: Text('$i'),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _birthday = value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _PrivacySelector(
                          value: _privacyBirthday,
                          onChanged: (value) =>
                              setState(() => _privacyBirthday = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _Section(
                      title: '其他资料',
                      children: [
                        TextField(
                          controller: _province,
                          decoration: const InputDecoration(
                            labelText: '居住省份',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _PrivacySelector(
                          label: '居住地可见范围',
                          value: _privacyResideCity,
                          onChanged: (value) =>
                              setState(() => _privacyResideCity = value),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _occupation,
                          decoration: const InputDecoration(
                            labelText: '职业',
                            prefixIcon: Icon(Icons.work_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _PrivacySelector(
                          label: '职业可见范围',
                          value: _privacyOccupation,
                          onChanged: (value) =>
                              setState(() => _privacyOccupation = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存资料'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '隐私：公开 / 好友可见 / 仅自己可见。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.outline,
                      ),
                    ),
                  ],
                ),
    );
  }

  int _safeYear(int value) {
    if (value == 0) {
      return 0;
    }
    if (value < 1940 || value > DateTime.now().year) {
      return 0;
    }
    return value;
  }

  int _safeRange(int value, int max) {
    return value >= 0 && value <= max ? value : 0;
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _PrivacySelector extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _PrivacySelector({
    this.label = '可见范围',
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = value == 0 || value == 1 || value == 3 ? value : 0;

    return DropdownButtonFormField<int>(
      value: normalized,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.visibility_outlined),
      ),
      items: const [
        DropdownMenuItem(value: 0, child: Text('公开')),
        DropdownMenuItem(value: 1, child: Text('好友可见')),
        DropdownMenuItem(value: 3, child: Text('仅自己可见')),
      ],
      onChanged: (next) {
        if (next != null) {
          onChanged(next);
        }
      },
    );
  }
}
