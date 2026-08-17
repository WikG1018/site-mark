# SiteMark HarmonyOS NEXT 适配实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 GitHub `origin/main` 的 SiteMark v1.0.8（`847c74b`）上，用长期 `ohos` 分支交付 HarmonyOS NEXT 原生 HAP，产品语义与 Android v1.0.8 全量对等。

**Architecture:** `main` 继续官方 Flutter 3.41.2 / Pigeon+Kotlin / WorkManager / MediaStore。`ohos` 分支用 OpenHarmony 社区 Flutter 编 HAP。页面、`CaptureWorkflow`、`CaptureProcessor`、Drift 状态机不写 `if (ohos)`。鸿蒙只替换 `PlatformServices` 与 `BackgroundWorkClient` 的实现：联邦插件 `sitemark_system_api` 增加 ohos 宿主、应用内串行队列、ACL 相册 + picker 托底、Rust `ohos-arm64`。

**Tech Stack:** OpenHarmony 社区 Flutter（约 3.27–3.32）、ArkTS / NAPI、HarmonyOS NEXT SDK、Drift / sqlite3 ohos 实现、现有 `sitemark_core` Rust crate + FRB 2.12.0 或等价 FFI、Riverpod、GoRouter。

**Spec:** [2026-08-17-harmonyos-next-adaptation-design.md](../specs/2026-08-17-harmonyos-next-adaptation-design.md)

## Global Constraints

- 基线是 GitHub `origin/main` **v1.0.8 / `847c74b`**，不是本工作区可能落后的 `1.0.7+22`。
- `ohos` 从该提交拉出；OHOS SDK、`ohos/`、社区 Flutter、插件补丁只存在该分支。禁止把 fork 补丁合回 `main`。
- `main` 的产品修复只允许 `main` → `ohos` cherry-pick，反向合入禁止。
- 不改 `PlatformServices` / `BackgroundWorkClient` / `SiteMarkSystemApi` 的方法签名。
- 页面、`CaptureWorkflow`、`CaptureProcessor` 禁止 `if (ohos)` 发图或相册分支。
- 发布日记与替换只按 **`captureId`** 记账，禁止按照片编号或文件名扫相册。
- **真实 v1.0.8 语义（本计划以此为准，覆盖规格里“原生删旧图”的简化表述）：** `publishJpeg` 先落新图、同步写日记，**原生不删相册行**；返回 `PublishJpegOutcome(contentUri, supersededUris)`；Dart 更新 Drift 后做引用检查、只删无引用的旧 URI。`clearPublishJournal(captureId, expectedContentUri)` 必须条件清除。
- 全量对等只能在 **AGC 批准 `READ/WRITE_IMAGEVIDEO` ACL** 且 **Rust 编出 `ohos-arm64`** 同时成立时对外宣称。picker / 降级水印可发测试包，必须标明降级。
- 第 0 期是硬闸：空壳 HAP 不能在 NEXT **模拟器或真机**冷启动就停，改评纯 ArkTS，不堆业务。无真机时 DevEco NEXT 模拟器冷启动视为第 0 期过关。
- 不做账号、联网、推送、自研相机、图库导入、iOS、折叠屏 / 多设备流转。
- 动态取色、本地通知若 ohos 插件缺失，第一期可关，必须写入差异表，不得 silently 假装还在。
- 不在 UI、记录卡片、SnackBar、诊断包对外文案里暴露原始异常或平台字符串。
- 所有行为变更先写失败测试，再写最小实现并验证转绿。第 0 期工具链用 NEXT 模拟器或真机冷启动作为验收，不编造单测替代表。

---

## File map

| 路径 | 职责 |
|---|---|
| 长期分支 `ohos`（从 `847c74b` 拉出） | 隔离社区 Flutter、OHOS SDK、插件补丁 |
| `ohos/` | HAP 工程：`entry/src/main/module.json5`、签名、Ability、权限 |
| `packages/sitemark_system_api/pubspec.yaml` | 联邦插件增加 `ohos` platform |
| `packages/sitemark_system_api/lib/src/ohos/ohos_system_api.dart` | JSON MethodChannel `sitemark.system.ohos`，方法名与 `SiteMarkSystemApi` 一一对应 |
| `packages/sitemark_system_api/lib/src/ohos/ohos_platform_services.dart` | `OhosPlatformServices implements PlatformServices` |
| `packages/sitemark_system_api/lib/src/ohos/publish_journal_store.dart` | 按 `captureId` 的发布日记（Dart，可单测） |
| `packages/sitemark_system_api/lib/src/ohos/capture_session_store.dart` | 相机会话半截恢复 |
| `packages/sitemark_system_api/lib/src/ohos/gallery_store.dart` | `GalleryStore` / `AclGalleryStore` / `PickerFallbackStore` / `ProbingGalleryStore` |
| `packages/sitemark_system_api/ohos/` | ArkTS 宿主：相机 Ability、定位、PhotoAccessHelper、保存 picker、沙箱文件 |
| `lib/platform/ohos_background_work_client.dart` | `InAppSerialBackgroundWorkClient implements BackgroundWorkClient` |
| `lib/app.dart` | 仅在 `ohos` 分支把 provider 接到鸿蒙实现；不改业务签名 |
| `lib/l10n/app_strings.dart` | 相册降级、隐私弹窗、降级水印中英文案 |
| `rust/Cargo.toml` + `rust_builder/` | 增加 `ohos` ffi 目标 |
| `.github/workflows/ohos.yml` | **只挂在 `ohos` 分支**：编 HAP / 跑鸿蒙相关 Dart 测试。不改 `main` 的 `ci.yml` / `release.yml` |
| `docs/superpowers/specs/2026-08-17-harmonyos-next-adaptation-design.md` | 已确认规格；实现中以本计划的发布语义为准 |

不改（除非 cherry-pick 需要解决冲突）：`pigeons/system_api.dart`、Android Kotlin、`CaptureProcessor` 状态机、`.github/workflows/ci.yml` 的 Android 3.44/3.41 发布线。

鸿蒙不复用 Pigeon `_PigeonCodec`（type 129–138）和 Kotlin 生成器。Dart 业务继续只认 `PlatformServices`。`OhosPlatformServices` 用稳定 JSON channel，避免在 ArkTS 里重实现 Pigeon 二进制 codec。

---

### Task 0: 工具链硬闸与 `ohos` 分支

**Files:**
- Create branch: `ohos` from `origin/main` @ `847c74b`
- Create: `ohos/` 空壳 HAP（社区 Flutter `flutter create --platforms ohos` 或官方 OHOS 模板）
- Create: `tool/ohos/toolchain_probe.md`（只记录实测 SDK 版本、fork 提交、模拟器或真机型号、过/不过；不是产品文档）
- Do not modify: `.github/workflows/ci.yml`、`release.yml`、`android/`

**Interfaces:**
- Consumes: GitHub `origin/main` `847c74b`；本仓已提交的规格 `docs/superpowers/specs/2026-08-17-harmonyos-next-adaptation-design.md` 与本计划（从当前提交 cherry-pick 到 `ohos`）
- Produces: 可在 NEXT 模拟器或真机冷启动的空壳 HAP；`OHOS_FLUTTER_ROOT` 本机约定；失败则停止后续 Task

- [ ] **Step 1: 确认基线提交，不要在落后的本地树上开干**

```bash
git fetch origin
git log -1 --oneline origin/main
```

