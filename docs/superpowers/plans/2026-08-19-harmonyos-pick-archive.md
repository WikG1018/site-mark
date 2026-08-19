# HarmonyOS native pickArchive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 恢复项目时用鸿蒙原生文档选择器选出 zip，复制进应用沙箱后再走现有 `prepareRestore`，体验对齐安卓「选备份文件并恢复」。

**Architecture:** 不改 Pigeon，不改 `pigeons/system_api.dart`。在已有 `sitemark.system.ohos` 通道上增加 `pickArchive`：宿主 `DocumentViewPicker.select` 选一个 `.zip`，`copyUriToPath` 到 `filesDir/imports/`，返回沙箱路径。Dart 侧新增 `ArchivePickService`，`app.dart` 按平台注入（与 `ArchiveSaveService` 相同），`runProjectRestoreFlow` 默认 `pickZip` 读该 provider。不要 page-level `if (ohos)`。无模拟器成功 dump 不得写「系统文件选择恢复已通」。

**Tech Stack:** 官方 Flutter 3.44.6 / Dart 3.12.2 跑测试；社区 Flutter-OH 编 HAP；`@kit.CoreFileKit` `picker.DocumentViewPicker`；DevEco 模拟器 `SiteMarkPhone602`。

**Predecessor:** [2026-08-19-harmonyos-restore-import.md](2026-08-19-harmonyos-restore-import.md) 已推 `b3eaba8`：降级管线可自读 schema 5 / bundle。产品恢复仍走 `FilePicker.pickFiles`，鸿蒙上未证。

## Global Constraints

- 不降 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`，不合 `main`。
- 不要 page-level `if (ohos)`。
- 不实现真相机拍成、ACL、`ohos-arm64`、定位出坐标。
- 无 FilePicker / Document picker 成功 dump 不得写系统文件选择恢复已通。
- 不提交一次性脚本、HAP、`ohos/entry/libs/`、社区 lock、`flutter_*.log`、`tool/ohos/review/`。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。
- 用户已说提交并继续：本块绿灯后只 add 产品/文档并 `git push origin ohos`。

## File map

- Modify: `test/platform/ohos_platform_services_test.dart` — `pickArchive` 通道契约。
- Modify: `packages/sitemark_system_api/lib/src/ohos/ohos_system_api.dart` — `pickArchive()`。
- Modify: `lib/platform/platform_services.dart` — `ArchivePickService` + FilePicker 实现。
- Modify: `lib/platform/ohos_platform_services.dart` — `OhosArchivePickService`。
- Modify: `lib/app.dart` — `archivePickServiceProvider`。
- Modify: `lib/features/projects/project_restore_flow.dart` — 默认 `pickZip` 走 provider。
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets` — `pickArchive`。
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`。

---

### Task 29: Dart pickArchive channel and service

**Files:**
- Modify: `test/platform/ohos_platform_services_test.dart`
- Modify: `packages/sitemark_system_api/lib/src/ohos/ohos_system_api.dart`
- Modify: `lib/platform/platform_services.dart`
- Modify: `lib/platform/ohos_platform_services.dart`

**Interfaces:**
- Consumes: `OhosSystemApi._invoke`、`ArchiveSaveOutcome` 同通道
- Produces: `OhosSystemApi.pickArchive()` → `Future<String>`；空串表示取消。`ArchivePickService.pickArchive()` → `Future<String?>`

- [x] **Step 1: Write the failing tests**

在 `ohos_platform_services_test.dart` 追加：

```dart
  test('OhosArchivePickService maps missing plugin to ohos_not_ready', () async {
    final service = OhosArchivePickService();
    await expectLater(
      service.pickArchive(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'ohos_not_ready',
        ),
      ),
    );
  });

  test('OhosArchivePickService returns sandbox path from pickArchive', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pickArchive');
          expect(call.arguments, isNull);
          return '/data/storage/el2/base/files/imports/sitemark-restore-1.zip';
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(
      await OhosArchivePickService().pickArchive(),
      '/data/storage/el2/base/files/imports/sitemark-restore-1.zip',
    );
  });

  test('OhosArchivePickService treats empty path as cancelled', () async {
    const channel = MethodChannel('sitemark.system.ohos');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(await OhosArchivePickService().pickArchive(), isNull);
  });
