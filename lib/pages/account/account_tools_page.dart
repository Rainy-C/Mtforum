import 'package:flutter/material.dart';

import 'avatar_upload_page.dart';
import 'contact_profile_page.dart';
import 'password_security_page.dart';
import 'promotion_page.dart';
import 'rename_page.dart';
import 'signature_profile_page.dart';
import 'sms_settings_page.dart';
import 'user_group_page.dart';
import 'wall_page.dart';

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
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
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
            subtitle: '查看当前等级、升级进度与论坛权限',
            color: colors.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UserGroupPage(),
              ),
            ),
          ),
          tile(
            icon: Icons.drive_file_rename_outline_rounded,
            title: '改名',
            subtitle: '每次 200 金币，查看当前可用状态',
            color: colors.tertiary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const RenamePage(),
              ),
            ),
          ),
          tile(
            icon: Icons.forum_outlined,
            title: '留言墙',
            subtitle: '查看、发表和管理自己的留言',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WallPage(uid: uid),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
