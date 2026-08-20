# 产品 HAP 模拟器审查

包名 `io.github.wikg1018.sitemark`，版本 `1.0.8+23`。设备：DevEco 模拟器 `SiteMarkPhone602`，hdc `127.0.0.1:5555`。入口：全量 `lib/main.dart` 未签名 HAP。

## 2026-08-20 Task 54

云端闭环：`ohos.yml` 纳入 `capture_workflow_test.dart`；拍摄页锁 delayed 后仍可再拍。生产 `CaptureWorkflowOutcome.delayed` 与 snackbar 已有，本刀未改表单语义。官方测试闭环，未重编 HAP，无拍成 dump。队列仍是应用内内存串行。

| 项 | 结果 |
| --- | --- |
| CI | `.github/workflows/ohos.yml` 纳入 `capture_workflow_test.dart` |
| delayed 继续拍 | 入队抛错后出现 delayed snackbar，`capture-button` 仍可点，再拍一次 `launchCameraCount` 从 1 到 2 |
| 官方测试 | `capture_workflow_test` **17 绿**；`capture_form_screen_test` **20 绿** |
| 模拟器 dump | **无**。不得写相机已拍成；不得写 WorkScheduler 保活 |

## 2026-08-20 Task 53

云端闭环：启动恢复四窗互不阻塞。`AppStartupRecovery` 是回调式，不是 `FakeCaptureWorkflow`。先串行清理中断导入，再并行开工相册待清理 / 发布日记 / 相机 / 定位 / 队列。日记抽出为 `recoverPublishJournals()`。官方测试闭环，未重编 HAP，无杀进程 dump。队列仍是应用内内存串行。

| 项 | 结果 |
| --- | --- |
| 并行开工 | 相机挂起时队列 / 日记 / 相册窗仍开工；一窗抛错不跳过其余窗 |
| 日记抽出 | `CaptureMediaService.recoverPublishJournals()` 按 `captureById` 对账；真正删 URI 仍由 `cleanupInterrupted` |
| CI | `.github/workflows/ohos.yml` 纳入 `app_startup_recovery_test.dart` |
| 官方测试 | `app_startup_recovery_test` + `capture_media_service_test` + `widget_test` + `app_lifecycle_test` **88 绿** |
| 模拟器 dump | **无**。不得写杀进程后四窗已在设备上验证；不得写 WorkScheduler 保活 |

## 2026-08-20 Tasks 51–52

云端闭环：扩充 `ohos.yml`；相册删除按 URI 身份；备份恢复同编号不得串 URI。官方测试闭环，未重编 HAP，无相册 dump。

| 项 | 结果 |
| --- | --- |
| CI | `.github/workflows/ohos.yml` 纳入 `degraded_image_pipeline_test` / `jpeg_gps_test` / `ohos_platform_services_test` / `storage_section_screen_test` / `appearance_section_screen_test` / `capture_form_screen_test` |
| 删除路由 | `ProbingGalleryStore.delete` 按 URI 方案（沙箱 `file://` → picker，其余 → ACL），对齐 `OhosSystemHost.deletePublishedImage` |
| 同编号 | 删未发布恢复副本不碰原项目 URI；再发布后再删只删副本自己的 URI |
| 官方测试 | `gallery_store_test` **8 绿**；`publish_journal_store_test` **5 绿**；`capture_media_service_test` 含新 2 项全绿 |
| 模拟器 dump | **无**。不得写系统相册 / 拍成 / 备份进系统文件管理已通 |

## 2026-08-19 Tasks 21–24

走查：隐私门 → 新建 Task13Demo → 设置 → 备份与恢复 → 备份项目 → 勾选 Task13Demo → 继续 → 不包含原图。

| 项 | 结果 |
| --- | --- |
| 产品 HAP 重装 | 未签名 HAP 卸载后安装成功，`aa start` 成功 |
| 降级 zip 导出 | 沙箱留下 `files/exports/sitemark-backup-1787112954673-25897fe6-ebae-47bc-9a56-2f2c69d52cae.zip`（1086 bytes） |
| zip 内容 | `manifest.json` `schema_version: 5`，`records.csv` BOM+表头，`photoCount` 0，无 `photos/` |
| `saveArchive` | 弹出系统 Document picker（「保存」「取消」「文件名称」）。**未完成 picker 保存，不得写已进系统文件管理** |
| 官方测试 | `degraded_image_pipeline_test` / `ohos_platform_services_test` / `platform_services_test` 通过 |