Expected: 含 `847c74b` 且 tag / 版本指向 **v1.0.8**。若 `origin/main` 已超前，仍以 **v1.0.8 标签或 `847c74b`** 为分支起点，再 cherry-pick 之后需要的产品修复。

- [ ] **Step 2: 从基线拉长期分支，并把规格/计划带过去**

```bash
git checkout -B ohos 847c74b
git cherry-pick 97b7a0d
git cherry-pick <本计划提交>
```

Expected: `ohos` 指向 v1.0.8 树，且 `docs/superpowers/specs/2026-08-17-harmonyos-next-adaptation-design.md` 与本文件存在。冲突只允许出现在文档路径。

- [ ] **Step 3: 安装独立 OHOS Flutter SDK，禁止覆盖官方 3.41.2**

本机同时保留：

- 官方 Flutter 3.41.2（或 `main` CI 使用的 3.44.x）→ 继续编 Android
- 社区 OHOS Flutter（记录精确 commit）→ 只给 `ohos` 分支用

```bash
# 示例：SDK 装在仓库外，避免污染 main
echo %OHOS_FLUTTER_ROOT%
"%OHOS_FLUTTER_ROOT%\bin\flutter" --version
"%OHOS_FLUTTER_ROOT%\bin\flutter" doctor
```

Expected: `flutter doctor` 识别 HarmonyOS / OpenHarmony toolchain。若命令不存在或 doctor 失败，**停在 Task 0**，不要创建业务代码。把失败原因写入 `tool/ohos/toolchain_probe.md` 后改评纯 ArkTS。

- [x] **Step 4: 生成空壳 HAP 并在 NEXT 模拟器或真机启动**

在 `ohos` 分支根目录用社区 Flutter 生成平台目录（具体 flag 以该 fork 文档为准，常见为 `--platforms ohos`）：

```bash
"%OHOS_FLUTTER_ROOT%\bin\flutter" create --platforms ohos .
"%OHOS_FLUTTER_ROOT%\bin\flutter" pub get
"%OHOS_FLUTTER_ROOT%\bin\flutter" build hap --debug
"%OHOS_FLUTTER_ROOT%\bin\flutter" install
```

Expected: 模拟器或真机出现默认计数器 / 空 Flutter 界面，进程不秒退。无真机时先用 DevEco `emulator.exe` 装 Phone 镜像、建实例、冷启动，再 `hdc list targets` 必须非空。把 SDK 版本、fork commit、目标类型（emulator/device）、API 版本写入 `tool/ohos/toolchain_probe.md`。

- [x] **Step 5: 过关或停**

过关条件（全部满足才进入 Task 1）：

1. 空壳 HAP 在 HarmonyOS NEXT 模拟器或真机冷启动成功
2. 官方 Flutter 仍能在另一条 checkout / 另一 `PATH` 下执行 `flutter --version`（证明没被覆盖）
3. `main` 工作树、`.github/workflows/ci.yml` 未被改

不过：停止。不要实现相机、插件、Rust。回复用户：第 0 期失败，按规格改评纯 ArkTS。

- [x] **Step 6: Commit**

```bash
git add ohos tool/ohos/toolchain_probe.md
git commit -m "chore(ohos): add empty HAP toolchain spike"
```

---

### Task 1: 工程骨架与联邦插件空实现

**Files:**
- Modify: `packages/sitemark_system_api/pubspec.yaml`
- Create: `packages/sitemark_system_api/lib/src/ohos/ohos_system_api.dart`
- Create: `packages/sitemark_system_api/lib/src/ohos/ohos_platform_services.dart`
- Create: `packages/sitemark_system_api/test/ohos_platform_services_test.dart`
- Create: `packages/sitemark_system_api/ohos/index.ets`（或该 fork 要求的 plugin 入口）
- Create: `packages/sitemark_system_api/ohos/src/main/ets/SiteMarkSystemPlugin.ets`
- Create: `packages/sitemark_system_api/ohos/oh-package.json5`
- Modify: `packages/sitemark_system_api/lib/sitemark_system_api.dart`（export ohos 实现，不改 Pigeon export）
- Modify: `lib/app.dart`（仅 `ohos` 分支：`platformServicesProvider` / `backgroundWorkClientProvider` 的构造）
- Create: `lib/platform/ohos_capability.dart`（`bool get isOhosBuild`，编译期常量，禁止散落到页面）
- Modify: `pubspec.yaml` 仅当 ohos 插件补丁需要 dependency_overrides；overrides 不得出现在 `main`
- Test: `test/widget_test.dart`（主界面仍能泵起来）

**Interfaces:**
- Consumes: `PlatformServices` 现有方法；Pigeon DTO：`CameraCaptureResult`、`CameraOutcome`、`RecoveredCameraCapture`、`LocationResult`、`LocationOutcome`、`LocationPermissionState`、`ImageMetadataResult`、`ArchiveSaveOutcome`
- Produces:
  - `const MethodChannel ohosSystemChannel = MethodChannel('sitemark.system.ohos');`
  - `class OhosSystemApi` 方法名与 `SiteMarkSystemApi` 相同
  - `class OhosPlatformServices implements PlatformServices`
  - `class UnimplementedOhosBackgroundWorkClient implements BackgroundWorkClient`（Task 1 只保证 UI 启动，enqueue 抛稳定 `OhosCapabilityException.queueNotReady`）
  - `bool get isOhosBuild`（`bool.fromEnvironment('SITEMARK_OHOS', defaultValue: false)` 或 fork 提供的 `Platform.operatingSystem == 'ohos'`）

- [ ] **Step 1: 写失败测试 — 空实现必须映射成 `PlatformServices`，且未实现方法有稳定错误码**

创建 `packages/sitemark_system_api/test/ohos_platform_services_test.dart`：

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/ohos_platform_services.dart';
import 'package:sitemark/platform/platform_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OhosPlatformServices implements PlatformServices', () {
    expect(OhosPlatformServices(), isA<PlatformServices>());
  });

  test('unimplemented publishJpeg throws stable capability code', () async {
    final services = OhosPlatformServices();
    expect(
      () => services.publishJpeg('/tmp/a.jpg', 'IMG-0001', 'capture-1', null),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'ohos_not_ready'),
      ),
    );
  });

  test('channel name is stable', () {
    expect(ohosSystemChannel.name, 'sitemark.system.ohos');
  });
}
```

若测试无法直接 import `package:sitemark/platform/platform_services.dart`（插件包测 app 包），把 `implements` 断言放到 `test/platform/ohos_platform_services_test.dart`，插件包测试只断言 channel 名与 `OhosSystemApi` 方法存在。

- [ ] **Step 2: 运行测试，确认因文件不存在而失败**

```bash
flutter test packages/sitemark_system_api/test/ohos_platform_services_test.dart test/platform/ohos_platform_services_test.dart
```

Expected: FAIL，`ohos_platform_services.dart` 不存在。

- [ ] **Step 3: 写最小 Dart 空实现**

`packages/sitemark_system_api/lib/src/ohos/ohos_system_api.dart`：

```dart
import 'package:flutter/services.dart';

const MethodChannel ohosSystemChannel = MethodChannel('sitemark.system.ohos');

class OhosSystemApi {
  OhosSystemApi({MethodChannel? channel}) : _channel = channel ?? ohosSystemChannel;

  final MethodChannel _channel;

