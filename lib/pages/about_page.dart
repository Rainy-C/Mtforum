import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/feedback_service.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _avatarUrl = 'https://loveqin.fun/Star.jpg';
  static const _authorName = '我什么也不想要了';
  static const _qq = '615192041';
  static const _email = '615162041@qq.com';
  static const _forumName = 'Cynnie';

  final _contentController = TextEditingController();
  final _contactController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _contentController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label 已复制'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submitFeedback() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入反馈内容')),
      );
      return;
    }

    setState(() => _sending = true);
    final result = await FeedbackService.instance.submit(
      content: content,
      contact: _contactController.text,
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (result.success) {
      _contentController.clear();
      _contactController.clear();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('关于'),
            pinned: true,
            centerTitle: true,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildAppHeader(theme, colors),
                  const SizedBox(height: 28),
                  const _SectionTitle(title: '作者信息'),
                  const SizedBox(height: 10),
                  _buildAuthorCard(theme, colors),
                  const SizedBox(height: 28),
                  const _SectionTitle(title: '问题反馈'),
                  const SizedBox(height: 10),
                  _buildFeedbackCard(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppHeader(ThemeData theme, ColorScheme colors) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primary,
                colors.primary.withValues(alpha: 0.72),
              ],
            ),
          ),
          child: const Icon(
            Icons.forum_rounded,
            size: 40,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'MT论坛',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'v2.17.24',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.outline,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'MT论坛第三方客户端',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildAuthorCard(ThemeData theme, ColorScheme colors) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        child: Column(
          children: [
            Container(
              width: 104,
              height: 104,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primaryContainer,
              ),
              child: ClipOval(
                child: Image.network(
                  _avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => ColoredBox(
                    color: colors.surfaceContainerHighest,
                    child: Icon(
                      Icons.person_rounded,
                      size: 48,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _authorName,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'MT论坛 · $_forumName',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Divider(color: colors.outlineVariant.withValues(alpha: 0.65)),
            _ContactRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'QQ',
              value: _qq,
              onCopy: () => _copy('QQ', _qq),
            ),
            _ContactRow(
              icon: Icons.mail_outline_rounded,
              label: 'Email',
              value: _email,
              onCopy: () => _copy('邮箱', _email),
            ),
            _ContactRow(
              icon: Icons.forum_outlined,
              label: 'MT论坛',
              value: _forumName,
              onCopy: () => _copy('论坛用户名', _forumName),
            ),
            const SizedBox(height: 10),
            Divider(color: colors.outlineVariant.withValues(alpha: 0.65)),
            const SizedBox(height: 12),
            Text(
              '技能',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            const _SkillBar(label: 'C++', percent: 56),
            const SizedBox(height: 12),
            const _SkillBar(label: 'Shell', percent: 16),
            const SizedBox(height: 12),
            const _SkillBar(label: 'Python', percent: 7),
            const SizedBox(height: 12),
            const _SkillBar(label: 'Java', percent: 3),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _contentController,
              minLines: 1,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: '反馈内容',
                hintText: '描述遇到的问题或建议…',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.feedback_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _contactController,
              decoration: const InputDecoration(
                labelText: '联系方式（可选）',
                hintText: 'QQ / 邮箱',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending ? null : _submitFeedback,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_sending ? '发送中…' : '提交反馈'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onCopy;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onCopy,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 19, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.outline,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.content_copy_rounded,
                size: 18,
                color: colors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillBar extends StatelessWidget {
  final String label;
  final int percent;

  const _SkillBar({required this.label, required this.percent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 8,
            backgroundColor: colors.surfaceContainerHighest,
            color: colors.primary,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