根因修复：此前空 `exports` 不是 save 后删文件，而是 `DegradedImagePipeline.export()` 未实现。现已用 `package:archive` + `crypto` 对齐 Rust schema 5。

## 2026-08-19 Tasks 25–27

官方测试闭环，未重编 HAP、未走系统 `FilePicker`。

| 项 | 结果 |
| --- | --- |
| `readProjectArchive` | 可读自己写出的 schema 5 空项目 zip |
| `extractArchivePhoto` | 解出的 JPEG 字节与源文件一致 |
| `readBundle` / `extractBundleEntry` | 可解出内层项目 zip 再读回 |
| selection zip | `invalid_data: Only single-project archives are restorable` |
| 缺失 zip | `not_found:` |
| 官方测试 | `degraded_image_pipeline_test` 14 项通过 |

## 2026-08-19 Tasks 29–30

产品恢复选文件改走鸿蒙原生 Document picker。官方通道测试闭环，未重编 HAP，未在模拟器点选 zip。

| 项 | 结果 |
| --- | --- |
| 通道 | `OhosSystemApi.pickArchive` / `OhosArchivePickService` |
| 产品接线 | `archivePickServiceProvider`；`runProjectRestoreFlow` 默认 `pickZip` 读该服务 |
| 宿主 | `DocumentViewPicker.select` 单选 `.zip`，`copyUriToPath` 到 `files/imports/sitemark-restore-*.zip` |
| 取消 | 空串 → Dart `null` |
| 非鸿蒙 | `FilePicker.pickFile` 单选 zip |
| 官方测试 | `ohos_platform_services_test` 9 项通过 |
| 模拟器 dump | **无**。不得写系统文件选择恢复已通 |

## 2026-08-19 Tasks 31–32

拍成后读图改走 ImageKit。官方通道测试闭环，未重编 HAP，未在模拟器拍成。

| 项 | 结果 |
| --- | --- |
| 通道 | `OhosSystemApi.inspectImage` 解码宽高 / 大小 / MIME / GPS |
| 宿主 | ImageKit `createImageSource` + `getImageInfo` + EXIF GPS |
| 相机回写 | `CameraPicker.resultUri` 与沙箱目标不同时 `copyUriToPath` |
| 官方测试 | `ohos_platform_services_test` 11 项通过 |
| 模拟器 dump | **无**。不得写相机已拍成 |

## 2026-08-19 Tasks 33–34

备份/导出分享改走鸿蒙原生 ShareKit。官方通道测试闭环，未重编 HAP，未在模拟器弹出分享面板。

| 项 | 结果 |
| --- | --- |
| 通道 | `OhosSystemApi.shareFile` / `OhosShareFileService` |
| 产品接线 | `shareFileServiceProvider`：鸿蒙走 `OhosShareFileService` |
| 宿主 | ShareKit `ShareController.show`；zip/jpeg/png 走对应 UTD |
| 顺带 | 补 ImageKit import（`dcd16b1` 漏写） |
| 官方测试 | `ohos_platform_services_test` 13 项通过 |
| 模拟器 dump | **无**。不得写系统分享已通 |

## 2026-08-19 Tasks 35–36

拍成完成通知改走鸿蒙 NotificationKit，并修掉 `main.dart` 把分享覆盖成 no-op。官方通道测试闭环，未重编 HAP，未在模拟器弹出系统通知。