  Future<T> _invoke<T>(String method, [dynamic args]) async {
    try {
      final result = await _channel.invokeMethod<T>(method, args);
      return result as T;
    } on MissingPluginException {
      throw PlatformException(code: 'ohos_not_ready', message: method);
    }
  }

  Future<String> createCameraTarget(String captureId) =>
      _invoke('createCameraTarget', {'captureId': captureId});

  Future<Map<Object?, Object?>> launchCamera(String captureId) =>
      _invoke('launchCamera', {'captureId': captureId});

  Future<Map<Object?, Object?>?> recoverCameraCapture() =>
      _invoke('recoverCameraCapture');

  Future<void> finishCameraCapture(String captureId, bool keepOriginal) =>
      _invoke('finishCameraCapture', {
        'captureId': captureId,
        'keepOriginal': keepOriginal,
      });

  Future<int> getLocationPermissionState() =>
      _invoke('getLocationPermissionState');

  Future<int> requestLocationPermission() =>
      _invoke('requestLocationPermission');

  Future<void> openApplicationSettings() => _invoke('openApplicationSettings');

  Future<Map<Object?, Object?>> inspectImage(String path) =>
      _invoke('inspectImage', {'path': path});

  Future<Map<Object?, Object?>> requestCurrentLocation(int timeoutMillis) =>
      _invoke('requestCurrentLocation', {'timeoutMillis': timeoutMillis});

  Future<Map<Object?, Object?>> publishJpeg(
    String sourcePath,
    String displayName,
    String captureId,
    String? publishedUri,
  ) =>
      _invoke('publishJpeg', {
        'sourcePath': sourcePath,
        'displayName': displayName,
        'captureId': captureId,
        'publishedUri': publishedUri,
      });

  Future<List<Object?>?> recoverPublishJournals() =>
      _invoke('recoverPublishJournals');

  Future<void> clearPublishJournal(
    String captureId,
    String expectedContentUri,
  ) =>
      _invoke('clearPublishJournal', {
        'captureId': captureId,
        'expectedContentUri': expectedContentUri,
      });

  Future<int> saveArchive(String sourcePath, String suggestedName) =>
      _invoke('saveArchive', {
        'sourcePath': sourcePath,
        'suggestedName': suggestedName,
      });

  Future<void> deletePublishedImage(String contentUri) =>
      _invoke('deletePublishedImage', {'contentUri': contentUri});
}
```

`OhosPlatformServices` 按 `PigeonPlatformServices` 同样方式把 Map 解成 `CameraCaptureResult` / `PublishJpegOutcome` / `RecoveredPublishJournalEntry`。未接宿主时保持 `ohos_not_ready`。枚举用 index 传输，与 Pigeon 一致：

- `CameraOutcome`: 0 captured, 1 cancelled, 2 failed
- `ArchiveSaveOutcome`: 0 saved, 1 cancelled
- `LocationOutcome`: 0 precise … 5 unavailable
- `LocationPermissionState`: 0 granted, 1 denied, 2 permanentlyDenied

`MediaPublishResult` JSON：

```json
{ "contentUri": "file://...", "supersededUris": ["..."] }
```

`RecoveredPublishJournal` JSON：

```json
{ "captureId": "...", "contentUri": "...", "supersededUris": ["..."] }
```

ArkTS 插件入口先对所有 method 抛 `ohos_not_ready`，只保证 engine attach 不崩。

`packages/sitemark_system_api/pubspec.yaml` 增加（字段名以该 Flutter fork 为准，常见是 `ohos`）：

```yaml
flutter:
  plugin:
    platforms:
      android:
        package: io.github.wikg1018.sitemark.system
        pluginClass: SiteMarkSystemPlugin
      ohos:
        pluginClass: SiteMarkSystemPlugin
```

- [ ] **Step 4: 接线，主界面能进，不接相机**

`lib/platform/ohos_capability.dart`：

```dart
bool get isOhosBuild =>
    const bool.fromEnvironment('SITEMARK_OHOS') ||
    identical(0, 0) && _ohosOs;

bool get _ohosOs {
  try {
    return const String.fromEnvironment('OHOS_PLATFORM').isNotEmpty;
  } catch (_) {
    return false;
  }
}
```

不要用上面的占位判断。实现时按社区 Flutter 实际 API 选 **一个** 稳定探测：

1. `Platform.operatingSystem == 'ohos'`，或
2. `--dart-define=SITEMARK_OHOS=true` 写进 `ohos/` 构建脚本

`lib/app.dart` 仅改两处 provider 的构造（业务对象仍是同一接口）：

```dart
final platformServicesProvider = Provider<PlatformServices>(
  (ref) => isOhosBuild ? OhosPlatformServices() : PigeonPlatformServices(),
);

final backgroundWorkClientProvider = Provider<BackgroundWorkClient>((ref) {
  return isOhosBuild
      ? UnimplementedOhosBackgroundWorkClient()
      : WorkmanagerBackgroundWorkClient();
});
```

`UnimplementedOhosBackgroundWorkClient.initialize` 为空成功（避免启动即炸）。`appendCapture` 抛 `StateError('ohos_queue_not_ready')`。Task 1 不点拍摄。

ohos 上若 `dynamic_color` / `flutter_local_notifications` / `workmanager` 编不过：在 `ohos` 分支 `pubspec.yaml` 用 fork 替代或条件禁用，并在 `tool/ohos/toolchain_probe.md` 记入差异表（通知关、动态取色关）。**不要改 `main` 的 pubspec。**

- [ ] **Step 5: 跑测试并真机进主界面**

```bash
flutter test packages/sitemark_system_api/test/ohos_platform_services_test.dart test/widget_test.dart
"%OHOS_FLUTTER_ROOT%\bin\flutter" build hap --debug
```

Expected: 单测绿。真机冷启动进入项目列表（空库也行）。`main` checkout 上 `flutter test test/widget_test.dart` 仍绿（抽查，证明没污染）。

- [ ] **Step 6: Commit**

```bash
git add packages/sitemark_system_api lib/app.dart lib/platform/ohos_capability.dart pubspec.yaml pubspec.lock
git commit -m "feat(ohos): add federated system-api stub and launch UI"
```

---

### Task 2: 系统契约 — 相机、定位、会话恢复、相册探测

**Files:**
- Create: `packages/sitemark_system_api/lib/src/ohos/capture_session_store.dart`
- Create: `packages/sitemark_system_api/lib/src/ohos/capture_target_policy.dart`
- Create: `packages/sitemark_system_api/lib/src/ohos/gallery_access.dart`
- Create: `packages/sitemark_system_api/test/capture_session_store_test.dart`
- Create: `packages/sitemark_system_api/test/capture_target_policy_test.dart`
- Create: `packages/sitemark_system_api/test/gallery_access_test.dart`
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/SiteMarkSystemPlugin.ets`
- Create: `packages/sitemark_system_api/ohos/src/main/ets/CameraBridge.ets`
- Create: `packages/sitemark_system_api/ohos/src/main/ets/LocationBridge.ets`
- Create: `packages/sitemark_system_api/ohos/src/main/ets/GalleryProbe.ets`
- Modify: `ohos/entry/src/main/module.json5`（相机、麦克风如系统相机需要、精确定位按需、相册 ACL 声明）
- Modify: `lib/l10n/app_strings.dart`（相册探测降级文案先加字符串，UI 挂载可到 Task 4/5）
- Test: `test/workflow/capture_workflow_test.dart`（回归，不改断言）

