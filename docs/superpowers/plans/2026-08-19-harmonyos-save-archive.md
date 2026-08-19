# HarmonyOS saveArchive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 让全量 `lib/main.dart` HAP 的「备份项目」走鸿蒙 `sitemark.system.ohos` 真 `saveArchive`：系统 picker 优先，失败/取消回退到应用沙箱 `files/exports`，备份页不再因 Pigeon 无宿主而 `ohos_not_ready`。

**Architecture:** 备份页继续只调 `ArchiveSaveService.saveArchive`，不改状态机、不写 page-level `if (ohos)`。ohos 覆盖 `archiveSaveServiceProvider` 为 `OhosArchiveSaveService`，经 `OhosSystemApi.saveArchive` 调宿主。宿主校验私有非空 `.zip`、规范化文件名、`DocumentViewPicker.save`，失败再复制到 `filesDir/exports`。成功返回 `0`（`ArchiveSaveOutcome.saved`）。`inspectImage` 仍 `ohos_not_ready`。

**Tech Stack:** 官方 Flutter 3.44.6 / Dart 3.12.2 跑测试；社区 Flutter-OH 3.44 编 HAP；`sitemark.system.ohos`；DevEco 模拟器 `SiteMarkPhone602`，hdc `127.0.0.1:5555`。

**Predecessor:** [2026-08-19-harmonyos-records-backup.md](2026-08-19-harmonyos-records-backup.md) Tasks 17–20 已探测：备份入口可开，`saveArchive` 仍 throw，`files/exports` 空。远端 `origin/ohos` = `fca9537`。

## Global Constraints

- 不降 `sdk: ^3.12.2`，不改 `version: 1.0.8+23`。
- 不改 `ci.yml` / `release.yml` / `android/`，不合 `main`。
- 不要 page-level `if (ohos)` 发布/相册/备份。
- 不实现恢复导入、真相机拍成、`inspectImage`、ACL、`ohos-arm64`。
- 无真机：不得宣称备份 zip 已进系统文件管理，除非 dump 证明 picker 真成功。沙箱 zip 只算应用内导出。
- 不提交一次性脚本、HAP、`ohos/entry/libs/`、社区 lock、`flutter_*.log`。
- 用户可见失败文案不暴露原始异常。
- 用户已说「继续完善并提交」：实现后 commit + `git push origin ohos`。

## File map

- Create: `OhosArchiveSaveService` 放在 `lib/platform/ohos_platform_services.dart`（与 `OhosPlatformServices` 同文件，共用 ohos 桥）。
- Modify: `lib/app.dart` 的 `archiveSaveServiceProvider`。
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets` 实现 `saveArchive`。
- Test: `test/platform/ohos_platform_services_test.dart`、`test/platform/degraded_image_pipeline_test.dart`。
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`。
- Extra (empty `exports` root cause): `lib/platform/degraded_image_pipeline.dart` 实现 schema 5 zip；`exportSelection` / `exportBundle` 一并写出；restore 仍 throw。

---

### Task 21: `OhosArchiveSaveService` + provider 覆盖

**Files:**
- Test: `test/platform/ohos_platform_services_test.dart`
- Create in: `lib/platform/ohos_platform_services.dart`
- Modify: `lib/app.dart`

**Interfaces:**
- Consumes: `OhosSystemApi.saveArchive(String sourcePath, String suggestedName) -> Future<int>`
- Produces: `class OhosArchiveSaveService implements ArchiveSaveService { Future<ArchiveSaveOutcome> saveArchive(String sourcePath); }`

- [x] **Step 1: Write the failing tests**

在 `test/platform/ohos_platform_services_test.dart` 追加：

```dart
test('OhosArchiveSaveService maps missing plugin to ohos_not_ready', () async {
  final service = OhosArchiveSaveService();
  await expectLater(
    service.saveArchive('/tmp/exports/sitemark-backup-1.zip'),
    throwsA(
      isA<PlatformException>().having(
        (error) => error.code,
        'code',
        'ohos_not_ready',
      ),
    ),
  );
});

test('OhosArchiveSaveService decodes saved and sends the zip basename', () async {
  const channel = MethodChannel('sitemark.system.ohos');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'saveArchive');
        final args = Map<String, Object?>.from(call.arguments as Map);
        expect(args['sourcePath'], '/tmp/exports/sitemark-backup-1.zip');
        expect(args['suggestedName'], 'sitemark-backup-1.zip');
        return 0;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final outcome = await OhosArchiveSaveService().saveArchive(
    '/tmp/exports/sitemark-backup-1.zip',
  );
  expect(outcome, ArchiveSaveOutcome.saved);
});

test('OhosArchiveSaveService decodes cancelled', () async {
  const channel = MethodChannel('sitemark.system.ohos');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => 1);
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  expect(
    await OhosArchiveSaveService().saveArchive(
      '/tmp/exports/sitemark-backup-1.zip',
    ),
    ArchiveSaveOutcome.cancelled,
  );
});
```