| 项 | 结果 |
| --- | --- |
| 通道 | `OhosSystemApi.requestEnableNotification` / `publishCaptureReady` / `listenNotificationTap` |
| 产品接线 | `OhosCompletionNotificationService`；`main.dart` 鸿蒙分享走 `OhosShareFileService` |
| 宿主 | NotificationKit `requestEnableNotification` + `addSlot` + `publish` 基础文本；WantAgent 带回 `sitemarkDeepLink` |
| 冷启动 | `takePendingNotificationTap`：插件 attach 前点通知，等 Dart `initialize` 再投递 |
| 官方测试 | `ohos_platform_services_test` 19 项通过 |
| 模拟器 dump | **无**。不得写系统通知已通 |

## 2026-08-19 Tasks 37–38

关于页 GitHub 改走鸿蒙 `startAbility` 隐式 Want，并修掉 `main.dart` 把外链覆盖成 no-op。官方通道测试闭环，未重编 HAP，未在模拟器打开系统浏览器。

| 项 | 结果 |
| --- | --- |
| 通道 | `OhosSystemApi.openLink` |
| 产品接线 | `OhosExternalLinkService`；`main.dart` 鸿蒙外链走该服务 |
| 宿主 | `ohos.want.action.viewData` + `entity.system.browsable` + `startAbility` |
| `querySchemes` | `https` / `http` |
| 官方测试 | `ohos_platform_services_test` 22 项通过 |
| 模拟器 dump | **无**。不得写系统外链已通 |

## 2026-08-20 Task 47

宿主 `inspectImage` GPS 空时 Dart 解析 JPEG EXIF（度分秒 3 个 rational 或单值十进制度）。官方测试闭环，未重编 HAP，无拍成 dump、无坐标 dump。

| 项 | 结果 |
| --- | --- |
| 解析 | `readJpegGpsCoordinates`：DMS → 十进制度；S/W 取负；单值 double 也认 |
| 回退 | 宿主 lat/lon 皆空才读盘；宿主已有 GPS 不覆盖 |
| 官方测试 | `jpeg_gps_test` **6 项全绿**；`ohos_platform_services_test` **28 项全绿** |
| 模拟器 dump | **无**。不得写定位已出坐标 |

## 2026-08-20 Task 46

应用内串行队列对 `CaptureProcessResult.retry` / runner 抛错做 30s 起指数退避。官方队列测试闭环，未重编 HAP，无拍成 dump。

| 项 | 结果 |
| --- | --- |
| 退避 | 30s × 2^(n-1)，最多 3 次调度重试；`failed` 不重排 |
| 不挡队 | c1 retry 等待期间仍跑 c2 |
| 接线 | `processCaptureOnOhos` 返回 `CaptureProcessResult` |
| 官方测试 | `ohos_background_work_client_test` **6 项全绿** |
| 模拟器 dump | **无**。不是 WorkScheduler 进程保活，不得写后台渲染已对等 |

## 2026-08-20 Task 50

外观页动态取色诚实化。鸿蒙不假装 Material You「跟随系统取色」可用。官方 UI 测试闭环，未重编 HAP。

| 项 | 结果 |
| --- | --- |
| 能力 | `supportsDynamicColorProvider` 默认 `!isOhosBuild` |
| UI | 不支持时隐藏 `dynamic-color-switch`，显示「鸿蒙暂不支持壁纸动态取色」，始终露出 9 个主题色芯片 |
| 主题 | `SiteMarkApp` 在不支持时忽略已持久化的 `useDynamicColor` |
| 官方测试 | `appearance_section_screen_test` **9 绿** |
| 模拟器 dump | **无**。不得写动态取色已对等 Android Material You |

## 2026-08-20 Task 49

拍摄页补上与存储页/拍摄详情相同的降级水印引擎提示。官方 UI 测试闭环，未重编 HAP，无拍成 dump。

| 项 | 结果 |
| --- | --- |
| UI | `imagePipelineProvider.isDegraded` 时拍摄页显示「降级水印引擎」/`watermark-engine-degraded` |
| 非降级 | 宿主默认 Rust 管线不显示该提示 |
| 官方测试 | `capture_form_screen_test` **19 绿** |
| 模拟器 dump | **无**。不得写水印已对等 Android 像素 |

## 2026-08-20 Task 48

相册探测诚实化。无 ACL 成功证明时不得把媒体权限当成 `acl`。官方 UI / 通道测试闭环，未重编 HAP，无相册 dump。

