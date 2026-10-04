/// Dio `RequestOptions.extra` 中用于无感验证协同的标记位。
///
/// 单独放在一个文件里，避免 [WafInterceptor] 与 [VerificationGate] 互相 import
/// 造成的循环依赖，也避免同一个字符串字面量散落多处。
abstract final class WafFlags {
  /// 该请求的拦截页已被处理过（验证完成后重放时写入）。
  /// 用于阻止"重放 → 再次判定拦截 → 再次验证"的死循环。
  static const String handled = 'mtforum.waf.handled';

  /// 该请求是验证探测请求，永远不触发人机验证。
  static const String probe = 'mtforum.waf.probe';
}
