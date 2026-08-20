# 全量产品 HAP 与 Android v1.0.8 差距

对照：`main` / Android SiteMark **v1.0.8**（`1.0.8+23`）。本文件只记产品 HAP（`lib/main.dart`）事实，不把审查壳或 `tool/ohos/review` 一次性脚本当产品证据。

## 已接通（模拟器 `SiteMarkPhone602` / hdc `127.0.0.1:5555`）

- 全量 `lib/main.dart` 未签名 HAP 可装可起：隐私门 → 新建项目 → 项目详情 → 拍摄表单 → 全部记录 → 设置 / 关于 → 备份与恢复。
- Drift / sqlite3：same-isolate + musl so + `NativeAssetsManifest.json`；项目可写入。
- `OhosArchiveSaveService` + 宿主 `saveArchive`：picker 优先，失败/取消回退沙箱。
- 降级 `DegradedImagePipeline.export` 写出 schema 5 zip（`manifest.json` + `records.csv`）。0 张照片的 Task13Demo「不包含原图」在沙箱留下 `files/exports/*.zip`，并弹出系统 Document picker。
- 降级读档：`readProjectArchive` / `extractArchivePhoto` / `readBundle` / `extractBundleEntry` 可自读自恢复 schema 5 单项目 zip 与 schema 1 bundle。多项目 selection zip 按 Rust 契约拒绝。官方 `degraded_image_pipeline_test` 19 项全绿。
- 降级水印：`degradedWatermarkLines` 对齐 Rust `labels()`；`render` 用 `dart:ui` 半透明卡片叠 JPEG；叠图前 `bakeOrientation`。官方 `degraded_image_pipeline_test` **19 项全绿**。无拍成 dump，不是 `ohos-arm64` 像素对等。
- 应用内串行队列：`InAppSerialBackgroundWorkClient` 对 `CaptureProcessResult.retry` / runner 抛错做 30s × 2^(n-1) 退避，不挡后续 capture；`failed` 不重排。官方 `ohos_background_work_client_test` **6 项全绿**。不是 WorkScheduler 进程保活。
- 相册适配器删除按 URI 身份：`ProbingGalleryStore.delete` 对沙箱 `file://` 走 picker，其余走 ACL，不再按当前探测模式转发。官方 `gallery_store_test` **8 绿**。无相册 dump。
- 备份恢复同编号：删刚恢复 / 再发布后的副本只动本行 `captureId` 与 `publishedUri`，不得串原项目 gallery URI。官方 `capture_media_service_test` 已锁。
- `.github/workflows/ohos.yml` 已纳入降级引擎 / GPS / 鸿蒙通道 / 存储页 / 外观页 / 拍摄表单 / 拍摄工作流 / 启动恢复 / widget / lifecycle / 备份导入测试。push `ohos` 即跑。
- 启动恢复四窗：`AppStartupRecovery` 回调式并行开工相册待清理 / 发布日记 / 相机 / 定位 / 队列；日记抽出为 `CaptureMediaService.recoverPublishJournals()`。官方 `app_startup_recovery_test` 已锁「相机挂起仍开工其余窗」。无杀进程 dump。队列仍是应用内内存串行。
- `OhosArchivePickService` + 宿主 `pickArchive`：恢复选文件走原生 `DocumentViewPicker.select`（单选 `.zip`），`copyUriToPath` 到 `files/imports/sitemark-restore-*.zip`。未做模拟器点选 zip dump。
- 宿主 `inspectImage`：ImageKit 读宽高 / 大小 / MIME / 可选 EXIF GPS；宿主 GPS 空时 Dart 解析 JPEG EXIF 度分秒或单值十进制度回填。官方 `jpeg_gps_test` **6 项全绿**，`ohos_platform_services_test` **30 项全绿**。无拍成 dump、无坐标 dump。
- 相册探测诚实化：`detectGalleryAccess` 无 ACL 证明返回 `pickerFallback`，不再把 READ+WRITE 媒体权限当成 ACL。存储页和拍摄页显示「未进入系统相册」。发布路径在有媒体写权限时仍先尝试 `createAsset`。官方 `storage_section_screen_test` **5 绿**。无相册 dump。
- 动态取色诚实化：鸿蒙 `supportsDynamicColorProvider` 为 false；外观页隐藏「跟随系统取色」开关，始终露出应用主题色，并显示「鸿蒙暂不支持壁纸动态取色」。官方 `appearance_section_screen_test` **9 绿**。不得写 Material You 已对等。
- 宿主 `launchCamera`：`CameraPicker` 省略沙箱 `saveUri`；`file://media/` 用 `fs.openSync(uri)` 拷进 `files/originals`。无拍成 dump。
- `OhosShareFileService` + 宿主 `shareFile`：ShareKit `ShareController.show`，zip/jpeg/png 走对应 UTD。`main.dart` 鸿蒙入口不再覆盖成 `NoopShareFileService`。官方通道测试绿灯。无分享面板 dump。
- `OhosCompletionNotificationService` + 宿主 NotificationKit：`requestEnableNotification` / `publishCaptureReady`；点击经 WantAgent 参数 `sitemarkDeepLink` 回 Dart。官方通道测试绿灯。无通知 dump。

## 未接通 / 不得宣称

- 备份 zip **未证明**写进系统文件管理。本轮只证实沙箱 zip + picker 弹出，没有 picker 成功 dump。
- 系统文件选择恢复 **未证明**。产品页已改走原生 Document picker → 沙箱 `files/imports`，再进现有 `prepareRestore`；无 picker 成功 dump，不等于系统文件选择恢复已通。
- 相机未拍成；定位未出坐标；ACL 未证明。
- 水印引擎仍 degraded，无 `ohos-arm64`。字段卡片已接，像素未对等。无拍成 dump。
- 系统通知 / 系统分享 / 系统外链 **未证明**（通道已接，无 dump）。
- 相机拍成 **未证明**（媒体 URI 拷沙箱已接，无 dump）。
- 系统相册 **未证明**（保存对话框已接，无 dump）。
- 无签名 release，无真机回归。

## 水平结论

项目能存；备份能在应用沙箱导出 zip 并弹出保存选择器；降级引擎能把该 zip 读回；恢复选文件已接到鸿蒙原生 Document picker；拍成后读图已接到 ImageKit，宿主 GPS 空时 Dart 回退读 JPEG EXIF；相机媒体 URI 拷沙箱已接；发布 JPEG 已接系统相册保存对话框；无 ACL 证明时 UI 显示「未进入系统相册」；降级水印已叠与 Rust 同字段的半透明卡片，拍摄页也会标出降级引擎；应用内队列瞬时失败会指数退避重试（进程被杀仍只靠冷启动对账）；入队失败 delayed 后拍摄页仍可继续拍（Dart 测试已锁，无拍成 dump）；启动恢复四窗 Dart 语义已锁（无杀进程 dump）；分享通道已接 ShareKit；拍成通知通道已接 NotificationKit；外链通道已接 `startAbility`。拍成 dump / 定位坐标 dump / 水印像素对等 / 系统相册 dump / 系统文件落盘 / 系统文件选择恢复 / 系统分享面板 / 系统通知 / 系统浏览器仍未对等 Android v1.0.8。
