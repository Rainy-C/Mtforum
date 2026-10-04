part of '../forum_parser.dart';

extension ForumParserParserUtilsPart on ForumParser {
  String _cleanInline(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD\u25A1]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cleanMultiline(String value) {
    return _normalizeMultiline(value).trim();
  }

  String _normalizeMultiline(String value) {
    final text = value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\u00a0', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    final lines = text
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trimRight())
        .toList();

    // 连续换行来自用户正文中的多个 <br>，必须原样保留；调用方根据
    // 场景决定是否裁剪首尾。富文本节点边界不能裁剪。
    return lines.join('\n');
  }

  String? _nullableText(String? value) {
    if (value == null) return null;
    final cleaned = _cleanInline(value);
    return cleaned.isEmpty ? null : cleaned;
  }

  String? _cleanThreadExcerpt(String? value) {
    if (value == null) return null;

    var cleaned = _cleanInline(value);
    // 列表已经通过 hasHiddenContent 显示“隐藏”标记，摘要中继续显示
    // Discuz/Comiis 的隐藏占位提示只会重复占空间并影响阅读。这里只
    // 过滤模板提示，不尝试恢复或泄露真正的隐藏正文。
    cleaned = cleaned
        .replaceAll(
          RegExp(r'[*＊\s]*本(?:帖)?内容被作者隐藏[*＊\s]*'),
          ' ',
        )
        .replaceAll(
          RegExp(r'[*＊\s]*本帖隐藏的内容\s*[:：]?[*＊\s]*'),
          ' ',
        )
        .replaceAll(
          RegExp(r'[*＊\s]*(?:回复后可见|回复可见|查看隐藏内容)[*＊\s]*'),
          ' ',
        );
    cleaned = _cleanInline(cleaned);
    return cleaned.isEmpty ? null : cleaned;
  }

  /// 从 `<img>` 元素取出**真实**图片地址（未做绝对化）。
  ///
  /// 属性优先级：`zoomfile → file → comiis_loadimages → data-original →
  /// data-src → data-lazy-src → src`。
  ///
  /// 为什么必须带 `comiis_loadimages`：克米移动模板（2026-10 起）把帖子图片
  /// 改成懒加载 —— `src` 指向占位图 `none.png`，真实地址放在私有属性
  /// `comiis_loadimages` 上，由站点 JS 回填到 `src`。HTML 解析器不执行 JS，
  /// 只读 `src` 就会把占位图当成正文图片，表现为"帖子图片全都不显示"。
  ///
  /// 站点模板同时会把 `og:image` 输出成 `https://bbs.binmt.cc/https://oos.binmt.cc/...`
  /// 这种双重前缀，这里不处理，交由 [AppUrl.resolve] 修复。
  String? _imageSourceOf(html_dom.Element? element) {
    if (element == null) return null;
    for (final key in const [
      'zoomfile',
      'file',
      'comiis_loadimages',
      'data-original',
      'data-src',
      'data-lazy-src',
      'src',
    ]) {
      final value = element.attributes[key]?.trim();
      if (value == null || value.isEmpty) continue;
      if (_isPlaceholderImage(value)) continue;
      return value;
    }
    return null;
  }

  /// 站点模板的懒加载占位图，不能当作正文图片。
  bool _isPlaceholderImage(String url) {
    final lower = url.toLowerCase();
    return lower.contains('imageloading.gif') ||
        lower.contains('comiis_loadimg.gif') ||
        lower.endsWith('/none.png') ||
        lower.endsWith('/none.gif') ||
        lower.contains('/pic/none.');
  }

  /// 统一走 [AppUrl.resolve]（含"裸域名补 https"的论坛正文外链规则）。
  String? _absoluteUrl(String? raw, String baseUrl) =>
      AppUrl.resolve(raw, baseUrl, promoteBareDomain: true);
}
