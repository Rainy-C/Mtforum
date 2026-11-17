# MtForum 版本与发布规则

每次向用户交付新的 APK，都应先增加 `app/build.gradle.kts` 的 `versionCode`，且 `versionName` 必须体现对应变更，避免更新检测把新构建当作旧版本。

- 修复缺陷、调整 Compose 界面、不兼容变更较少：增加补丁号（例如 0.3.5 → 0.3.6）。
- 增加较完整的新功能或模块：增加次版本号（例如 0.3.6 → 0.4.0）。
- 不兼容的核心架构更新：经过评估后增加主版本号。
- 每次交付 APK 必须增加 `versionCode`，不能重用旧版本代码。
- 单纯运行内部验证编译、不交付新 APK 时，可以复用同一版本，确保可复现。
- 修改版本时同步更新 `.github/release-notes.txt` 首行 `version_name=` 和变更说明。
- GitHub 主分支 `app/build.gradle.kts` 发生更新时，Release 工作流会尝试使用 CI 已配置的签名密钥构建正式 APK。
- `update.json` 必须从最终实际发布的已签名 APK 计算大小与 SHA-256，不允许复制旧版本数值或填写虚构的下载地址。
- 本地 `-PallowDebugSigning` 仅用于测试；Debug 签名的 APK 不可作为稳定渠道更新包发布。
