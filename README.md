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

## 文档

- [开发进度](开发进度.md) - 功能清单、已知问题、代码结构
- [接口文档](binmt_api_doc.md) - 34个论坛API接口完整说明

## 技术栈

- Flutter 3.27.0 + Dart 3.6.0
- Material Design 3 (ColorScheme.fromSeed)
- Dio (HTTP) + Cookie管理
- html (HTML解析)
- photo_view (图片缩放)
- cached_network_image (图片缓存)
