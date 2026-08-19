# HarmonyOS 拍成完成通知（Tasks 35–36）

日期：2026-08-19  
分支：`ohos`  
目标：拍成完成后的系统通知走鸿蒙 NotificationKit，语义对齐 Android `LocalNotificationService`；同时修掉 `main.dart` 把分享覆盖成 `NoopShareFileService` 的入口问题。

## 范围

- Dart：`OhosCompletionNotificationService` 实现 `CompletionNotificationService`。
- 通道：`requestEnableNotification`、`publishCaptureReady`。
- 宿主：`notificationManager.requestEnableNotification` + `addSlot` + `publish` 基础文本。
- 点击：通知 WantAgent 带回 `sitemarkDeepLink`，`EntryAbility` 转给 Dart `onTapDeepLink`。
- 入口：`main.dart` 鸿蒙不再注入通知/分享 no-op。
- 不改：`pigeons/`、`android/`、`ci.yml`、`release.yml`、引擎 crate。
- 不声称：无通知 dump 不得写「系统通知已通」；无分享面板 dump 不得写「系统分享已通」。

## Tasks

- [x] 35. 官方测试覆盖通知通道契约与 enabled 门闩
- [x] 36. NotificationKit 宿主 + Dart 服务 + 修入口覆盖

## 验收

- 官方 `ohos_platform_services_test` 绿灯。
- 设置页开通知会走 `requestEnableNotification`。
- `processCaptureOnOhos` 成功后可走 `showCaptureReady`。
- 提交只含产品/文档；push `origin/ohos`；不合 `main`。