**Interfaces:**
- Consumes: `createCameraTarget` / `launchCamera` / `recoverCameraCapture` / `finishCameraCapture`；`getLocationPermissionState` / `requestLocationPermission` / `requestCurrentLocation` / `openApplicationSettings`
- Produces:
  - `class CaptureTargetPolicy { static String fileName(String captureId); static bool isCaptured({required bool exists, required int length}); }`
  - `class CaptureSessionStore { Future<void> write({required String captureId, required String outputPath}); Future<RecoveredCameraCapture?> recover(); Future<void> clear(); }`
  - `enum GalleryAccessMode { acl, pickerFallback }`
  - `class GalleryAccessProbe { Future<GalleryAccessMode> detect(); }`
  - 相机成功：原图落到应用沙箱 `originals/<captureId>.jpg`（与 Android `CaptureTargetPolicy.fileName` 相同：`^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$` + `.jpg`）
  - 定位失败返回 `LocationOutcome` 枚举，不抛、不阻断拍摄

- [ ] **Step 1: 写失败测试 — 目标文件名与恢复判定**

`packages/sitemark_system_api/test/capture_target_policy_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/capture_target_policy.dart';

void main() {
  test('accepts the same capture id alphabet as Android', () {
    expect(CaptureTargetPolicy.fileName('capture-1'), 'capture-1.jpg');
    expect(CaptureTargetPolicy.fileName('A' * 96), 'A' * 96 + '.jpg');
  });

  test('rejects empty, dotted, or overlong ids', () {
    expect(() => CaptureTargetPolicy.fileName(''), throwsArgumentError);
    expect(() => CaptureTargetPolicy.fileName('bad.id'), throwsArgumentError);
    expect(() => CaptureTargetPolicy.fileName('A' * 97), throwsArgumentError);
  });

  test('recovery treats missing or empty file as cancelled', () {
    expect(CaptureTargetPolicy.isCaptured(exists: true, length: 12), isTrue);
    expect(CaptureTargetPolicy.isCaptured(exists: true, length: 0), isFalse);
    expect(CaptureTargetPolicy.isCaptured(exists: false, length: 0), isFalse);
  });
}
```

`packages/sitemark_system_api/test/capture_session_store_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/capture_session_store.dart';

void main() {
  test('recover returns the durable session and clear is idempotent', () async {
    final prefs = MemoryKeyValueStore();
    final store = CaptureSessionStore(prefs);
    await store.write(captureId: 'capture-1', outputPath: '/docs/originals/capture-1.jpg');

    final first = await store.recover();
    expect(first!.captureId, 'capture-1');
    expect(first.outputPath, '/docs/originals/capture-1.jpg');

    await store.clear();
    expect(await store.recover(), isNull);
    await store.clear();
  });

  test('write replaces the previous unfinished session', () async {
    final store = CaptureSessionStore(MemoryKeyValueStore());
    await store.write(captureId: 'old', outputPath: '/old.jpg');
    await store.write(captureId: 'new', outputPath: '/new.jpg');
    expect((await store.recover())!.captureId, 'new');
  });
}
```

`packages/sitemark_system_api/test/gallery_access_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/gallery_access.dart';

void main() {
  test('granted ACL selects acl mode', () async {
    final probe = GalleryAccessProbe(reader: () async => true);
    expect(await probe.detect(), GalleryAccessMode.acl);
  });

  test('denied ACL selects picker fallback, not failure', () async {
    final probe = GalleryAccessProbe(reader: () async => false);
    expect(await probe.detect(), GalleryAccessMode.pickerFallback);
  });
}
```

- [ ] **Step 2: 运行测试确认先红**

```bash
flutter test packages/sitemark_system_api/test/capture_target_policy_test.dart packages/sitemark_system_api/test/capture_session_store_test.dart packages/sitemark_system_api/test/gallery_access_test.dart
```

Expected: FAIL，类型不存在。

- [ ] **Step 3: 实现 Dart 策略（不含 PhotoAccessHelper）**

`CaptureTargetPolicy` 直接移植 Android `CaptureTargetPolicy` 的正则与 `exists && length > 0` 判定。

`CaptureSessionStore` 键名固定：

- `capture_id`
- `capture_path`

写入必须同步持久化语义：`MemoryKeyValueStore` 测试用 Map；真机用 ohos Preferences，`commit` 失败要让 `write` 返回/抛给宿主，不能 `apply` 完就当成功。

`GalleryAccessProbe` 只问 `reader()`，不在业务层写 if。Task 2 的 ArkTS `GalleryProbe` 读 `ohos.permission.READ_IMAGEVIDEO` + `WRITE_IMAGEVIDEO`（或当期 AGC 文档中的等价受限权限）。未授权 → `pickerFallback`。

- [ ] **Step 4: 实现 ArkTS 相机 / 定位**

`createCameraTarget`：

1. 校验 `captureId`
2. 在应用文件目录创建 `originals/<id>.jpg` 占位（0 字节允许）
3. `CaptureSessionStore.write`
4. 返回绝对路径字符串

`launchCamera`：

1. 拉起系统相机 / 拍照 Ability
2. 若系统相机不能直写私有路径：拍到临时 URI，再拷贝到 `originals/<id>.jpg`
3. 拷贝后文件 `length > 0` → `{outcome: 0, outputPath, errorMessage: null}`
4. 用户取消 → `{outcome: 1, outputPath, errorMessage: null}`，保留会话给 `finishCameraCapture` 清
5. 无 Ability / 失败 → `{outcome: 2, outputPath, errorMessage: null}`（不要把系统异常字符串塞进 `errorMessage` 给 UI；最多内部打日志）

`recoverCameraCapture`：读会话；用 `CaptureTargetPolicy.isCaptured` 填 `hasContent`。

`finishCameraCapture(captureId, keepOriginal)`：`keepOriginal == false` 时删占位文件；无论 keep 与否都 `clear` 会话。

定位：

- 启动不申请
- `requestCurrentLocation(timeoutMillis)`：超时 → `LocationOutcome.timeout`（index 4）；拒权 → `permissionDenied`（2）；无服务 → `servicesDisabled`（3）
- 坐标可空

`module.json5` 只声明实际会用的权限，并准备 Task 5 要用的用途说明字符串（可先写进 json5，弹窗在 Task 5）。

- [ ] **Step 5: 跑策略测试 + 现网工作流回归 + 真机手工**

```bash
flutter test packages/sitemark_system_api/test/capture_target_policy_test.dart packages/sitemark_system_api/test/capture_session_store_test.dart packages/sitemark_system_api/test/gallery_access_test.dart test/workflow/capture_workflow_test.dart
```

Expected: PASS。

真机手工（不过就停在 Task 2，不接队列）：

1. 建项目 → 填表 → 系统相机 → 确认 → 库里有 `captured` 或至少有记录
2. 取消拍照 → 不占编号
3. 拍完立刻杀进程再进 App → `recoverCameraCapture` 能补记（走现有 `AppStartupRecovery.recoverCamera`）
4. 拒绝定位仍能拍

- [ ] **Step 6: Commit**

```bash
git add packages/sitemark_system_api ohos lib/l10n/app_strings.dart
git commit -m "feat(ohos): implement camera session, location, and gallery probe"
```

---

### Task 3: Rust `ohos-arm64` 水印引擎

