/// URL 归一化工具。
///
/// 论坛 HTML 里的链接写法极不统一（`//cdn.x/y`、`/thread-1-1-1.html`、
/// `thread-1-1-1.html`、裸域名 `www.x.com/a.png`）。三个解析器此前各写了一份
/// `_absoluteUrl`，行为还有细微差别，这里收敛为唯一的实现。
abstract final class AppUrl {
  static final RegExp _scheme = RegExp(r'^https?://', caseSensitive: false);
  static final RegExp _bareDomain = RegExp(
    r'^(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?::\d+)?(?:/|$)',
    caseSensitive: false,
  );

  /// 把 [raw] 归一化为绝对 URL；无法判定时返回 null。
  ///
  /// - [promoteBareDomain]：把 `www.a.com/x.png` 这类裸域名补成 `https://`。
  ///   论坛正文里的外链图片经常省略协议，需要它；接口返回的路径不需要。
  /// - [resolveRelative]：使用 `Uri.resolve` 处理 `../` 等相对路径。
  ///   克米模板的部分链接带 `./` 前缀。
  static String? resolve(
    String? raw,
    String baseUrl, {
    bool promoteBareDomain = false,
    bool resolveRelative = false,
  }) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;

    if (value.startsWith('//')) return 'https:$value';
    if (_scheme.hasMatch(value)) return value;

    if (promoteBareDomain &&
        (value.toLowerCase().startsWith('www.') ||
            _bareDomain.hasMatch(value))) {
      return 'https://$value';
    }

    if (resolveRelative) {
      final parsed = Uri.tryParse(value);
      if (parsed != null && parsed.hasScheme) return value;
      final base = Uri.tryParse(baseUrl);
      if (base != null) return base.resolve(value).toString();
    }

    if (value.startsWith('/')) return '$baseUrl$value';
    return '$baseUrl/$value';
  }

  /// 判断是否是可以直接用浏览器打开的绝对 http(s) 链接。
  static bool isHttp(String? url) =>
      url != null && _scheme.hasMatch(url.trim());

  /// 判断是否是可缓存的远程图片。
  static bool isNetworkImage(String? url) => isHttp(url);
}