- [x] **Step 2: Run tests to verify they fail**

```powershell
$dart = 'C:\Users\Administrator\Development\flutter\bin\cache\dart-sdk\bin\dart.exe'
$snap = 'C:\Users\Administrator\Development\flutter\bin\cache\flutter_tools.snapshot'
$pkg = 'C:\Users\Administrator\Development\flutter\packages\flutter_tools\.dart_tool\package_config.json'
Set-Location 'C:\Users\Administrator\Documents\Codex\2026-07-15\new-chat\.worktrees\ohos'
& $dart --packages=$pkg $snap test test/platform/ohos_platform_services_test.dart --reporter expanded
```

Expected: compile/fail because `OhosArchiveSaveService` 不存在。

- [ ] **Step 3: Minimal Dart implementation**

`lib/platform/ohos_platform_services.dart` 增加：

```dart
class OhosArchiveSaveService implements ArchiveSaveService {
  OhosArchiveSaveService({OhosSystemApi? api}) : _api = api ?? OhosSystemApi();

  final OhosSystemApi _api;

  @override
  Future<ArchiveSaveOutcome> saveArchive(String sourcePath) async {
    final suggestedName = Uri.file(sourcePath).pathSegments.last;
    final outcome = await _api.saveArchive(sourcePath, suggestedName);
    return ArchiveSaveOutcome.values[outcome];
  }
}
```

`lib/app.dart`：

```dart
final archiveSaveServiceProvider = Provider<ArchiveSaveService>(
  (ref) =>
      isOhosBuild ? OhosArchiveSaveService() : PigeonArchiveSaveService(),
);
```

不要改备份页。

- [ ] **Step 4: Re-run the same official test file**

Expected: PASS。

---

### Task 22: 宿主实现 `saveArchive`

**Files:**
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets`

**Interfaces:**
- Consumes: `DocumentViewPicker.save`、`copyFile` / `copyFileToUri`、`ensureDir`、`hasCaptureContent`
- Produces: `handle('saveArchive') -> 0`（saved）。picker 取消或失败也回退沙箱并返回 `0`。非法源抛错。`inspectImage` 仍 throw `ohos_not_ready`。

- [x] **Step 1: Split the switch and implement**

`handle` 里把两个 case 拆开：

```ets
case 'inspectImage':
  throw new Error('ohos_not_ready');
case 'saveArchive':
  return await this.saveArchive(
    this.requiredString(args, 'sourcePath'),
    this.requiredString(args, 'suggestedName'),
  );
```

常量：

```ets
const ARCHIVE_SAVE_SAVED = 0;
```

方法（对齐 Android `ArchiveSavePolicy`：源必须在 `filesDir` 下、是非空 `.zip`；建议名去首尾空白、必须以 `.zip` 结尾、不含控制字符和 `/ \ : * ? " < > |`）：