**Files:**
- Modify: `rust/Cargo.toml`（仅在需要时加 ohos target 条件依赖，默认不改 crate API）
- Modify: `rust_builder/pubspec.yaml`（增加 `ohos: ffiPlugin: true`）
- Create: `rust_builder/ohos/`（该 fork 的 ffi 插件目录，通常含 `CMakeLists.txt` 或 hvigor 钩子）
- Modify: `rust_builder/cargokit/lib/src/target.dart`（登记 `aarch64-unknown-linux-ohos` 或 fork 文档中的 triple）
- Create: `tool/ohos/engine_status.md`（`ok` / `degraded` + 命令输出摘要）
- Modify: `lib/platform/platform_services.dart` **禁止**改 `RustImagePipeline` 签名。若必须降级，新增 `lib/platform/degraded_image_pipeline.dart` 实现同一 `ImagePipeline` 接口
- Test: `test/platform/platform_services_test.dart`（现有 Rust 错误前缀解析继续绿）
- Create: `test/platform/degraded_image_pipeline_test.dart`（仅当走降级通道时）

**Interfaces:**
- Consumes: 现网 `ImagePipeline`（`lib/platform/platform_services.dart`），方法是 `render` / `export` / `exportSelection` / `readProjectArchive` / `extractArchivePhoto` / `sha256`，不是 `renderToFile`，也不是直接暴露 `renderPhoto`
- Produces:
  - 成功：`ohos-arm64` 共享库被 HAP 打包，`RustLib.init()` 在鸿蒙前台 isolate 成功；`imagePipelineProvider` 仍是 `RustImagePipeline`
  - 失败：`DegradedImagePipeline implements ImagePipeline`，六个方法都要有实现或稳定错误；渲染结果文件存在但必须让 UI / 发布说明可读到“降级水印”；备份/导出若未实现则抛 `ImagePipelineException.tryParseRustError` 能识别的 `invalid_data:` 前缀，并在 `engine_status.md` 标明备份亦降级；**不得**把 `imagePipelineProvider` 在页面里 if 掉

- [ ] **Step 1: 写失败测试 — provider 在降级模式下仍是 `ImagePipeline`，且带稳定标记**

先假设引擎可能失败，把降级通道的契约测死，避免以后随手改页面：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/platform/degraded_image_pipeline.dart';
import 'package:sitemark/platform/platform_services.dart';

void main() {
  test('degraded pipeline implements ImagePipeline and reports degraded', () {
    const pipeline = DegradedImagePipeline();
    expect(pipeline, isA<ImagePipeline>());
    expect(pipeline.isDegraded, isTrue);
  });
}
```

给现有 `ImagePipeline` 增加只读 `bool get isDegraded => false;`，默认实现 false，避免改每个调用点。`RustImagePipeline` 不 override（保持 false）。只允许 `DegradedImagePipeline` 为 true。

- [ ] **Step 2: 运行测试确认先红**

```bash
flutter test test/platform/degraded_image_pipeline_test.dart
```

Expected: FAIL，`isDegraded` / `DegradedImagePipeline` 不存在。

- [ ] **Step 3: 先给现网接口加 `isDegraded`，再编 Rust**

只改 `lib/platform/platform_services.dart` 里现有 `abstract interface class ImagePipeline`：增加 `bool get isDegraded => false;`，其余六个方法签名一字不改：

```dart
abstract interface class ImagePipeline {
  bool get isDegraded => false;

  Future<rust.ExportProjectResult> export(rust.ExportProjectRequest request);
  Future<rust.ExportProjectResult> exportSelection(
    rust.ExportSelectionRequest request,
  );
  Future<rust.ProjectArchivePreview> readProjectArchive(String zipPath);
  Future<rust.ExtractedArchivePhoto> extractArchivePhoto(
    rust.ExtractArchivePhotoRequest request,
  );
  Future<String> sha256(String path);
  Future<rust.RenderPhotoResult> render(rust.RenderPhotoRequest request);
}
```

`DegradedImagePipeline.render`：复制原图到 `request` 指定输出路径，叠一行纯文本 “SiteMark”，返回与 `RustImagePipeline.render` 同形状的 `RenderPhotoResult`（字段以 `lib/src/rust/api/image_core.dart` 为准）。`sha256` 可用 Dart 算同一文件。`export` / `exportSelection` / `readProjectArchive` / `extractArchivePhoto` 若本任务做不了 ZIP：抛字符串以 `invalid_data:` 开头的错误，让现有 `ImagePipelineException.tryParseRustError` 能解析。

然后在 `ohos` 分支交叉编译：

```bash
rustup target add aarch64-unknown-linux-ohos
cd rust
cargo build --release --target aarch64-unknown-linux-ohos
```

若 triple 不是这个名字，以 OHOS Rust SDK 文档为准，并把 **实际 triple** 写进 `tool/ohos/engine_status.md`。不要在计划执行时 invent 第二个 crate。

`flutter_rust_bridge` 2.12.0 若官方不支持 ohos：允许改为手工 `cdylib` + 现有生成的 Dart API 仍调用同一导出符号；**禁止**换水印算法或另写一套版式。

- [ ] **Step 4: 接进 HAP 并做版式对照**

成功路径：`initializeForegroundRust()` 在鸿蒙启动后仍只调用一次 `RustLib.init()`。`imagePipelineProvider` 继续 `RustImagePipeline()`。

失败路径：`imagePipelineProvider` 在 `isOhosBuild && rustInitFailed` 时给 `DegradedImagePipeline`。`rustInitFailed` 放在 `lib/platform/ohos_capability.dart` 的一个 `ValueNotifier`/`Provider`，不要写进 `CaptureProcessor`。

`DegradedImagePipeline` 最小行为：把原图 JPEG 复制到输出路径并画一行纯文本“SiteMark”（可用 `package:image` 或 ohos 原生编解码）。字段顺序仍尽量带上工程部位 / 工作内容 / 拍摄人 / 时间；做不到像素级对等。

- [ ] **Step 5: 验证**

```bash
flutter test test/platform/platform_services_test.dart test/platform/degraded_image_pipeline_test.dart test/workflow/capture_processor_test.dart
```

Expected: PASS。

真机：拍一张，对比 Android v1.0.8 同字段成片。

- `engine_status.md` 写 `ok`：版式对得上 → 可进入 Task 4 并保留对等资格
- 写 `degraded`：可进 Task 4 做出片闭环，但发布说明必须写“降级水印”，不得称全量对等

- [ ] **Step 6: Commit**

```bash
git add rust rust_builder lib/platform tool/ohos/engine_status.md test/platform/degraded_image_pipeline_test.dart
git commit -m "feat(ohos): build watermark engine for ohos-arm64"
```

---

### Task 4: 串行队列、发布日记、删除 / 再生成 / 再发布 / 备份

**Files:**
- Create: `lib/platform/ohos_background_work_client.dart`
- Create: `test/platform/ohos_background_work_client_test.dart`
- Create: `packages/sitemark_system_api/lib/src/ohos/publish_journal_store.dart`
- Create: `packages/sitemark_system_api/test/publish_journal_store_test.dart`
- Create: `packages/sitemark_system_api/lib/src/ohos/gallery_store.dart`
- Create: `packages/sitemark_system_api/test/gallery_store_test.dart`
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/PhotoPublisher.ets`
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/SiteMarkSystemPlugin.ets`
- Modify: `lib/app.dart`（`backgroundWorkClientProvider` 换成 `InAppSerialBackgroundWorkClient`）
- Modify: `lib/l10n/app_strings.dart` + 记录详情 / 设置里展示“未进入系统相册”
- Test: `test/background/capture_background_scheduler_test.dart`
- Test: `test/workflow/capture_media_service_test.dart`
- Test: `test/workflow/capture_processor_test.dart`
- Test: `test/workflow/app_startup_recovery_test.dart`
- Test: `test/workflow/project_bundle_service_test.dart`（若 ohos 分支已含备份测试）

**Interfaces:**
- Consumes:
  - `BackgroundWorkClient.initialize(void Function() dispatcher)`
  - `BackgroundWorkClient.appendCapture({required String queueName, required String taskName, required String captureId, required String tag})`
  - `captureProcessingTask = 'sitemark.processCapture'`
  - `captureProcessingQueue = 'sitemark-render-queue'`
  - `PublishJpegOutcome({required contentUri, supersededUris = const []})`
  - `RecoveredPublishJournalEntry({required captureId, required contentUri, required supersededUris})`
  - `CaptureMediaService._recoverPublishJournals` 的现网分支（不要重写）
- Produces:
  - `class InAppSerialBackgroundWorkClient implements BackgroundWorkClient`
  - `class HarmonyPublishJournalStore`：`record` / `peek` / `recover` / `clear`
  - `abstract interface class GalleryStore`
  - `class AclGalleryStore implements GalleryStore`
  - `class PickerFallbackStore implements GalleryStore`
  - `class ProbingGalleryStore implements GalleryStore`（内部选 store，业务只调 `publish` / `delete`）
  - `class GalleryPublishResult { final String contentUri; final List<String> supersededUris; final bool enteredSystemAlbum; }`

**发布语义（必须按此实现，不要按“原生删旧图”实现）：**

1. `peek(captureId)` 取出未完成日记
2. 把新 JPEG 写入 ACL 相册或 picker / 沙箱，得到 `contentUri`
3. `superseded = {publishedUri?, peek.contentUri, ...peek.supersededUris}` 去空去重，且不含新 `contentUri`
4. **同步** `record(captureId, contentUri, superseded)`；`record` 失败则整次 `publishJpeg` 失败，且不要声称成功
5. 返回 `PublishJpegOutcome(contentUri, supersededUris: superseded)` —— **不要在宿主里 delete**
6. Dart `CaptureProcessor` / `CaptureMediaService.republish` 提交 Drift 后 `clearPublishJournal(id, contentUri)`
7. 引用检查删除走现有 `enqueueSupersededCleanups` + `deletePublishedImage`

日记 key 布局与 Android 对齐，避免以后双端对账文档分叉：

- `journal.<base64url(captureId)>.exists`
- `journal.<base64url(captureId)>.newUri`
- `journal.<base64url(captureId)>.staleCount`
- `journal.<base64url(captureId)>.stale.<i>`

`clear`：当前 `newUri != expectedContentUri` 时返回 false 且不删；缺省条目返回 true。

- [ ] **Step 1: 写失败测试 — 日记**

`packages/sitemark_system_api/test/publish_journal_store_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/publish_journal_store.dart';

