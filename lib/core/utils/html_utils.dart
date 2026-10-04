import 'package:html/dom.dart' as dom;

/// HTML → 纯文本的共享工具。
///
/// 论坛源码里存在大量干扰字符：`&nbsp;`、零宽空格、双向文本标记、
/// 控制字符，以及克米模板私有区的字体图标。所有通过 `element.text`
/// 取值的地方都必须经过 [sanitize]，否则会出现"看不见但占位"的排版问题。
abstract final class HtmlText {
  static final RegExp _invisible =
      RegExp(r'[\u200b-\u200f\u2060-\u2064\ufeff]');
  static final RegExp _control =
      RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]');
  static final RegExp _privateUse = RegExp(r'[\ue000-\uf8ff]');
  static final RegExp _iconArtifacts = RegExp(r'[\uE000-\uF8FF\uFFFD\u25A1]');
  static final RegExp _whitespace = RegExp(r'\s+');

  /// 清洗文本：合并空白、去不可见字符、去图标字形。
  static String sanitize(String? text) {
    if (text == null || text.isEmpty) return '';
    return text
        .replaceAll('\u00a0', ' ')
        .replaceAll(_invisible, '')
        .replaceAll(_control, '')
        .replaceAll(_privateUse, '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  /// 清洗并剔除私有区图标字形（克米模板专用）。
  static String sanitizeAvatar(String? text) {
    if (text == null || text.isEmpty) return '';
    return text
        .replaceAll(_iconArtifacts, '')
        .replaceAll(_whitespace, ' ')
        .trim();
  }

  /// 把多行空白压成单个空格。
  static String inline(String? text) {
    if (text == null) return '';
    return sanitize(text.replaceAll(_whitespace, ' '));
  }

  /// 保留换行的清洗（用于正文）。
  static String multiline(String? text) {
    if (text == null) return '';
    return text
        .replaceAll('\u00a0', ' ')
        .replaceAll(_invisible, '')
        .replaceAll(_control, '')
        .replaceAll(_privateUse, '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  /// 提取元素纯净文本（先剔除 script/style）。
  static String textOf(dom.Element? el) {
    if (el == null) return '';
    final clone = el.clone(true);
    clone.querySelectorAll('script, style').forEach((e) => e.remove());
    return sanitize(clone.text);
  }

  /// 统计"可见文本"长度：剔除标签、脚本、样式后的字符数。
  ///
  /// 用于判断页面是否只是验证/跳转桩（内容极少）。
  static int visibleTextLength(String html) {
    final text = html
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(_whitespace, ' ');
    return text.trim().length;
  }

  /// 从页面 DOM 提取 Discuz 分页信息 `{currentPage, totalPages}`。
  static Map<String, int> extractPagination(dom.Document doc) {
    final select = doc.querySelector('.comiis_page select#dumppage');
    if (select != null) {
      final options = select.querySelectorAll('option');
      if (options.isNotEmpty) {
        final totalPages =
            int.tryParse(options.last.attributes['value'] ?? '1') ?? 1;
        var currentPage = 1;
        for (final opt in options) {
          if (opt.attributes['selected'] != null) {
            currentPage = int.tryParse(opt.attributes['value'] ?? '1') ?? 1;
            break;
          }
        }
        return {'currentPage': currentPage, 'totalPages': totalPages};
      }
    }

    final pgDiv = doc.querySelector('.pg');
    if (pgDiv != null) {
      final currentPage = int.tryParse(pgDiv.querySelector('strong')?.text.trim() ?? '') ?? 1;
      var totalPages = 1;
      final span = pgDiv.querySelector('span[title]');
      if (span != null) {
        final m = RegExp(r'共\s*(\d+)\s*页')
            .firstMatch(span.attributes['title'] ?? '');
        if (m != null) totalPages = int.tryParse(m.group(1)!) ?? 1;
      }
      if (totalPages <= 1) {
        final label = pgDiv.querySelector('label');
        if (label != null) {
          final m = RegExp(r'/\s*(\d+)\s*页').firstMatch(label.text);
          if (m != null) totalPages = int.tryParse(m.group(1)!) ?? 1;
        }
      }
      return {'currentPage': currentPage, 'totalPages': totalPages};
    }

    return extractPaginationFromLinks(doc);
  }

  /// 从 `<a>` 分页链接提取分页信息（兼容 `?page=N` 与 `thread-TID-PAGE-1.html`）。
  static Map<String, int> extractPaginationFromLinks(dom.Document doc) {
    const defaults = <String, int>{'currentPage': 1, 'totalPages': 1};
    final pageLinks = doc.querySelectorAll('a[href*="page="], a[href*="thread-"]');
    if (pageLinks.isEmpty) return defaults;

    var maxPage = 0;
    int? prevPage;
    int? nextPage;

    for (final a in pageLinks) {
      final href = a.attributes['href'] ?? '';
      final text = a.text.trim();
      int? p;
      final m1 = RegExp(r'[?&]page=(\d+)').firstMatch(href);
      if (m1 != null) {
        p = int.tryParse(m1.group(1)!);
      } else {
        final m2 = RegExp(r'thread-\d+-(\d+)-\d+\.html').firstMatch(href);
        if (m2 != null) p = int.tryParse(m2.group(1)!);
      }
      if (p == null || p <= 0) continue;
      if (p > maxPage) maxPage = p;
      if (text == '上一页' || text.contains('上页')) prevPage = p;
      if (text == '下一页' || text.contains('下页')) nextPage = p;
    }

    int currentPage;
    if (nextPage != null && nextPage > 0) {
      currentPage = nextPage - 1;
    } else if (prevPage != null && prevPage > 0) {
      currentPage = maxPage;
    } else {
      currentPage = 1;
    }

    final totalPages = currentPage < maxPage ? maxPage : currentPage;
    return {'currentPage': currentPage, 'totalPages': totalPages};
  }

  /// 从 Discuz 帖子 URL 提取 `{tid, page}`。
  static Map<String, int> parseThreadUrl(String url) {
    final m1 = RegExp(r'thread-(\d+)(?:-(\d+))?').firstMatch(url);
    if (m1 != null) {
      return {
        'tid': int.tryParse(m1.group(1)!) ?? 0,
        'page': int.tryParse(m1.group(2) ?? '') ?? 1,
      };
    }
    final tidMatch = RegExp(r'tid=(\d+)').firstMatch(url);
    if (tidMatch != null) {
      final pageMatch = RegExp(r'[?&]page=(\d+)').firstMatch(url);
      return {
        'tid': int.tryParse(tidMatch.group(1)!) ?? 0,
        'page': int.tryParse(pageMatch?.group(1) ?? '') ?? 1,
      };
    }
    return {'tid': 0, 'page': 1};
  }
}
