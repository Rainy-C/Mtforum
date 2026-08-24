import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/smiley_catalog.dart';

/// 发帖前的本地 BBCode 预览。
///
/// 预览不请求论坛，也不会修改原文；它只按论坛常用标签做容错解析，
/// 尤其用于在提交前检查代码块、引用、图片和嵌套文字样式。
class BbCodePreview extends StatelessWidget {
  final String subject;
  final String bbcode;
  final Map<String, String> attachmentUrls;

  const BbCodePreview({
    super.key,
    required this.subject,
    required this.bbcode,
    this.attachmentUrls = const {},
  });

  @override
  Widget build(BuildContext context) {
    final nodes = _BbParser().parse(bbcode);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          if (subject.trim().isNotEmpty) ...[
            Text(
              subject.trim(),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Divider(color: colors.outlineVariant),
            const SizedBox(height: 8),
          ],
          _BbNodeView(
            nodes: nodes,
            attachmentUrls: attachmentUrls,
          ),
        ],
      ),
    );
  }
}

class _BbNode {
  final String tag;
  final String parameter;
  final String text;
  final List<_BbNode> children;

  _BbNode(
    this.tag, {
    this.parameter = '',
    this.text = '',
    List<_BbNode>? children,
  }) : children = children ?? [];
}

class _BbParser {
  static const _knownTags = <String>{
    'b', 'i', 'u', 's', 'strike', 'color', 'size', 'font', 'backcolor',
    'url', 'email', 'img', 'attach', 'attachimg', 'audio', 'media', 'flash',
    'quote', 'code', 'free', 'hide', 'align', 'list', 'hr', '*',
  };

  final _token = RegExp(
    r'\[(/?)([a-z*]+)(?:=([^\]]*))?\]',
    caseSensitive: false,
  );

  List<_BbNode> parse(String raw) {
    final root = _BbNode('root');
    final stack = <_BbNode>[root];
    var cursor = 0;

    void addText(String value) {
      if (value.isNotEmpty) stack.last.children.add(_BbNode('#text', text: value));
    }

    while (cursor < raw.length) {
      final relative = _token.firstMatch(raw.substring(cursor));
      if (relative == null) {
        addText(raw.substring(cursor));
        break;
      }

      final start = cursor + relative.start;
      final end = cursor + relative.end;
      addText(raw.substring(cursor, start));

      final closing = relative.group(1) == '/';
      final tag = (relative.group(2) ?? '').toLowerCase();
      final parameter = (relative.group(3) ?? '').trim();
      final literal = raw.substring(start, end);

      if (!_knownTags.contains(tag)) {
        addText(literal);
        cursor = end;
        continue;
      }

      if (closing) {
        final index = stack.lastIndexWhere((node) => node.tag == tag);
        if (index <= 0) {
          addText(literal);
        } else {
          stack.removeRange(index, stack.length);
        }
        cursor = end;
        continue;
      }

      if (tag == 'hr' || tag == '*') {
        stack.last.children.add(_BbNode(tag, parameter: parameter));
        cursor = end;
        continue;
      }

      if (tag == 'code') {
        final close = RegExp(r'\[/code\]', caseSensitive: false)
            .firstMatch(raw.substring(end));
        final closeStart = close == null ? raw.length : end + close.start;
        stack.last.children.add(
          _BbNode('code', text: raw.substring(end, closeStart)),
        );
        cursor = close == null ? raw.length : end + close.end;
        continue;
      }

      final node = _BbNode(tag, parameter: parameter);
      stack.last.children.add(node);
      stack.add(node);
      cursor = end;
    }
    return root.children;
  }
}

class _BbNodeView extends StatelessWidget {
  final List<_BbNode> nodes;
  final Map<String, String> attachmentUrls;

  const _BbNodeView({required this.nodes, required this.attachmentUrls});