void main() {
  test('record recover round-trips captureId not photo number', () {
    final store = HarmonyPublishJournalStore(MemoryKeyValueStore());
    expect(
      store.record(
        captureId: 'capture-1',
        contentUri: 'ph://new',
        supersededUris: ['ph://old'],
      ),
      isTrue,
    );
    final entry = store.recover().single;
    expect(entry.captureId, 'capture-1');
    expect(entry.contentUri, 'ph://new');
    expect(entry.supersededUris, ['ph://old']);
  });

  test('clear is conditional on expectedContentUri', () {
    final store = HarmonyPublishJournalStore(MemoryKeyValueStore());
    store.record(captureId: 'c1', contentUri: 'ph://v2', supersededUris: ['ph://v1']);
    expect(store.clear('c1', 'ph://v1'), isFalse);
    expect(store.recover().single.contentUri, 'ph://v2');
    expect(store.clear('c1', 'ph://v2'), isTrue);
    expect(store.recover(), isEmpty);
    expect(store.clear('c1', 'ph://v2'), isTrue);
  });

  test('same-capture record folds previous uri into later peek', () {
    final store = HarmonyPublishJournalStore(MemoryKeyValueStore());
    store.record(captureId: 'c1', contentUri: 'ph://v1', supersededUris: ['ph://v0']);
    store.record(captureId: 'c1', contentUri: 'ph://v2', supersededUris: ['ph://v1', 'ph://v0']);
    expect(store.peek('c1')!.contentUri, 'ph://v2');
    expect(store.peek('c1')!.supersededUris, ['ph://v1', 'ph://v0']);
  });

  test('hostile capture ids stay in a safe key alphabet', () {
    final prefs = MemoryKeyValueStore();
    final store = HarmonyPublishJournalStore(prefs);
    const hostile = 'cap\u0000.id.值📷';
    expect(store.record(captureId: hostile, contentUri: 'ph://x', supersededUris: const []), isTrue);
    for (final key in prefs.keys) {
      expect(RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(key), isTrue);
    }
    expect(store.recover().single.captureId, hostile);
  });
}
```

- [ ] **Step 2: 写失败测试 — 相册适配器**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/gallery_store.dart';

void main() {
  test('ACL publish reports only the passed publishedUri plus leftover journal', () async {
    final photos = MemoryPhotoAccess();
    final store = AclGalleryStore(photos);
    photos.seed('ph://old', bytes: [1]);
    final result = await store.publish(
      sourcePath: '/tmp/new.jpg',
      displayName: 'IMG-0001',
      captureId: 'c1',
      publishedUri: 'ph://old',
      leftoverJournalUris: ['ph://leftover'],
    );
    expect(result.contentUri, isNot('ph://old'));
    expect(result.supersededUris, containsAll(['ph://old', 'ph://leftover']));
    expect(result.enteredSystemAlbum, isTrue);
    expect(photos.exists('ph://old'), isTrue, reason: 'native must not delete');
  });

  test('ACL publish never scans by display name', () async {
    final photos = MemoryPhotoAccess();
    final store = AclGalleryStore(photos);
    photos.seed('ph://other', displayName: 'IMG-0001', bytes: [9]);
    final result = await store.publish(
      sourcePath: '/tmp/new.jpg',
      displayName: 'IMG-0001',
      captureId: 'c1',
      publishedUri: null,
      leftoverJournalUris: const [],
    );
    expect(result.supersededUris, isEmpty);
    expect(photos.exists('ph://other'), isTrue);
  });

  test('picker fallback does not claim system album parity', () async {
    final store = PickerFallbackStore(MemorySandbox());
    final result = await store.publish(
      sourcePath: '/tmp/new.jpg',
      displayName: 'IMG-0001',
      captureId: 'c1',
      publishedUri: null,
      leftoverJournalUris: const [],
    );
    expect(result.enteredSystemAlbum, isFalse);
    expect(result.contentUri, startsWith('file://'));
  });
}
```

- [ ] **Step 3: 写失败测试 — 串行队列客户端**