```

- [x] **Step 2: Run test to verify it fails**

Run:

```
C:\Users\Administrator\Development\flutter\bin\cache\dart-sdk\bin\dart.exe --packages=C:\Users\Administrator\Development\flutter\packages\flutter_tools\.dart_tool\package_config.json C:\Users\Administrator\Development\flutter\bin\cache\flutter_tools.snapshot test test/platform/ohos_platform_services_test.dart --reporter expanded
```

Expected: FAIL compiling `OhosArchivePickService` / `pickArchive` undefined.

- [ ] **Step 3: Write minimal implementation**

`OhosSystemApi`:

```dart
  Future<String> pickArchive() => _invoke('pickArchive');
```

`platform_services.dart`（`file_picker` 已在产品依赖中）：

```dart
abstract interface class ArchivePickService {
  Future<String?> pickArchive();
}

class FilePickerArchivePickService implements ArchivePickService {
  const FilePickerArchivePickService();

  @override
  Future<String?> pickArchive() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    return result?.files.single.path;
  }
}
```

`ohos_platform_services.dart`:

```dart
class OhosArchivePickService implements ArchivePickService {
  OhosArchivePickService({OhosSystemApi? api}) : _api = api ?? OhosSystemApi();

  final OhosSystemApi _api;

  @override
  Future<String?> pickArchive() async {
    final path = await _api.pickArchive();
    if (path.isEmpty) return null;
    return path;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

同一官方测试命令。Expected: PASS。然后 `git checkout -- pubspec.lock`。

- [ ] **Step 5: Do not commit yet**

等宿主与接线一并提交。

---

### Task 30: Wire restore flow and Harmony host

**Files:**
- Modify: `lib/app.dart`
- Modify: `lib/features/projects/project_restore_flow.dart`
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets`
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`

**Interfaces:**
- Consumes: Task 29 `ArchivePickService.pickArchive()`
- Produces: 宿主 `pickArchive(): Promise<string>`；取消返回 `''`；成功返回沙箱 zip 路径

- [x] **Step 1: Provider + restore default pickZip**

`app.dart`:

```dart
final archivePickServiceProvider = Provider<ArchivePickService>(
  (ref) =>
      isOhosBuild ? OhosArchivePickService() : const FilePickerArchivePickService(),
);
```

`project_restore_flow.dart` 默认依赖改为：

```dart
    deps = ProjectRestoreFlowDependencies(
      pickZip: () => ref.read(archivePickServiceProvider).pickArchive(),
      prepareRestore: service.prepareRestore,
      restorePrepared: service.restorePrepared,
      discardPrepared: service.discardPrepared,
    );
```

删除 `_pickRestoreZip`。已注入 `dependencies` 的测试不受影响。

- [ ] **Step 2: Host pickArchive**

`invoke` 增加 `case 'pickArchive': return await this.pickArchive();`

```ets
  private async pickArchive(): Promise<string> {
    const abilityContext = this.ability?.context as common.UIAbilityContext | undefined;
    if (abilityContext === undefined) {
      throw new Error('ability context unavailable');
    }
    const documentPicker = new picker.DocumentViewPicker();
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.zip'];
    const uris = await documentPicker.select(options);
    if (uris === undefined || uris.length === 0) {
      return '';
    }
    const uri = this.stringAt(uris, 0);
    const directory = `${this.context.filesDir}/imports`;
    await this.ensureDir(directory);
    const destination = `${directory}/sitemark-restore-${Date.now()}.zip`;
    await this.copyUriToPath(uri, destination);
    if (!this.hasCaptureContent(destination)) {
      throw new Error('picked archive is empty');
    }
    return destination;
  }
```

复用已有 `copyUriToPath` / `hasCaptureContent` / `ensureDir`。不要新增权限 ACL。

- [x] **Step 3: Re-run official Dart tests**

`ohos_platform_services_test.dart` 仍须全绿。不宣称模拟器系统选文件已通。

- [x] **Step 4: Update docs honestly**

写清：鸿蒙恢复选文件走原生 Document picker → 沙箱 `files/imports`；未完成 picker 成功 dump 前，「系统文件选择恢复」仍是未证。引擎读档已通不变。

- [x] **Step 5: Commit and push origin/ohos**

只 add 本块产品/文档。不合 `main`。
