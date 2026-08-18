# 全量 `lib/main.dart` HAP 差异表（2026-08-18 实测）

对照 Android SiteMark v1.0.8。本表只写**已量到的事实**，不写愿望。

引擎：`tool/ohos/engine_status.md` = **degraded**。

| 能力 | 模拟器现状 | 能否对外宣称 | 备注 |
|---|---|---|---|
| 全量 Dart 入口 | 已进 HAP | 可写「模拟器已跑 `lib/main.dart`」 | `--target lib/main.dart --dart-define=SITEMARK_OHOS=true` |
| 隐私门 | 已过 | 可 | `FilePrivacyConsentStore` + 桥接 `path_provider` |
| 首页（工程印记 / 项目 / 全部记录 / 设置） | 已看到 | 可写「空项目首页」 | dump 无审查壳文案 |
| Drift / 应用文档目录 | 首页已起来，推断可写 | 不单独宣称持久化对等 | 依赖 `filesDir` |
| 水印 Rust | 未编 `ohos-arm64` | **否** | 降级管线 |
| 系统相机 | 未测 | **否** | 模拟器 x86_64；Want 已能编译 |
| 定位 | 未测 | **否** | |
| 相册 ACL `READ/WRITE_IMAGEVIDEO` | 未测 | **否** | 无真机 / 无 AGC |
| picker / 沙箱托底 | 代码在，未走 | **否** | |
| WorkManager | ohos 走应用内串行队列 | 写差异，不假装 WorkManager | `InAppSerialBackgroundWorkClient` |
| 本地通知 | Android 插件，ohos 未桥 | **否** | 需 no-op 或自建 |
| `share_plus` | 未桥 | **否** | |
| `package_info_plus` | 未桥 | **否** | 关于页可能缺版本 |
| `dynamic_color` | 未证 | **否** | 可走默认主题 |
| `file_picker` | 钉 `12.0.0-beta.7`；未走导入 | **否** | 12.0.0 破坏 `.files` |
| AutoFill | API 24 编译桩 | **否** | 只为过编 |
| 签名 release | 无 | **否** | 未签名 debug 可装模拟器 |
| 应用市场上架 | 无 | **否** | |

官方测试：契约测试已绿；全量套件在改回 `RustLib.init()` 前是 `+1013 -1`。提交前应用官方 Flutter 复跑相关文件。