`test/platform/ohos_background_work_client_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/platform/ohos_background_work_client.dart';

void main() {
  test('appendCapture runs one capture at a time in enqueue order', () async {
    final started = <String>[];
    final client = InAppSerialBackgroundWorkClient(
      runner: (captureId) async {
        started.add(captureId);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
    );
    await client.initialize(() {});
    unawaited(client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'c1',
      tag: 'capture:c1',
    ));
    unawaited(client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'c2',
      tag: 'capture:c2',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(started, ['c1']);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(started, ['c1', 'c2']);
  });

  test('same captureId replaces a not-yet-running item', () async {
    final started = <String>[];
    final gate = Completer<void>();
    var c1Runs = 0;
    final client = InAppSerialBackgroundWorkClient(
      runner: (captureId) async {
        if (captureId == 'c1') c1Runs += 1;
        started.add(captureId);
        if (captureId == 'hold') await gate.future;
      },
    );
    await client.initialize(() {});
    await client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'hold',
      tag: 'capture:hold',
    );
    await client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'c1',
      tag: 'capture:c1',
    );
    await client.appendCapture(
      queueName: captureProcessingQueue,
      taskName: captureProcessingTask,
      captureId: 'c1',
      tag: 'capture:c1',
    );
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c1Runs, 1);
  });
}
```

`InAppSerialBackgroundWorkClient` 的 `initialize` 保存 `dispatcher` 但不走 WorkManager。生产 `runner` 调现有 `buildHeadlessCaptureProcessor` 所服务的同一套 `CaptureProcessor.process(captureId)`（可在前台 isolate 串行执行）。进程被杀后靠启动 `reconcilePending`；若 fork 提供 `WorkScheduler` / 前台任务，只用于拉起 App，不另开第二条处理链。

- [ ] **Step 4: 运行以上新测试，确认先红**

```bash
flutter test packages/sitemark_system_api/test/publish_journal_store_test.dart packages/sitemark_system_api/test/gallery_store_test.dart test/platform/ohos_background_work_client_test.dart
```

Expected: FAIL，实现不存在。

- [ ] **Step 5: 写最小实现并接宿主**

`HarmonyPublishJournalStore.record` 必须在持久化失败时返回 `false`（测试里给 `MemoryKeyValueStore.commitFails = true`）。

`AclGalleryStore` 通过 `PhotoAccessHelper` 写入尽量位于 `Pictures/SiteMark` 的应用创建资源，返回稳定 URI（`uri.toString()`）。替换 = 新写 + 把旧 URI 放进 `supersededUris`，不是改文件名覆盖。

`PickerFallbackStore`：拉系统保存 picker；用户取消视为可重试失败（处理器会按尝试次数回队），不要标 `failed` 永久失败。取消不得假装 `contentUri` 成功。

`ProbingGalleryStore.publish`：`detect()` 一次缓存到进程内；权限中途变化下次冷启动再生效即可。

`deletePublishedImage`：按 URI 删；已不存在当成功。无 ACL 时只能删 `file://` 沙箱或本应用创建的 picker 文档。

`lib/app.dart`：

```dart
final backgroundWorkClientProvider = Provider<BackgroundWorkClient>((ref) {
  return isOhosBuild
      ? InAppSerialBackgroundWorkClient(
          runner: (captureId) => processCaptureOnOhos(captureId, ref),
        )
      : WorkmanagerBackgroundWorkClient();
});
```

`processCaptureOnOhos` 建与 `buildHeadlessCaptureProcessor` 相同的 `CaptureProcessor`（`OhosPlatformServices` + 当前 `ImagePipeline` + 同一 `AppDatabase` 文件）。通知：ohos 无插件就让 `sendCaptureReadyNotificationIfEnabled` 继续走现有 service；service 内部初始化失败必须吞掉，不能失败整次处理（与 Android “通知 best-effort” 一致）。

文案（`lib/l10n/app_strings.dart`）：

```dart
String get galleryNotInSystemAlbum =>
    _english ? 'Not saved to the system gallery' : '未进入系统相册';
String get galleryPickerFallbackHint => _english
    ? 'Photos stay in the app sandbox or a file you pick. This is not full Android parity.'
    : '成片留在应用沙箱或你选择的保存位置，尚未进入系统相册，不能称为与 Android 全量对等。';
String get watermarkEngineDegraded =>
    _english ? 'Degraded watermark engine' : '降级水印引擎';
```

在记录详情水印预览附近：`!enteredSystemAlbum` 时显示 `galleryNotInSystemAlbum`。`enteredSystemAlbum` 不要塞进 Drift 新列除非现有库已有地方可挂；优先从 `ProbingGalleryStore.lastMode` / 启动探测缓存读，避免改 schema。

- [ ] **Step 6: 跑业务门禁 + 真机杀进程四窗**

```bash
flutter test test/background/capture_background_scheduler_test.dart test/workflow/capture_processor_test.dart test/workflow/capture_media_service_test.dart test/workflow/app_startup_recovery_test.dart test/workflow/capture_workflow_test.dart packages/sitemark_system_api/test/publish_journal_store_test.dart packages/sitemark_system_api/test/gallery_store_test.dart test/platform/ohos_background_work_client_test.dart
```

Expected: PASS。这些测试继续用 fake `PlatformServices` / fake `BackgroundWorkClient` 锁状态机；鸿蒙实现不得逼它们改断言。

真机清单（规格验收）：

1. 连拍编号不乱，同一时间只出一张
2. 杀进程：相机半截 / 队列未跑完 / 相册已写库未提交 / 日记与 Drift CAS
3. 删除：ACL 下系统图消失；picker 下沙箱文件消失
4. 再生成要求原图还在；再发布只对 `ready` 且成片在
5. 备份 ZIP 恢复后，同编号跨项目不得串 URI
6. 拒绝相册 → picker，文案为“未进入系统相册”

- [ ] **Step 7: Commit**

```bash
git add lib/platform/ohos_background_work_client.dart lib/app.dart lib/l10n/app_strings.dart packages/sitemark_system_api test
git commit -m "feat(ohos): add serial queue, gallery publish journal, and media parity"
```

---

### Task 5: 隐私弹窗、权限话术、release HAP、上架材料

**Files:**
- Create: `lib/features/onboarding/privacy_consent_store.dart`
- Create: `lib/features/onboarding/privacy_consent_gate.dart`
- Create: `test/features/onboarding/privacy_consent_gate_test.dart`
- Modify: `lib/app.dart`（根上包一层 gate；首次未同意不进主界面、不申请权限）
- Modify: `lib/l10n/app_strings.dart`
- Modify: `ohos/entry/src/main/module.json5`（权限 reason 与弹窗正文一致）
- Create: `ohos/entry/src/main/resources/base/element/string.json`（AGC 权限用途）
- Create: `tool/ohos/appgallery_checklist.md`（材料清单，不是过审证明）
- Create: `.github/workflows/ohos.yml`（**只在 `ohos` 分支文档里添加**；`on.push.branches: [ohos]`）
- Modify: `lib/features/settings/sections/about_section_screen.dart`（无网 / 无账号声明与鸿蒙权限实际一致）

**Interfaces:**
- Consumes: 现有 `AppStrings.privacyStatements` / `privacySummary`；定位仍按需
- Produces:
  - `class PrivacyConsentStore { Future<bool> isAccepted(); Future<void> accept(); }`
  - `class PrivacyConsentGate` 小部件：未接受只显示说明 +「同意并继续」+「退出」
  - release HAP 构建命令与签名配置
  - AGC 申请 `READ/WRITE_IMAGEVIDEO` 的说明草稿（中文）

