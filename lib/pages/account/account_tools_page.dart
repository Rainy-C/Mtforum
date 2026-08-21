import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import 'avatar_upload_page.dart';
import 'contact_profile_page.dart';
import 'invite_page.dart';
import 'password_security_page.dart';
import 'promotion_page.dart';
import 'signature_profile_page.dart';
import 'sms_settings_page.dart';

class AccountToolsPage extends StatelessWidget {
  final String uid;

  const AccountToolsPage({
    super.key,
    required this.uid,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Widget tile({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      Color? color,
    }) {
      return Card(
        margin: const EdgeInsets.only(bottom: 7),
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('账号工具')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 26),
        children: [
          tile(
            icon: Icons.account_circle_outlined,
            title: '修改头像',
            subtitle: '选择图片、压缩并上传论坛头像',
            color: colors.primary,
            onTap: () => Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => const AvatarUploadPage(),
              ),
            ),
          ),
          tile(
            icon: Icons.draw_outlined,
            title: '简介与签名',
            subtitle: '编辑个人简介、个性签名和简介隐私',
            color: colors.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SignatureProfilePage(),
              ),
            ),
          ),
          tile(
            icon: Icons.password_rounded,
            title: '密码安全',
            subtitle: '修改密码、邮箱、安全提问与验证邮件',
            color: colors.error,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PasswordSecurityPage(),
              ),
            ),
          ),
          tile(
            icon: Icons.sms_outlined,
            title: '短信与手机',
            subtitle: '绑定 / 解绑手机号与短信验证码',
            color: colors.secondary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SmsSettingsPage(),
              ),
            ),
          ),
          tile(
            icon: Icons.campaign_outlined,
            title: '访问推广',
            subtitle: '推广二维码、推广链接和奖励',
            color: colors.tertiary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PromotionPage(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              '其他账号信息',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.outline,
                  ),
            ),
          ),
          tile(
            icon: Icons.contact_phone_outlined,
            title: '联系方式',
            subtitle: '编辑 QQ、手机号和可见范围',
            color: colors.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ContactProfilePage(),
              ),
            ),
          ),
          tile(
            icon: Icons.groups_2_outlined,
            title: '用户组',
            subtitle: '当前用户组信息',
            onTap: () => _openRemote(
              context,
              keyName: 'usergroup',
              title: '用户组',
            ),
          ),
          tile(
            icon: Icons.format_list_bulleted_rounded,
            title: '用户组列表',
            subtitle: '论坛用户组列表',
            onTap: () => _openRemote(
              context,
              keyName: 'usergroup_list',
              title: '用户组列表',
            ),
          ),
          tile(
            icon: Icons.person_add_alt_1_rounded,
            title: '邀请好友',
            subtitle: '检查当前账号的邀请码权限',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InvitePage()),
            ),
          ),
          tile(
            icon: Icons.drive_file_rename_outline_rounded,
            title: '改名',
            subtitle: '绑定流程未完整抓包，只读展示',
            onTap: () => _openRemote(
              context,
              keyName: 'rename',
              title: '改名',
            ),
          ),
          tile(
            icon: Icons.forum_outlined,
            title: '留言墙',
            subtitle: '查看自己的留言墙',
            onTap: () => _openRemote(
              context,
              keyName: 'wall',
              title: '留言墙',
            ),
          ),
        ],
      ),
    );
  }

  void _openRemote(
    BuildContext context, {
    required String keyName,
    required String title,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemoteAccountPage(
          keyName: keyName,
          fallbackTitle: title,
          uid: uid,
        ),
      ),
    );
  }
}

class RemoteAccountPage extends StatefulWidget {
  final String keyName;
  final String fallbackTitle;
  final String uid;

  const RemoteAccountPage({
    super.key,
    required this.keyName,
    required this.fallbackTitle,
    required this.uid,
  });

  @override
  State<RemoteAccountPage> createState() => _RemoteAccountPageState();
}

class _RemoteAccountPageState extends State<RemoteAccountPage> {
  final _api = ApiService.instance;

  RemoteTextPageData? _data;
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
      final data = await _api.getAccountToolPage(
        widget.keyName,
        uid: widget.uid,
      );
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _data?.title ?? widget.fallbackTitle;
    final colors = Theme.of(context).colorScheme;
    final lines = _data?.lines ?? const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _data == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _data == null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 26),
                    children: [
                      if (lines.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 180),
                          child: Center(
                            child: Text(
                              '该页面暂未拿到可靠正文结构，已停止显示论坛导航和图标垃圾文本。',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.outline),
                            ),
                          ),
                        )
                      else
                        for (final line in lines)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(line),
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }
}
