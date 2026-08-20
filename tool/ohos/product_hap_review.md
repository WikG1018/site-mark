# 产品 HAP 模拟器审查

包名 `io.github.wikg1018.sitemark`，版本 `1.0.8+23`。设备：DevEco 模拟器 `SiteMarkPhone602`，hdc `127.0.0.1:5555`。入口：全量 `lib/main.dart` 未签名 HAP。

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
