# MTForum 2.0.0+8 重构说明

本版本不再继续堆叠旧 ApiService 里的多套帖子解析器。

## 架构

- `lib/services/api_service.dart`
  - 只负责 HTTP、Cookie、登录态、回复/点赞/收藏等写操作。
- `lib/data/forum_parser.dart`
  - 只负责论坛 HTML/XML 解析。
  - 帖子详情严格按 `docs/MT请求响应参考.md`：`pid` 楼层 + `comiis_message_table` 正文。
  - 为规避移动模板非标准 HTML 被 parser 自动重排，先在原始 HTML 中按 pid 起点切楼层，再解析每个楼层片段。
- `lib/services/theme_service.dart`
  - 跟随系统 / 浅色 / 深色，SharedPreferences 持久化。
- `lib/services/update_service.dart`
  - 检查 update.json。
  - 通过 Android DownloadManager 在 App 内发起 APK 下载并展示进度。
- `android/.../MainActivity.kt`
  - 提供版本读取、下载状态、调用系统安装器。

## 关键行为

- Cookie 登录 UI 已移除。
- 账号密码登录成功后从 CookieJar 读取最终 auth/saltkey，不再解码 auth。
- formhash 不再使用任何硬编码值。
- 回复请求使用 `application/x-www-form-urlencoded`、Referer、AJAX 头。
- 搜索按 POST -> 302 searchid -> GET 结果页三步处理。
- 首页移除无真实接口依据的“热门/最新/精华”假 Tab。
- 帖子正文第一阶段统一稳定纯文本显示；正文图片单独渲染。后续富文本可在 parser 稳定后继续补。

## 发布版本

`2.0.0+8`

发布脚本应在 `flutter build apk` 追加：

```bash
--dart-define=MTFORUM_UPDATE_URL="$PUBLIC_BASE/Mt/update.json"
```