- [ ] **Step 1: 写失败测试 — 未同意不得进主界面**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/onboarding/privacy_consent_gate.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  testWidgets('blocks the app until privacy consent is accepted', (tester) async {
    final store = MemoryPrivacyConsentStore(accepted: false);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [AppStrings.delegate],
        supportedLocales: AppStrings.supportedLocales,
        home: PrivacyConsentGate(
          store: store,
          child: const Text('HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsNothing);
    expect(find.text('同意并继续'), findsOneWidget);
  });

  testWidgets('shows home after accept', (tester) async {
    final store = MemoryPrivacyConsentStore(accepted: false);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [AppStrings.delegate],
        supportedLocales: AppStrings.supportedLocales,
        home: PrivacyConsentGate(
          store: store,
          child: const Text('HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(await store.isAccepted(), isTrue);
  });
}
```

文案必须原样加入 `AppStrings`：

```dart
String get privacyConsentTitle => _english ? 'Before you start' : '使用前说明';
String get privacyConsentBody => _english
    ? 'SiteMark works offline. It uses the system camera when you capture, optional location only when you request it, and photo access only to save watermarked photos. There is no account and no cloud sync.'
    : '工程印记离线工作。拍摄时调用系统相机；定位仅在你主动使用时申请；相册权限仅用于保存水印成片。无账号、无云同步。';
String get privacyConsentAgree => _english ? 'Agree and continue' : '同意并继续';
String get privacyConsentExit => _english ? 'Exit' : '退出';
```

- [ ] **Step 2: 运行测试确认先红**

```bash
flutter test test/features/onboarding/privacy_consent_gate_test.dart
```

Expected: FAIL，gate 不存在。

- [ ] **Step 3: 实现 gate 与权限话术**

`PrivacyConsentStore` 用 `shared_preferences` 的 ohos 实现，key：`privacy_consent_accepted_v1`。未同意时「退出」调用 `SystemNavigator.pop()`。

`module.json5` 的 `reason` 必须能对上：

- 相机：用于拍摄现场原图
- 定位：用于水印可选坐标，可在设置关闭
- 图库读写：用于把成片写入系统相册并按本条记录替换 / 删除

关于页 `privacySummary` 若与鸿蒙实际权限不符，只在 `ohos` 分支改文案，写明会申请相册 ACL；无网声明保持。

- [ ] **Step 4: release HAP 与材料**

```bash
"%OHOS_FLUTTER_ROOT%\bin\flutter" build hap --release
```

`tool/ohos/appgallery_checklist.md` 列出并勾选：

1. 软著 / 应用名称「工程印记」或 AGC 允许的英文 SiteMark
2. 隐私政策 URL 或随包文本，与弹窗一致
3. 受限相册 ACL 申请表
4. 权限逐条用途
5. 2–5 张截图（项目列表、拍摄表、成片、设置、隐私弹窗）
6. 若 `engine_status.md` 为 `degraded` 或相册为 picker：发布说明写明非全量对等
7. 签名、包名、versionCode 与 `pubspec.yaml` 对齐

`.github/workflows/ohos.yml`：

```yaml
name: OHOS
on:
  push:
    branches: [ohos]
  pull_request:
    branches: [ohos]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2.21.0
        with:
          flutter-version: '3.32.0'
          channel: stable
      - run: flutter pub get
      - run: flutter test test/platform/ohos_background_work_client_test.dart packages/sitemark_system_api/test test/features/onboarding/privacy_consent_gate_test.dart test/workflow/capture_processor_test.dart test/workflow/capture_media_service_test.dart test/background/capture_background_scheduler_test.dart
```

OHOS CI 机器若没有社区 Flutter，允许 job 先只跑上述不依赖 ohos SDK 的 Dart 测试。**不要**把社区 Flutter 装进 `main` 的 `ci.yml`。

- [ ] **Step 5: 跑 Task 5 测试并做发布自检**

```bash
flutter test test/features/onboarding/privacy_consent_gate_test.dart test/widget_test.dart
"%OHOS_FLUTTER_ROOT%\bin\flutter" build hap --release
```

Expected: 测试绿；产物 HAP 存在。过审本身不是完成定义。

完成定义对照规格：

1. `ohos` 出自 `847c74b`，`main` 没被社区 Flutter 污染
2. 真机：建项目 → 填表 → 系统相机 → 串行出片 → ACL 进相册或明确降级
3. 水印字段与编号规则与 Android 一致（或已标明降级引擎）
4. 杀进程四窗收敛
5. 删除 / 再生成 / 再发布 / 备份按 `captureId`
6. 隐私弹窗 + 能提交 AGC 的材料齐

- [ ] **Step 6: Commit**

```bash
git add lib/features/onboarding lib/app.dart lib/l10n/app_strings.dart lib/features/settings/sections/about_section_screen.dart ohos tool/ohos/appgallery_checklist.md .github/workflows/ohos.yml test/features/onboarding
git commit -m "feat(ohos): add privacy consent and AppGallery release materials"
```

---

## 手工回归总表（Task 4–5 结束时一次跑完）

| 项 | 期望 |
|---|---|
| 取消拍照 | 不占号，无空记录 |
| 连拍 | 编号递增，同时只处理一张 |
| 拒定位 | 仍出片，坐标空 |
| 拒相册 | picker / 沙箱 +「未进入系统相册」 |
| 杀进程四窗 | 都能收敛到 `ready` 或可解释的 `failed`，不丢编号 |
| 删除 | 只删本条稳定 ID |
| 再生成 | 原图缺失则拒绝 |
| 再发布 | 非 `ready` 或成片缺失则拒绝 |
| 备份恢复 | 同编号跨项目 URI 不串 |
| 隐私 | 首次启动先弹窗，未同意不申请权限 |

---

## Self-review

**规格覆盖：**

| 规格项 | 任务 |
|---|---|
| NEXT 原生 HAP、v1.0.8 基线、长期 `ohos` 分支 | Task 0 |
| 空壳模拟器/真机硬闸、失败改评 ArkTS | Task 0 Step 5 |
| `ohos/` 骨架、联邦插件空实现、进主界面、不污染 `main` | Task 1 |
| 相机 / 定位 / 会话恢复 / 相册探测 | Task 2 |
| Rust `ohos-arm64` + 显式降级通道 | Task 3 |
| 串行队列、日记、删除 / 再生成 / 再发布 / 备份 | Task 4 |
| 隐私弹窗、权限话术、release HAP、AGC 材料 | Task 5 |
| 原生不按文件名扫、日记按 `captureId`、条件清日记 | Task 4 测试钉死 |
| picker 不得标对等、通知/动态取色可关 | Task 1 差异记录 + Task 4/5 文案 |
| 现网 Dart 单测继续做门禁 | Task 2/4 回归命令 |
| 不改 Pigeon Kotlin、不改 `main` CI | 全任务 Files 约束 |

规格正文曾写“先落新图、写日记、再删旧图”。与 v1.0.8 代码不符。本计划按真实产品：宿主报告 `supersededUris`，Dart 引用检查后再删。这是对等所要求的行为。

**占位符扫描：** 已去掉 TBD / “类似 Task N”。社区 Flutter 的 `flutter create` flag、Rust triple、`Platform.operatingSystem` 探测以第 0/3 期实测写入 `tool/ohos/*.md` 为准；任务里已规定只允许选一个实测值，不允许同时留多套实现。

**类型一致性：** `PlatformServices`、`PublishJpegOutcome`、`RecoveredPublishJournalEntry`、`BackgroundWorkClient.appendCapture`、`captureProcessingQueue` / `captureProcessingTask`、Pigeon 枚举 index、日记 key 布局在 Task 1–4 使用同一套名字。
