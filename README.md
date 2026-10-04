# MT论坛 Flutter 客户端

MT管理器论坛 (bbs.binmt.cc) 第三方客户端，基于 Flutter + Material Design 3。

## 快速开始

```bash
flutter pub get
flutter run
```

## 编译 APK

```bash
flutter build apk --release
```

> Release 签名读取仓库根目录的 `key.properties`。该文件**不应提交到仓库**。
> 构建环境没有正式 keystore 时，`android/app/build.gradle.kts` 会回落到
> debug 签名并打印警告，构建不会失败——但这种包只能用于本地验证，
> **不能用于正式发布**。

## 发布新版本

1. 改 `pubspec.yaml` 的 `version:`（如 `2.47.8+169`）；
2. 在 `CHANGELOG.md` 里写一节 `## v2.47.8`，**每条一行、不带 `-`/`1.` 前缀**
   （App 内更新弹窗会自己加序号）；
3. 构建 APK；
4. 生成 `update.json` 并上传到 `https://loveqin.fun/Mt/update.json`：

```bash
python3 tools/make_update_json.py build/app/outputs/flutter-apk/app-release.apk -o update.json
```

脚本会自动带上 `version` / `versionCode` / `changelog` / `downloadUrl` /
`sha256` / `size`，并校验两件最容易出错的事：**APK 的 versionName 是否等于
pubspec 版本号**、**是否误用了 debug 签名**。任一不通过会返回非 0 退出码。

## 文档

- [开发进度](开发进度.md) - 功能清单、已知问题、代码结构
- [接口文档](binmt_api_doc.md) - 34个论坛API接口完整说明

## 技术栈

- Flutter 3.27.0 + Dart 3.6.0
- Material Design 3（`lib/core/theme/`，中性灰 + 单一低饱和强调色，自动深浅色）
- Dio (HTTP) + CookieJar（核心登录态 / 防护 Cookie 分流）
- html (HTML解析)
- photo_view (图片缩放)
- cached_network_image (图片缓存)
- Android 原生不可见 WebView（无感人机验证）

## 目录结构

```
lib/
  core/            主题 token、网络层、无感验证、工具、通用组件
    theme/         ColorScheme / Typography / Spacing / Radius / Motion
    network/       HttpClient 工厂、Cookie 管理
      waf/         拦截页识别、验证守门器、不可见 WebView 桥、重放拦截器
  features/<域>/   auth forum thread messages profile social mall
    data/          该域的网络调用（api_service 的 part）
    models/        该域的模型（models.dart 的 part）
    widgets/       该域的页面部件
  data/parsers/    HTML 解析器（forum_parser / user_center_parser 的 part）
  pages/           页面入口（部分为兼容转发）
  services/        ApiService 门面 + 业务服务
```
