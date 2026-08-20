# HarmonyOS JPEG EXIF GPS fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 鸿蒙 `inspectImage` 在 ImageKit 返回空 GPS 时，用 `package:image` 解析原图 EXIF 度分秒（DMS）坐标，让定位失败时水印仍能画出 `坐标` 行（对齐 Android `ExifInterface.getLatLong`）。

**Architecture:** 不改 Pigeon / 不改 ETS `parseCoordinate`。新增纯 Dart `readJpegGpsCoordinates`：把 GPS IFD 0x0002/0x0004 的 3 个 rational 合成十进制度，S/W 取负。`OhosPlatformServices.inspectImage` 仅在宿主 lat/lon 皆空时回退读文件；文件缺失或无 GPS 保持 null。无拍成 dump、无定位坐标 dump 不得写定位已出坐标。

**Predecessor:** [2026-08-20-harmonyos-queue-retry.md](2026-08-20-harmonyos-queue-retry.md) 已推。

## Global Constraints

- 不降 SDK，不合 `main`，不改 CI/Android/Pigeon。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。
- 绿灯后只 add 产品/文档并 `git push origin ohos`。
- 用户已要求直接做到功能体验对齐；本刀 inline TDD，不用子代理。

## File map

- Create: `lib/platform/jpeg_gps.dart`
- Create: `test/platform/jpeg_gps_test.dart`
- Modify: `lib/platform/ohos_platform_services.dart`
- Modify: `test/platform/ohos_platform_services_test.dart`
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`

---

### Task 47: JPEG EXIF DMS GPS fallback

- [x] **Step 1: Failing tests** — DMS 31°13′48″N 121°28′12″E → 31.23/121.47；S/W 取负；宿主 GPS 空时 `inspectImage` 回填；宿主已有 GPS 不覆盖；无 GPS 文件仍 null
- [x] **Step 2: `readJpegGpsCoordinates` + `inspectImage` 回退**
- [x] **Step 3: Official tests; honest docs; commit + push `origin/ohos`**
