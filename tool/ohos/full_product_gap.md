# 全量 `lib/main.dart` HAP 差异表（2026-08-19 实测）

对照 Android SiteMark v1.0.8。本表只写**已量到的事实**，不写愿望。

引擎：`tool/ohos/engine_status.md` = **degraded**。

| 能力 | 模拟器现状 | 能否对外宣称 | 备注 |
|---|---|---|---|
| 全量 Dart 入口 | 已进 HAP | 可写「模拟器已跑 `lib/main.dart`」 | `--target lib/main.dart --dart-define=SITEMARK_OHOS=true` |
| 隐私门 | 已过 | 可 | `FilePrivacyConsentStore` + 桥接 `path_provider` |
| 首页（工程印记 / 项目 / 全部记录 / 设置） | 已看到 | 可写「空项目首页」 | dump 无审查壳文案 |
| 新建项目 | 已过 | 可写「模拟器已保存项目并回到首页列表」 | 首页出现 `Task10Demo` / `Task13Demo`；库文件 `filesDir/sitemark.sqlite` |
| 项目详情 | 已过 | 可写「可进项目详情」 | `Task13Demo`：进行中 / 0 张照片 / FAB「拍摄」 |
| 拍摄表单 | 已过 | 可写「可打开拍摄表单并填写」 | 标题「水印内容」；地点/内容/拍摄人可输入；底部「拍摄」 |
| Drift / sqlite3 | 已打开 | 不单独宣称持久化对等 | same-isolate + 显式 `sqlite3.open` + musl `libsqlite3.so` + `NativeAssetsManifest.json` |
| 设置页 | 已打开 | 可写「设置分组可进」 | 外观 / 数据与备份 / 通知 / 诊断 / 关于 |
| 关于页版本 | 已过 | 可写「关于页显示 `1.0.8+23`」 | `package_info` 桥 `getAll`；设备标记 `SITEMARK_PKG_INFO getAll 1.0.8 23` |
| 通知开关 | 已过 | **否**（不是系统通知） | `NoopCompletionNotificationService`；开关可拨，不崩 |
| 仓库外链 | 已点 | **否**（不是系统浏览器） | `NoopExternalLinkService`；SnackBar「无法打开浏览器」，应用仍在关于页 |
| 分享 | 代码 no-op | **否** | `NoopShareFileService`；未走发布页，无 page-level `if (ohos)` |
| 水印 Rust | 未编 `ohos-arm64` | **否** | 降级管线 |
| 全部记录 | 已过 | 可写「空列表可开」 | 标题「全部记录」；「暂无记录」/「还没有拍摄记录」 |
| 备份与恢复入口 | 已过 | 可写「可打开备份选项目」 | 设置 → 备份与恢复 → 备份项目；列表含 `Task13Demo` |
| 备份导出 | 已探测，未导出 | **否** | 点「不包含原图」后 `files/exports` 被创建且无 zip；`saveArchive` 仍 `ohos_not_ready`；应用回选项目页未崩 |
| 系统相机 | 已探测，未拍成 | **否** | 权限框已出；hilog `CameraPicker::Pick`；模拟器无相机 UI；`originals` 空；应用回表单未崩 |
| 定位 | 已探测权限框，未证坐标 | **否** | 「开启定位」弹出系统位置框；允许后定位卡消失；不宣称 GPS 已通 |
| 相册 ACL `READ/WRITE_IMAGEVIDEO` | 未测 | **否** | 无真机 / 无 AGC |
| picker / 沙箱托底 | 代码在，未走 | **否** | |
| WorkManager | ohos 走应用内串行队列 | 写差异，不假装 WorkManager | `InAppSerialBackgroundWorkClient` |
| `dynamic_color` | 未证 | **否** | 可走默认主题 |
| `file_picker` | 钉 `12.0.0-beta.7`；未走导入 | **否** | 12.0.0 破坏 `.files` |
| AutoFill | API 24 编译桩 | **否** | 只为过编 |
| 签名 release | 无 | **否** | 未签名 debug 可装模拟器 |
| 应用市场上架 | 无 | **否** | |

官方测试（官方 Flutter 3.44.6 / Dart 3.12.2，2026-08-19）：

- `rust_initialization_contract_test.dart`
- `notification_service_test.dart`
- `external_link_service_test.dart`
- `platform_services_test.dart`
- `ohos_platform_services_test.dart`
- `app_database_test.dart`

全部通过。不要用社区 Flutter 跑官方测试。不要提交社区 `pub get` 冲过的 lock。