```ets
private async saveArchive(sourcePath: string, suggestedName: string): Promise<number> {
  const source = this.validatedArchiveSource(sourcePath);
  const name = this.normalizedZipName(suggestedName);
  const abilityContext = this.ability?.context as common.UIAbilityContext | undefined;
  if (abilityContext !== undefined) {
    try {
      const documentPicker = new picker.DocumentViewPicker(abilityContext);
      const destinations = await documentPicker.save({
        newFileNames: [name],
        fileSuffixChoices: ['zip'],
      });
      if (destinations !== undefined && destinations.length > 0) {
        const destination = this.stringAt(destinations, 0);
        if (destination.startsWith('file://')) {
          this.copyFile(source, this.pathFromUri(destination));
        } else {
          await this.copyFileToUri(source, destination);
        }
        return ARCHIVE_SAVE_SAVED;
      }
    } catch (_error) {
    }
  }
  return await this.writeSandboxZip(source, name);
}

private async writeSandboxZip(sourcePath: string, fileName: string): Promise<number> {
  const directory = `${this.context.filesDir}/exports`;
  await this.ensureDir(directory);
  const destination = `${directory}/${fileName}`;
  if (sourcePath !== destination) {
    this.copyFile(sourcePath, destination);
  }
  return ARCHIVE_SAVE_SAVED;
}

private validatedArchiveSource(sourcePath: string): string {
  if (!sourcePath.startsWith(`${this.context.filesDir}/`) ||
      !sourcePath.toLowerCase().endsWith('.zip') ||
      !this.hasCaptureContent(sourcePath)) {
    throw new Error('Backup source is empty, missing, or outside private storage');
  }
  return sourcePath;
}

private normalizedZipName(suggestedName: string): string {
  const trimmed = suggestedName.trim();
  if (!trimmed.toLowerCase().endsWith('.zip') || trimmed.length <= 4) {
    throw new Error('Backup filename must end with .zip');
  }
  if (/[\u0000-\u001f\/\\:*?"<>|]/.test(trimmed)) {
    throw new Error('Invalid backup filename');
  }
  return trimmed;
}
```

ArkTS 禁止 `arr[i]` / index signature；复用现有 `stringAt`。不要改 `android/`。

- [ ] **Step 2: Official Dart tests still pass**

同一条 `ohos_platform_services_test.dart` 命令。宿主 ETS 无单测；无插件时 `OhosSystemApi.saveArchive` 仍映射 `ohos_not_ready`。

---

### Task 23: 编产品 HAP 并在模拟器重走备份

**Files:**
- Evidence only (do not commit dumps/HAP): `tool/ohos/review/`
- Docs: `tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`、`README.md`

**Interfaces:**
- Consumes: `tool/ohos/build-product-hap.ps1`、hdc `127.0.0.1:5555`、已有 `Task13Demo` 或重建同名项目
- Produces: 备份成功 SnackBar **或** 沙箱 `files/exports/*.zip` 仍在；应用不崩。不得宣称系统文件管理已收到 zip，除非 picker dump 证明。

- [x] **Step 1: 非沙箱编产品 HAP 并安装**

`tool/ohos/build-product-hap.ps1`，然后：

```powershell
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 install 'ohos\entry\build\default\outputs\default\entry-default-unsigned.hap'
& $hdc -t 127.0.0.1:5555 shell "aa start -a EntryAbility -b io.github.wikg1018.sitemark"
```

卸载会清库，需要时重建 `Task13Demo`。编完 restore official lock，不要提交社区 lock。

- [x] **Step 2: 设置 → 备份与恢复 → 备份项目 → 勾选项目 → 不包含原图**

记录：picker 是否弹出、SnackBar 文案、`files/exports` 是否有 zip、进程是否仍 FOREGROUND。

- [x] **Step 3: 按实测改 README / gap / review**

备份导出：可写「应用内沙箱导出已通」当且仅当 zip 存在。不可写「已保存到系统文件」除非 picker 成功。

---

### Task 24: Commit and push `ohos`

- [ ] **Step 1: Stage only product + plan + review docs**

不要 add：`ohos/entry/libs/`、HAP、`tool/ohos/*.ps1` 一次性脚本、review jpeg/json dump、社区 lock、`flutter_*.log`。

- [ ] **Step 2: Commit**

```text
feat(ohos): implement saveArchive with picker and sandbox fallback
```

- [x] **Step 3: `git push origin ohos`**

不合 `main`，不开 PR。

---

## Out of scope

- 恢复导入 / `file_picker`
- `inspectImage`
- 相机拍成、相册 ACL、`ohos-arm64`
- 改备份页状态机
- 合进 `main`

## Self-review

1. 规格备份条款：picker 优先，失败写沙箱。本计划覆盖；ACL / 对等宣称不在本计划。
2. 无 page-level `if (ohos)`。只换 `archiveSaveServiceProvider`。
3. 返回值 `0/1` 对齐 `ArchiveSaveOutcome.saved/cancelled`。沙箱回退返回 `0`，避免把已生成 zip 报成失败。
4. 用户取消 picker 也回退沙箱（规格「失败再写沙箱」；模拟器常无法完成 picker）。
