# HarmonyOS native inspectImage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 拍成后的读图对齐安卓 `inspectImage`：从沙箱 JPEG 读出宽高、文件大小、MIME、可选 EXIF GPS，让定位协调器能走 EXIF 优先，水印处理不再因 `ohos_not_ready` 丢掉照片元数据。

**Architecture:** 不改 Pigeon。Dart `OhosSystemApi.inspectImage` / `OhosPlatformServices.inspectImage` 已存在。宿主 `inspectImage` 当前直接抛 `ohos_not_ready`。改为 `@kit.ImageKit` `image.createImageSource` + `getImageInfo` + `getImageProperty`。`launchCamera` 已有 `CameraPicker.pick` + `resultUri` 回写；本块只加固「resultUri 与目标路径不同时一律拷进沙箱」。无模拟器拍成 dump 不得写相机已拍成。

**Tech Stack:** 官方 Flutter 3.44.6 / Dart 3.12.2 跑测试；`@kit.ImageKit`；现有 `sitemark.system.ohos` 通道。

**Predecessor:** [2026-08-19-harmonyos-pick-archive.md](2026-08-19-harmonyos-pick-archive.md) 已推 `648db79`。

## Global Constraints

- 不降 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`，不合 `main`。
- 不要 page-level `if (ohos)`。
- 不实现 ACL、`ohos-arm64`、系统相册对等。
- 无模拟器拍成 dump 不得写相机已拍成 / 定位已出坐标。
- 不提交一次性脚本、HAP、`ohos/entry/libs/`、社区 lock、`flutter_*.log`、`tool/ohos/review/`。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。
- 用户已说提交并继续：本块绿灯后只 add 产品/文档并 `git push origin ohos`。

## File map

- Modify: `test/platform/ohos_platform_services_test.dart` — `inspectImage` 解码契约。
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets` — ImageKit `inspectImage` + `resultUri` 回写。
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`。

---

### Task 31: Dart inspectImage decode contract

**Files:**
- Modify: `test/platform/ohos_platform_services_test.dart`

**Interfaces:**
- Consumes: `OhosPlatformServices.inspectImage` → `OhosSystemApi.inspectImage` → `_decodeImageMetadataResult`
- Produces: 通道 map `{width,height,fileSizeBytes,mimeType,latitude,longitude}` 解码为 `ImageMetadataResult`

- [ ] **Step 1: Write the failing tests**

在 `ohos_platform_services_test.dart` 追加：

```dart
  test('OhosPlatformServices inspectImage decodes metadata map', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'inspectImage');
          expect(call.arguments, {'path': '/tmp/a.jpg'});
          return <String, Object?>{
            'width': 4032,
            'height': 3024,
            'fileSizeBytes': 2048,
            'mimeType': 'image/jpeg',
            'latitude': 31.23,
            'longitude': 121.47,
          };
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final metadata = await OhosPlatformServices().inspectImage('/tmp/a.jpg');
    expect(metadata.width, 4032);
    expect(metadata.height, 3024);
    expect(metadata.fileSizeBytes, 2048);
    expect(metadata.mimeType, 'image/jpeg');
    expect(metadata.latitude, closeTo(31.23, 0.0001));
    expect(metadata.longitude, closeTo(121.47, 0.0001));
  });

  test('OhosPlatformServices inspectImage treats missing GPS as null', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'width': 100,
            'height': 80,
            'fileSizeBytes': 12,
            'mimeType': 'image/jpeg',
            'latitude': null,
            'longitude': null,
          };
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final metadata = await OhosPlatformServices().inspectImage('/tmp/a.jpg');
    expect(metadata.latitude, isNull);
    expect(metadata.longitude, isNull);
  });
```

- [ ] **Step 2: Run test to verify it fails**

官方 `ohos_platform_services_test.dart`。解码测试应红，直到确认现有解码已通（若已通则本步即绿，进入宿主实现）。

- [x] **Step 3: No Dart product change unless decode is missing**

`OhosSystemApi.inspectImage` 与 `_decodeImageMetadataResult` 已存在，不要重复封装。

- [x] **Step 4: Re-run official Dart tests**

`ohos_platform_services_test.dart` 须全绿。

---

### Task 32: Host ImageKit inspectImage + resultUri copy

**Files:**
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets`
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`

**Interfaces:**
- Consumes: `image.createImageSource(path)`、`getImageInfo()`、`getImageProperty(PropertyKey)`、`fs.statSync`
- Produces: `inspectImage(path)` 返回 `{width,height,fileSizeBytes,mimeType,latitude,longitude}`；空文件 / 缺失文件抛错。`launchCamera` 在 `resultUri` 与 `target` 不同时 `copyUriToPath`。

- [ ] **Step 1: Implement inspectImage**

`import { image } from '@kit.ImageKit';`

`case 'inspectImage': return await this.inspectImage(this.requiredString(args, 'path'));`

```ets
  private async inspectImage(path: string): Promise<Record<string, Object | null>> {
    if (!this.hasCaptureContent(path)) {
      throw new Error('image not found');
    }
    const source = image.createImageSource(path);
    try {
      const info = await source.getImageInfo();
      const orientationText = await this.readImageProperty(source, image.PropertyKey.ORIENTATION);
      const latitudeText = await this.readImageProperty(source, image.PropertyKey.GPS_LATITUDE);
      const longitudeText = await this.readImageProperty(source, image.PropertyKey.GPS_LONGITUDE);
      const latitudeRef = await this.readImageProperty(source, image.PropertyKey.GPS_LATITUDE_REF);
      const longitudeRef = await this.readImageProperty(source, image.PropertyKey.GPS_LONGITUDE_REF);
      const swapped = this.swapsDimensions(orientationText);
      const gps = this.parseExifGps(latitudeText, longitudeText, latitudeRef, longitudeRef);
      const result: Record<string, Object | null> = {
        width: swapped ? info.size.height : info.size.width,
        height: swapped ? info.size.width : info.size.height,
        fileSizeBytes: fs.statSync(path).size,
        mimeType: info.mimeType.length > 0 ? info.mimeType : 'image/jpeg',
        latitude: gps.latitude,
        longitude: gps.longitude,
      };
      return result;
    } finally {
      await source.release();
    }
  }
```

GPS 解析对齐安卓：`a/b` 有理数或小数；南纬/西经取负；超出 ±90/±180 视为无 GPS。

- [x] **Step 2: Copy CameraPicker resultUri when it is not the sandbox target**

把

```ets
        if (!this.hasCaptureContent(target) && pickerResult?.resultUri) {
          await this.copyUriToPath(pickerResult.resultUri, target);
        }
```

改成：`resultUri` 存在且解析后的路径不等于 `target` 时一律拷贝；拷贝失败不覆盖已有目标内容。

- [x] **Step 3: Re-run official Dart tests**

`ohos_platform_services_test.dart` 仍须全绿。不宣称模拟器相机已拍成。

- [x] **Step 4: Update docs honestly**

写清：鸿蒙读图走 ImageKit `inspectImage`；相机仍是系统 `CameraPicker` + 沙箱 `files/originals`。无拍成 dump 不得写相机已拍成。

- [x] **Step 5: Commit and push origin/ohos**
