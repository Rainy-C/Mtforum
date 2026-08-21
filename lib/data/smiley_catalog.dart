class SmileyPack {
  final String id;
  final String title;
  final List<String> urls;

  const SmileyPack({
    required this.id,
    required this.title,
    required this.urls,
  });
}

class SmileyCatalog {
  const SmileyCatalog._();

  static const String baseUrl =
      'https://cdn-bbs.mt2.cn/static/image/smiley';

  static const Set<int> qqMissing = {
    62,
    93,
    94,
    95,
    96,
  };

  static final List<String> qq = List<String>.unmodifiable([
    for (var i = 1; i <= 107; i++)
      if (!qqMissing.contains(i))
        '$baseUrl/qq/qq${i.toString().padLeft(3, '0')}.gif',
  ]);

  static final List<String> comcom = List<String>.unmodifiable([
    for (var i = 1; i <= 30; i++) '$baseUrl/comcom/$i.gif',
  ]);

  static final List<SmileyPack> packs = List<SmileyPack>.unmodifiable([
    SmileyPack(
      id: 'qq',
      title: 'QQ',
      urls: qq,
    ),
    SmileyPack(
      id: 'comcom',
      title: 'COMCOM',
      urls: comcom,
    ),
  ]);

  // 回复编辑器内部使用私有区单字符代表一个论坛 GIF 表情。
  // 用户看不到 URL；发送前才转换为论坛需要的 [img]...[/img]。
  static const int _markerBase = 0xE000;

  static final List<String> allUrls = List<String>.unmodifiable([
    ...qq,
    ...comcom,
  ]);

  static String? markerForUrl(String url) {
    final index = allUrls.indexOf(url);
    if (index < 0) {
      return null;
    }
    return String.fromCharCode(_markerBase + index);
  }

  static String? urlForCodeUnit(int codeUnit) {
    final index = codeUnit - _markerBase;
    if (index < 0 || index >= allUrls.length) {
      return null;
    }
    return allUrls[index];
  }

  static bool isMarkerCodeUnit(int codeUnit) =>
      urlForCodeUnit(codeUnit) != null;

  static String fromForumBbCode(String value) {
    return value.replaceAllMapped(
      RegExp(r'\[img\](https?://[^\[]+)\[/img\]', caseSensitive: false),
      (match) {
        final url = match.group(1)?.trim() ?? '';
        return markerForUrl(url) ?? match.group(0)!;
      },
    );
  }

  static String toForumBbCode(String value) {
    final out = StringBuffer();

    for (final codeUnit in value.codeUnits) {
      final url = urlForCodeUnit(codeUnit);
      if (url == null) {
        out.writeCharCode(codeUnit);
      } else {
        out.write('[img]$url[/img]');
      }
    }

    return out.toString();
  }
}
