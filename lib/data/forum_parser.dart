import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../core/utils/html_utils.dart';
import '../core/utils/url_utils.dart';
import '../models/models.dart';
import 'smiley_catalog.dart';

part 'parsers/thread_list_parser.dart';
part 'parsers/thread_detail_parser.dart';
part 'parsers/post_content_parser.dart';
part 'parsers/editor_parser.dart';
part 'parsers/parser_utils.dart';

/// 论坛 HTML 解析器。
///
/// 核心原则：
/// 1. AJAX 响应先剥离 XML/CDATA。
/// 2. 帖子详情不依赖整页 DOM 的父子关系，因为移动模板可能包含非标准嵌套，
///    HTML5 parser 会自动修复 DOM，造成正文被移动到 pid 节点外。
/// 3. 详情页先在“原始 HTML 字符串”中按 pid 起点切楼层，再在每个楼层片段里
///    找 comiis_message_table。这样既遵循 MT 页面结构，又规避 DOM 修复问题。
class ForumParser {
  const ForumParser();
}

class _InlineStyle {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final String? color;
  final String? backgroundColor;
  final String? fontFamily;
  final double? fontSizeScale;

  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.color,
    this.backgroundColor,
    this.fontFamily,
    this.fontSizeScale,
  });

  _InlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    String? color,
    String? backgroundColor,
    String? fontFamily,
    double? fontSizeScale,
  }) {
    return _InlineStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSizeScale: fontSizeScale ?? this.fontSizeScale,
    );
  }
}

class _ReplyRelation {
  final String? pid;
  final String? name;
  final String? time;
  final String? quotedText;

  const _ReplyRelation({
    this.pid,
    this.name,
    this.time,
    this.quotedText,
  });
}

class _ParsedMessage {
  final String text;
  final String? hiddenHint;
  final String? lastEditTime;
  final String? lastEditor;
  final List<String> images;
  final List<PostContent> contents;

  const _ParsedMessage({
    required this.text,
    this.hiddenHint,
    this.lastEditTime,
    this.lastEditor,
    this.images = const [],
    this.contents = const [],
  });
}
