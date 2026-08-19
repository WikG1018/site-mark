# 全量产品 HAP 与 Android v1.0.8 差距

对照：`main` / Android SiteMark **v1.0.8**（`1.0.8+23`）。本文件只记产品 HAP（`lib/main.dart`）事实，不把审查壳或 `tool/ohos/review` 一次性脚本当产品证据。

## 已接通（模拟器 `SiteMarkPhone602` / hdc `127.0.0.1:5555`）

- 全量 `lib/main.dart` 未签名 HAP 可装可起：隐私门 → 新建项目 → 项目详情 → 拍摄表单 → 全部记录 → 设置 / 关于 → 备份与恢复。
- Drift / sqlite3：same-isolate + musl so + `NativeAssetsManifest.json`；项目可写入。
- `OhosArchiveSaveService` + 宿主 `saveArchive`：picker 优先，失败/取消回退沙箱。
- 降级 `DegradedImagePipeline.export` 写出 schema 5 zip（`manifest.json` + `records.csv`）。0 张照片的 Task13Demo「不包含原图」在沙箱留下 `files/exports/*.zip`，并弹出系统 Document picker。
- 降级读档：`readProjectArchive` / `extractArchivePhoto` / `readBundle` / `extractBundleEntry` 可自读自恢复 schema 5 单项目 zip 与 schema 1 bundle。多项目 selection zip 按 Rust 契约拒绝。官方 `degraded_image_pipeline_test` 14 项全绿。
- 官方测试：`degraded_image_pipeline_test` / `ohos_platform_services_test` / `platform_services_test` 绿灯。
- `OhosArchivePickService` + 宿主 `pickArchive`：恢复选文件走原生 `DocumentViewPicker.select`（单选 `.zip`），`copyUriToPath` 到 `files/imports/sitemark-restore-*.zip`。未做模拟器点选 zip dump。
- 宿主 `inspectImage`：ImageKit 读宽高 / 大小 / MIME / 可选 EXIF GPS；`CameraPicker.resultUri` 与沙箱目标不同时拷进 `files/originals`。无拍成 dump。
- `OhosShareFileService` + 宿主 `shareFile`：ShareKit `ShareController.show`，zip/jpeg/png 走对应 UTD。`main.dart` 鸿蒙入口不再覆盖成 `NoopShareFileService`。官方通道测试绿灯。无分享面板 dump。
- `OhosCompletionNotificationService` + 宿主 NotificationKit：`requestEnableNotification` / `publishCaptureReady`；点击经 WantAgent 参数 `sitemarkDeepLink` 回 Dart。官方通道测试绿灯。无通知 dump。

## 未接通 / 不得宣称

- 备份 zip **未证明**写进系统文件管理。本轮只证实沙箱 zip + picker 弹出，没有 picker 成功 dump。
- 系统文件选择恢复 **未证明**。产品页已改走原生 Document picker → 沙箱 `files/imports`，再进现有 `prepareRestore`；无 picker 成功 dump，不等于系统文件选择恢复已通。
- 相机未拍成；定位未出坐标；ACL 未证明。
- 水印引擎仍 degraded，无 `ohos-arm64`。
- 系统通知 / 系统分享 **未证明**（通道已接，无 dump）。外链仍 no-op。
- 无签名 release，无真机回归。

## 水平结论

项目能存；备份能在应用沙箱导出 zip 并弹出保存选择器；降级引擎能把该 zip 读回；恢复选文件已接到鸿蒙原生 Document picker；拍成后读图已接到 ImageKit；分享通道已接 ShareKit；拍成通知通道已接 NotificationKit；外链通道已接 `startAbility`。拍 / 水印 / 系统文件落盘 / 系统文件选择恢复 / 系统分享面板 / 系统通知 / 系统浏览器仍未对等 Android v1.0.8。
