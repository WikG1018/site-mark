# HarmonyOS: album save cancel falls back to sandbox

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Task 59。规格「ACL 被拒：自动切 picker / 沙箱，不把整次拍摄打成 `failed`」。ACL `createAsset` 失败已托底。本刀锁相册保存对话框用户取消 / 空 destinations 也写沙箱 URI，宿主不再把 `cancelled`/`Canceled` 再抛成 `PlatformException`，避免处理器三次 transient 后 `markFailed`。

**Architecture:** 纯 Dart `PublishFallbackPolicy` 编码「空 destinations / 用户取消 / 其它相册错误 → 沙箱，不 throw」。ETS `writeAlbumOrSandboxJpeg` 镜像该策略：取消也走 `writeSandboxJpeg`，对齐 `saveArchive` 取消回退 `writeSandboxZip`。不改 `pigeons/`，不给 `PublishJpegResult` 加 `enteredSystemAlbum`。UI 诚实提示仍走 Task 48 `detectGalleryAccess`。无 dump 不得宣称系统相册已通。

**Predecessor:** [2026-08-20-harmonyos-empty-camera-no-photo-number.md](2026-08-20-harmonyos-empty-camera-no-photo-number.md) 已推（Task 58 / `2f1a058`）。

## Global Constraints

- 长期 `ohos` 分支，不合 `main`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`。`.github/workflows/ohos.yml` 可以改；本刀测试放 `packages/sitemark_system_api/test/`，已在清单。
- 不降 `sdk: ^3.12.2`。不要 page-level `if (ohos)`。
- 无 dump 不得宣称拍成 / 相册 / 分享 / 通知 / 外链 / 像素对等。队列仍是应用内内存串行。
- 官方测试必须 Flutter 3.44.6 + `--no-pub`。
- 不要重做 Task 51–58。不要写 WorkScheduler。不要改 `capture_processor` 状态机。

## File map

- Create: `packages/sitemark_system_api/lib/src/ohos/publish_fallback_policy.dart`
- Test: `packages/sitemark_system_api/test/publish_fallback_policy_test.dart`
- Modify: `packages/sitemark_system_api/lib/sitemark_system_api.dart`（export 策略）
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets`（取消走沙箱）
- Docs: `README.md`, `tool/ohos/full_product_gap.md`, `tool/ohos/product_hap_review.md`, `docs/superpowers/handoffs/2026-08-20-ohos-agent-handoff.md`, `NEXT_AGENT_PROMPT.md`

---

### Task 59: 相册保存取消托底沙箱

- [x] **Step 1: RED** — 新增 `publish_fallback_policy_test.dart`。空 destinations、`cancelled`/`Canceled` 错误、其它相册错误都决定沙箱且不 throw；有 destination 才走相册。

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/publish_fallback_policy.dart';

void main() {
  test('empty destinations fall back to sandbox without throwing', () {
    expect(
      PublishFallbackPolicy.decide(destinations: null),
      PublishFallbackDecision.sandbox,
    );
    expect(
      PublishFallbackPolicy.decide(destinations: const []),
      PublishFallbackDecision.sandbox,
    );
    expect(
      PublishFallbackPolicy.shouldRethrow(
        destinations: const [],
        error: Exception('User cancelled the album save dialog'),
      ),
      isFalse,
    );
  });

  test('cancelled and Canceled album errors fall back to sandbox', () {
    expect(
      PublishFallbackPolicy.decide(
        error: Exception('User cancelled the album save dialog'),
      ),
      PublishFallbackDecision.sandbox,
    );
    expect(
      PublishFallbackPolicy.decide(
        error: Exception('Operation Canceled'),
      ),
      PublishFallbackDecision.sandbox,
    );
    expect(
      PublishFallbackPolicy.shouldRethrow(
        error: Exception('User cancelled the album save dialog'),
      ),
      isFalse,
    );
  });

  test('other album errors also fall back to sandbox', () {
    expect(
      PublishFallbackPolicy.decide(error: Exception('copy failed')),
      PublishFallbackDecision.sandbox,
    );
    expect(
      PublishFallbackPolicy.shouldRethrow(error: Exception('copy failed')),
      isFalse,
    );
  });

  test('non-empty destination stays on album', () {
    expect(
      PublishFallbackPolicy.decide(
        destinations: const ['file://media/Photo/123'],
      ),
      PublishFallbackDecision.album,
    );
    expect(
      PublishFallbackPolicy.shouldRethrow(
        destinations: const ['file://media/Photo/123'],
      ),
      isFalse,
    );
  });
}
```

- [x] **Step 2: Run test to verify it fails**

Run（worktree，官方 Flutter 3.44.6 + flutter_tools packages，`--no-pub`）:

```text
dart.exe --disable-dart-dev C:\Users\Administrator\Development\flutter\bin\cache\flutter_tools.snapshot test --no-pub packages/sitemark_system_api/test/publish_fallback_policy_test.dart
```

Expected: FAIL because `publish_fallback_policy.dart` is missing (`PublishFallbackPolicy` not defined).

- [x] **Step 3: GREEN** — 新增策略，ETS 取消不再 rethrow。

`packages/sitemark_system_api/lib/src/ohos/publish_fallback_policy.dart`:

```dart
enum PublishFallbackDecision { album, sandbox }

