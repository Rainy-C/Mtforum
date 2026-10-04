import 'dart:io' show Cookie;

/// Cookie 分类与转换桥。
///
/// 两类 Cookie 必须严格区分：
/// - **核心登录态**：Discuz 的 `{cookiepre}auth` / `{cookiepre}saltkey` / `sid`
///   —— 属于账号，需要持久化、需要注入验证页、绝不能扩散到其他账号；
/// - **客户端防护 Cookie**：`acw_sc__v2` / `acw_tc` 等 —— 属于"这台客户端 + 这个
///   出口 IP"，与账号无关。它们**不能**写进账号登录态，否则会被启动/切号/
///   导入导出反复"复活"成过期值，形成"每次冷启动都要验证"的死锁。
abstract final class CookieClassifier {
  /// 已知的防护 / CDN Cookie 名称与前缀。
  ///
  /// 只做"清理"用，绝不做"判定验证是否通过"用——通过与否只看能否拿到论坛页。
  static const Set<String> wafCookieNames = {
    'acw_sc__v2',
    'acw_tc',
    'cdn_sec_tc',
    'sec_tc',
    'aliyungf_tc',
    'ssxmod_itna',
    'ssxmod_itna2',
  };

  static const List<String> wafCookiePrefixes = [
    'acw_',
    'acwsc_',
    'aliyungf_',
    'ssxmod_',
    '__cdn',
  ];

  /// 是否是客户端防护 Cookie（人机验证 / 防火墙下发）。
  static bool isWafCookie(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return false;
    if (wafCookieNames.contains(n)) return true;
    for (final prefix in wafCookiePrefixes) {
      if (n.startsWith(prefix)) return true;
    }
    return false;
  }

  /// 从 cookie 名列表推断站点核心 cookie 前缀（Discuz 的 `cookiepre`）。
  ///
  /// ① 有 `{prefix}auth` 时以它为准（Discuz 用它判定是否登录）；
  /// ② 否则统计出现 ≥2 次的"下划线前缀"，取最多的；
  /// ③ 都推不出返回空串，此时 [isCoreCookie] 不过滤（保持旧行为）。
  static String inferCookiePrefix(Iterable<String> names) {
    final list = names.where((n) => n.isNotEmpty).toList();
    const authSuffix = 'auth';
    for (final n in list) {
      if (n.length > authSuffix.length && n.endsWith(authSuffix)) {
        return n.substring(0, n.length - authSuffix.length);
      }
    }

    final counts = <String, int>{};
    for (final n in list) {
      final i = n.lastIndexOf('_');
      if (i <= 0) continue;
      final p = n.substring(0, i + 1);
      counts[p] = (counts[p] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    return best.value >= 2 ? best.key : '';
  }

  /// 是否核心 Cookie。`prefix` 为空表示未识别出前缀，一律视为核心。
  static bool isCoreCookie(String name, String prefix) {
    if (isWafCookie(name)) return false;
    return prefix.isEmpty || name.startsWith(prefix);
  }

  /// 解析 `name=value; name2=value2` 形式的 cookie 串。
  static List<({String name, String value})> parseCookieString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final out = <({String name, String value})>[];
    for (final pair in raw.split(';')) {
      final trimmed = pair.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final name = trimmed.substring(0, eq).trim();
      final value = trimmed.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      out.add((name: name, value: value));
    }
    return out;
  }

  /// 只保留核心登录 Cookie 的 cookie 串（用于持久化与注入验证页）。
  ///
  /// 防护 Cookie 会被剔除——把手里那条旧值灌回验证页，只会让挑战继续基于
  /// 旧值进行。
  static String coreCookiesOf(String? cookieStr) {
    final pairs = parseCookieString(cookieStr);
    if (pairs.isEmpty) return cookieStr ?? '';
    final prefix = inferCookiePrefix(pairs.map((p) => p.name));
    final kept = pairs
        .where((p) => isCoreCookie(p.name, prefix))
        .map((p) => '${p.name}=${p.value}')
        .toList();
    if (kept.isEmpty) return '';
    return kept.join('; ');
  }

  /// 只保留防护 Cookie（用于状态展示 / 调试，不参与登录态）。
  static String wafCookiesOf(String? cookieStr) {
    final pairs = parseCookieString(cookieStr);
    return pairs
        .where((p) => isWafCookie(p.name))
        .map((p) => '${p.name}=${p.value}')
        .join('; ');
  }

  /// `dart:io` Cookie → `name=value` 映射（同名后者覆盖前者）。
  static Map<String, String> toNameValueMap(Iterable<Cookie> cookies) {
    final out = <String, String>{};
    for (final c in cookies) {
      if (c.name.isEmpty) continue;
      out[c.name] = c.value;
    }
    return out;
  }
}
