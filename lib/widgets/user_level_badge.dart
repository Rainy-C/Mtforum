import 'package:flutter/material.dart';

class UserLevelBadge extends StatelessWidget {
  final String text;
  final bool compact;

  const UserLevelBadge({
    super.key,
    required this.text,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final value = text.trim();
    if (value.isEmpty) return const SizedBox.shrink();

    final style = _styleFor(value, Theme.of(context).colorScheme);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: style.foreground.withValues(alpha: 0.26),
        ),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: style.foreground,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }

  _BadgeStyle _styleFor(String value, ColorScheme colors) {
    final normalized = value.toLowerCase();

    if (normalized.contains('管理员') || normalized.contains('admin')) {
      return const _BadgeStyle(
        foreground: Color(0xFFB3261E),
        background: Color(0xFFFFDAD6),
      );
    }

    if (normalized.contains('超级版主') ||
        normalized.contains('版主') ||
        normalized.contains('moderator')) {
      return const _BadgeStyle(
        foreground: Color(0xFFB0185B),
        background: Color(0xFFFFD8E7),
      );
    }

    if (normalized.contains('管理') ||
        normalized.contains('审核') ||
        normalized.contains('巡查') ||
        normalized.contains('荣誉')) {
      return const _BadgeStyle(
        foreground: Color(0xFF6F35A5),
        background: Color(0xFFEEDCFF),
      );
    }

    final match = RegExp(
      r'lv\.?\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(normalized);
    final level = int.tryParse(match?.group(1) ?? '');

    if (level != null) {
      if (level >= 6) {
        return const _BadgeStyle(
          foreground: Color(0xFF8A4B00),
          background: Color(0xFFFFDDB5),
        );
      }
      if (level >= 4) {
        return const _BadgeStyle(
          foreground: Color(0xFF005FAF),
          background: Color(0xFFD7E9FF),
        );
      }
      if (level >= 2) {
        return const _BadgeStyle(
          foreground: Color(0xFF006A60),
          background: Color(0xFFBCECE3),
        );
      }
      return const _BadgeStyle(
        foreground: Color(0xFF3F5F00),
        background: Color(0xFFD8F2A4),
      );
    }

    if (normalized.contains('博士') ||
        normalized.contains('硕士') ||
        normalized.contains('专家')) {
      return const _BadgeStyle(
        foreground: Color(0xFF8A4B00),
        background: Color(0xFFFFDDB5),
      );
    }

    if (normalized.contains('大学') || normalized.contains('高中')) {
      return const _BadgeStyle(
        foreground: Color(0xFF005FAF),
        background: Color(0xFFD7E9FF),
      );
    }

    return _BadgeStyle(
      foreground: colors.onSecondaryContainer,
      background: colors.secondaryContainer,
    );
  }
}

class _BadgeStyle {
  final Color foreground;
  final Color background;

  const _BadgeStyle({
    required this.foreground,
    required this.background,
  });
}