| 项 | 结果 |
| --- | --- |
| 探测 | `detectGalleryAccess` 默认 `pickerFallback` |
| 发布 | 有 READ+WRITE 媒体权限仍先 `createAsset`，失败再相册对话框/沙箱 |
| UI | 存储页、拍摄页在 `pickerFallback` 显示「未进入系统相册」 |
| 官方测试 | `storage_section_screen_test` **5 绿**、`ohos_platform_services_test` **30 绿** |
| 模拟器 dump | **无**。不得写系统相册已通 |

## 2026-08-20 Task 45

降级 `render` 叠水印前烘焙 EXIF orientation（orientation 6：48×32 → 32×48）。删除恢复页未使用的 `FilePicker` 路径。官方管线测试闭环，未重编 HAP，无拍成 dump。

| 项 | 结果 |
| --- | --- |
| 方向 | `img.bakeOrientation` 在 decode 后、卡片叠图前 |
| 恢复页 | 去掉 `_pickRestoreZip`；产品路径仍走 `OhosArchivePickService` |
| 官方测试 | `degraded_image_pipeline_test` **19 项全绿** |
| 模拟器 dump | **无**。不得写方向已对等 Android 像素 |

## 2026-08-20 Tasks 43–44

降级水印从只画英文 `SiteMark` 改为与 Rust `labels()` 同字段的半透明卡片。官方管线测试闭环，未重编 HAP，无拍成 dump。

| 项 | 结果 |
| --- | --- |
| 文案 | `degradedWatermarkLines`：现场记录 · 项目 / 位置 / 内容 / 拍摄人 / 时间；非空地址、坐标、备注；照片编号不画 |
| 叠图 | `dart:ui` Canvas 半透明底 + 左侧 accent + `compositeImage` |
| 字体 | `NotoSansSC` ← `rust/assets/fonts/NotoSansSC-Regular.otf` |
| 官方测试 | `degraded_image_pipeline_test` **18 项全绿**（随后 Task 45 扩到 19） |
| 模拟器 dump | **无**。不得写水印已对等 Android 像素 |

## 2026-08-20 Tasks 41–42

无 ACL 发布走系统相册保存对话框。官方通道测试闭环，未重编 HAP，未在模拟器保存到相册。

| 项 | 结果 |
| --- | --- |
| 通道 | `publishJpeg` 解码媒体库 URI；`requestCurrentLocation` 解码精确坐标 |
| 宿主 | `showAssetsCreationDialog` + `PhotoCreationConfig`；用户取消不静默沙箱 |
| 删除 | 沙箱 `file://` 才 unlink；`file://media/` 走 `deleteAssets` |
| 官方测试 | `ohos_platform_services_test` **26 项全绿** |
| 模拟器 dump | **无**。不得写系统相册已通 |

## 2026-08-20 Tasks 39–40

系统相机 `resultUri` 拷进沙箱 `files/originals`。官方通道测试闭环，未重编 HAP，未在模拟器拍成。

| 项 | 结果 |
| --- | --- |
| 通道 | `OhosPlatformServices.launchCamera` 解码 `CAMERA_CAPTURED` / `CAMERA_CANCELLED` |
| 宿主 | `CameraPicker` 省略沙箱 `saveUri`；`file://media/` 用 `fs.openSync(uri)` 写入 `files/originals/{id}.jpg` |
| 失败语义 | picker 成功但空文件 / 拷失败 → `CAMERA_FAILED`，不再把空文件当取消 |
| 官方测试 | `ohos_platform_services_test` **24 项全绿** |
| 模拟器 dump | **无**。不得写相机已拍成 |

## 仍禁止写成已完成

- picker 真正写入系统文件
- 系统文件选择恢复（接线已改原生 picker，无成功 dump）
- 系统分享面板（接线已改原生 ShareKit，无成功 dump）
- 系统通知（接线已改 NotificationKit，无成功 dump）
- 系统外链（接线已改 `startAbility`，无浏览器 dump）
- 相机拍成 / ACL / `ohos-arm64`
- 签名 release / 真机