class PublishFallbackPolicy {
  static bool isUserCancelledPublish(Object? error) {
    if (error == null) return false;
    final message = '$error';
    return message.contains('cancelled') || message.contains('Canceled');
  }

  static PublishFallbackDecision decide({
    List<String>? destinations,
    Object? error,
  }) {
    if (error != null) return PublishFallbackDecision.sandbox;
    if (destinations == null || destinations.isEmpty) {
      return PublishFallbackDecision.sandbox;
    }
    return PublishFallbackDecision.album;
  }

  static bool shouldRethrow({
    List<String>? destinations,
    Object? error,
  }) {
    decide(destinations: destinations, error: error);
    return false;
  }
}
```

`sitemark_system_api.dart` 增加：

```dart
export 'src/ohos/publish_fallback_policy.dart';
```

`OhosSystemHost.ets` 的 `writeAlbumOrSandboxJpeg` 改成取消也写沙箱（对齐 `saveArchive`）：

```ts
  private async writeAlbumOrSandboxJpeg(
    sourcePath: string,
    captureId: string,
    displayName: string,
  ): Promise<string> {
    try {
      return await this.writeAlbumJpeg(sourcePath, displayName);
    } catch (_error) {
      return await this.writeSandboxJpeg(sourcePath, captureId);
    }
  }
```

`isUserCancelledPublish` 若已无调用方则删除，避免死代码。不要改 `writeAlbumJpeg` 的空 destinations 抛错文案——策略在 catch 里吞掉。不要改 `publishJpeg` Pigeon 返回值。不要改 `capture_processor`。

- [x] **Step 4: Run tests to verify they pass**

同一官方命令跑：

```text
packages/sitemark_system_api/test/publish_fallback_policy_test.dart
packages/sitemark_system_api/test/gallery_store_test.dart
```

Expected: 新测试 4 绿；`gallery_store_test` 仍 8 绿。不要宣称相册已通。

- [x] **Step 5: 诚实文档**

- `README.md` 计划链 Task 59 打头；落地段写「相册保存对话框取消 / 空 destinations 回退沙箱，不把拍摄打成 failed」。不得写系统相册已通。
- `tool/ohos/full_product_gap.md` 已接通加一条 Dart/ETS 策略锁；未接通仍写系统相册未证明。
- `tool/ohos/product_hap_review.md` 顶部加 Task 59 段：官方测试闭环，未重编 HAP，无相册 dump。Task 46–59 Dart 未进 HAP。
- 交接文档：事实基准 Task 59；表行 59；第 9 节不要再把「相册保存取消再 throw」当缺口。Task 58 行提交列已是 `2f1a058`。
- `NEXT_AGENT_PROMPT.md`：已完成 Tasks 0–59。

- [x] **Step 6: Commit and push `ohos`**

```text
feat(ohos): fall back to sandbox when album save is cancelled
```

已推 `ccf39ec`。只暂存本刀源码 / 测试 / 文档。不要提交 `ohos/entry/libs/`、HAP、一次性 ps1。不合 `main`。