  bool _isBlock(_BbNode node) {
    const blockTags = <String>{
      'img', 'attach', 'attachimg', 'audio', 'media', 'flash', 'quote',
      'code', 'free', 'hide', 'align', 'list', 'hr',
    };
    return blockTags.contains(node.tag) || node.children.any(_isBlock);
  }

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    final inline = <_BbNode>[];

    void flushInline() {
      if (inline.isEmpty) return;
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
              children: [for (final node in inline) _inlineSpan(context, node)],
            ),
          ),
        ),
      );
      inline.clear();
    }

    for (final node in nodes) {
      if (_isBlock(node)) {
        flushInline();
        widgets.add(_buildBlock(context, node));
      } else {
        inline.add(node);
      }
    }
    flushInline();

    if (widgets.isEmpty) {
      return Text(
        '暂无可预览内容',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  InlineSpan _inlineSpan(BuildContext context, _BbNode node) {
    if (node.tag == '#text') return TextSpan(text: node.text);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    var style = const TextStyle();

    switch (node.tag) {
      case 'b':
        style = style.copyWith(fontWeight: FontWeight.w800);
        break;
      case 'i':
        style = style.copyWith(fontStyle: FontStyle.italic);
        break;
      case 'u':
        style = style.copyWith(decoration: TextDecoration.underline);
        break;
      case 's':
      case 'strike':
        style = style.copyWith(decoration: TextDecoration.lineThrough);
        break;
      case 'color':
        style = style.copyWith(color: _parseColor(node.parameter));
        break;
      case 'backcolor':
        style = style.copyWith(backgroundColor: _parseColor(node.parameter));
        break;
      case 'font':
        style = style.copyWith(fontFamily: node.parameter);
        break;
      case 'size':
        style = style.copyWith(
          fontSize: 16 * _sizeScale(node.parameter),
        );
        break;
      case 'url':
      case 'email':
        style = style.copyWith(
          color: colors.primary,
          decoration: TextDecoration.underline,
          decorationColor: colors.primary,
        );
        break;
    }

    return TextSpan(
      style: style,
      children: [for (final child in node.children) _inlineSpan(context, child)],
    );
  }

  Widget _buildBlock(BuildContext context, _BbNode node) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    switch (node.tag) {
      case 'code':
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              node.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ),
        );
      case 'quote':
        return _panel(
          context,
          node,
          color: colors.surfaceContainerHighest,
          icon: Icons.format_quote_rounded,
        );
      case 'free':
        return _panel(
          context,
          node,
          color: colors.secondaryContainer.withValues(alpha: 0.45),
          icon: Icons.info_outline_rounded,
        );
      case 'hide':
        return _panel(
          context,
          node,
          color: colors.tertiaryContainer.withValues(alpha: 0.45),
          icon: Icons.visibility_off_outlined,
          title: '隐藏内容',
        );
      case 'img':
        return _image(context, _plainText(node));
      case 'attachimg':
        final aid = _plainText(node).trim();
        final url = attachmentUrls[aid];
        return url == null
            ? _mediaCard(context, Icons.image_outlined, '图片附件 $aid')
            : _image(context, url);
      case 'attach':
        return _mediaCard(
          context,
          Icons.attach_file_rounded,
          '附件 ${_plainText(node).trim()}',
        );
      case 'audio':
        return _mediaCard(
          context,
          Icons.audiotrack_rounded,
          _plainText(node).trim(),
          title: '音频',
        );
      case 'media':
        return _mediaCard(
          context,
          Icons.play_circle_outline_rounded,
          _plainText(node).trim(),
          title: '视频',
        );
      case 'flash':
        return _mediaCard(
          context,
          Icons.extension_off_outlined,
          _plainText(node).trim(),
          title: 'Flash',
        );
      case 'hr':
        return Divider(height: 24, color: colors.outlineVariant);
      case 'align':
        final alignment = switch (node.parameter.toLowerCase()) {
          'center' => Alignment.center,
          'right' => Alignment.centerRight,
          _ => Alignment.centerLeft,
        };
        return Align(
          alignment: alignment,
          child: _BbNodeView(
            nodes: node.children,
            attachmentUrls: attachmentUrls,
          ),
        );
      case 'list':
        return _buildList(context, node);
      case 'url':
        final image = _findFirst(node, 'img');
        if (image != null) {
          return GestureDetector(
            onTap: () => _open(node.parameter),
            child: _image(context, _plainText(image)),
          );
        }
        return _BbNodeView(nodes: node.children, attachmentUrls: attachmentUrls);
      default:
        return _BbNodeView(nodes: node.children, attachmentUrls: attachmentUrls);
    }
  }

  Widget _panel(
    BuildContext context,
    _BbNode node, {
    required Color color,
    required IconData icon,
    String? title,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: colors.primary, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                ],
                _BbNodeView(nodes: node.children, attachmentUrls: attachmentUrls),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _image(BuildContext context, String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return _mediaCard(context, Icons.broken_image_outlined, '图片地址为空');
    final smiley = SmileyCatalog.isForumSmileyUrl(url);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(smiley ? 4 : 12),
        child: CachedNetworkImage(
          imageUrl: url,
          width: smiley ? 32 : null,
          height: smiley ? 32 : null,
          fit: smiley ? BoxFit.contain : BoxFit.fitWidth,
          placeholder: (_, __) => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (_, __, ___) => _mediaCard(
            context,
            Icons.broken_image_outlined,
            url,
            title: '图片加载失败',
          ),
        ),
      ),
    );
  }

  Widget _mediaCard(
    BuildContext context,
    IconData icon,
    String subtitle, {
    String title = '内容预览',
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildList(BuildContext context, _BbNode node) {
    final groups = <List<_BbNode>>[];
    var current = <_BbNode>[];
    for (final child in node.children) {
      if (child.tag == '*') {
        if (current.isNotEmpty) groups.add(current);
        current = <_BbNode>[];
      } else {
        current.add(child);
      }
    }
    if (current.isNotEmpty) groups.add(current);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          for (var index = 0; index < groups.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      node.parameter.isEmpty ? '•' : '${index + 1}.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: _BbNodeView(
                      nodes: groups[index],
                      attachmentUrls: attachmentUrls,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _plainText(_BbNode node) {
    if (node.tag == '#text') return node.text;
    return node.children.map(_plainText).join();
  }

  _BbNode? _findFirst(_BbNode node, String tag) {
    if (node.tag == tag) return node;
    for (final child in node.children) {
      final found = _findFirst(child, tag);
      if (found != null) return found;
    }
    return null;
  }

  Future<void> _open(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  double _sizeScale(String raw) {
    final numeric = int.tryParse(raw.trim());
    if (numeric != null) {
      return switch (numeric.clamp(1, 7)) {
        1 => 0.72,
        2 => 0.82,
        3 => 0.92,
        4 => 1.0,
        5 => 1.18,
        6 => 1.36,
        _ => 1.58,
      };
    }
    final px = double.tryParse(
      RegExp(r'[\d.]+').firstMatch(raw)?.group(0) ?? '',
    );
    return px == null ? 1.0 : (px / 16).clamp(0.65, 2.2).toDouble();
  }

  Color? _parseColor(String raw) {
    var value = raw.trim().toLowerCase();
    const named = <String, Color>{
      'black': Colors.black,
      'white': Colors.white,
      'red': Colors.red,
      'green': Colors.green,
      'blue': Colors.blue,
      'yellow': Colors.yellow,
      'orange': Colors.orange,
      'purple': Colors.purple,
      'pink': Colors.pink,
      'grey': Colors.grey,
      'gray': Colors.grey,
      'cyan': Colors.cyan,
      'teal': Colors.teal,
    };
    if (named.containsKey(value)) return named[value];
    value = value.replaceFirst('#', '');
    if (value.length == 3 && RegExp(r'^[0-9a-f]{3}$').hasMatch(value)) {
      value = value.split('').map((part) => '$part$part').join();
    }
    if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(value)) return null;
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? null : Color(0xff000000 | parsed);
  }
}
