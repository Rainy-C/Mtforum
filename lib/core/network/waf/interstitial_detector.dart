import '../../utils/html_utils.dart';

/// 通用「拦截页」识别器（人机验证 / WAF / 跳转桩）。
///
/// **刻意不做厂商适配**：不认 `acw_sc__v2`、不认 "Aliyun"、不认 "ESA"。
/// 只判断"结构"——真实 Discuz 页面必然有 `<body>`，且必然带论坛骨架痕迹
/// （`discuz` / `formhash` / `comiis` / `#ct` / `#hd` / `#ft` / `#postlist` /
/// `#thread_subject`）。因此任何新出现的验证页，只要它同样"不是一个能用的
/// 论坛页"，就会被命中，无需逐家适配。
///
/// 三道门槛用于排除误判：
/// 1. `content-type` 必须含 `text/html`（JSON / 图片接口天然排除）；
/// 2. 必须含 `<html`（Discuz `inajax=1` 的 XML/CDATA 包装天然排除）；
/// 3. 体积必须小于 [maxBodyLength]（真实帖子页实测 ~160KB）。
///
/// 判定必须"宁可判成论坛页"：把正常页误判成拦截页会平白触发一次后台验证，
/// 而漏判只是回到既有的"页面结构可能已变更"提示。
abstract final class InterstitialDetector {
  /// 判定上限：真实 Discuz 页面远大于此，验证/跳转桩通常在几 KB 量级。
  static const int maxBodyLength = 64 * 1024;

  /// 带 `<body>` 的页面，可见文本低于此值才可能是拦截页。
  static const int minVisibleTextForBodyPage = 256;

  static final RegExp _skeletonId = RegExp(
    r'''id\s*=\s*["']?(ct|hd|ft|postlist|thread_subject)\b''',
  );

  /// Content-Type 是否是 HTML 文档。
  ///
  /// 只对 HTML 文档做拦截判定：`text/html` 才算，`text/xml`（Discuz ajax）、
  /// `application/json`（接口）一律跳过。
  static bool isHtmlDocument(String? contentType) {
    final ct = (contentType ?? '').toLowerCase();
    if (ct.isEmpty) return false;
    return ct.contains('text/html') || ct.contains('application/xhtml');
  }

  /// 响应体是否"不是一个能用的论坛页"。
  static bool looksLikeInterstitialPage(String body, String? contentType) {
    if (body.isEmpty) return false;
    if (!isHtmlDocument(contentType)) return false;
    if (body.length > maxBodyLength) return false;

    final lower = body.toLowerCase();
    if (!lower.contains('<html')) return false;

    // 无 `<body>` 的完整文档：脚本挑战 / 跳转桩（阿里云 ESA JS 挑战即此类，
    // 实测样本 `<html><script>var arg1='…'`，4321 字节、无 body、无 DOCTYPE）。
    if (!lower.contains('<body')) {
      return lower.contains('<script') || lower.contains('<meta');
    }

    // 有 `<body>` 但完全没有论坛骨架、且正文极少 → 拦截页。
    if (hasForumSkeleton(lower)) return false;
    return HtmlText.visibleTextLength(body) < minVisibleTextForBodyPage;
  }

  /// 论坛页骨架痕迹：任一命中即认为"这是论坛页"。
  ///
  /// 这些是 Discuz 的全局骨架（跨模板、跨页面稳定），比 `#postlist` 这类
  /// 页面级选择器更通用：列表页、空间页、消息页同样命中。
  static bool hasForumSkeleton(String lowerBody) {
    if (lowerBody.contains('discuz') ||
        lowerBody.contains('formhash') ||
        lowerBody.contains('comiis')) {
      return true;
    }
    return _skeletonId.hasMatch(lowerBody);
  }

  /// 判断一个页面是否"确实拿到了论坛页"。验证成功的唯一权威判据。
  static bool isUsableForumPage(String body, String? contentType) {
    if (body.isEmpty) return false;
    if (looksLikeInterstitialPage(body, contentType)) return false;
    return true;
  }
}
