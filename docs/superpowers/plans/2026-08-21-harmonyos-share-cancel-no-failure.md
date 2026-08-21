# HarmonyOS: user-cancelled share is not a failure

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Task 60。规格「界面只显示稳定错误类别」。ShareKit 分享面板用户取消不得当成备份/导出/诊断失败。Android `SharePlus` 关面板通常不 throw；鸿蒙 `controller.show` 无 catch，取消可能冒成 `PlatformException`，备份页 `_shareBackup`、批量导出 `_export`、诊断页 `_share` 对任何 catch 弹失败。

**Architecture:** 纯 Dart `ShareCancelPolicy` 识别 `cancelled`/`Canceled`。`OhosShareFileService` 吞掉取消并正常完成；ETS `shareFile` catch 取消后 return。空源 / `ohos_not_ready` / 其它真实错误仍 throw。不改 `ShareFileService` 接口（仍 `Future<void>`）。不改 `pigeons/`。无 dump 不得宣称系统分享已通。

**Honest UI boundary:** 接口是 `void`，吞取消后备份页会走现有成功路径并弹「备份已分享」。本刀最小对齐是「不再报失败」，不改接口去区分 cancelled vs shared。

**Predecessor:** [2026-08-20-harmonyos-album-cancel-sandbox.md](2026-08-20-harmonyos-album-cancel-sandbox.md) 已推（Task 59 / `ccf39ec`）。

## Global Constraints

- 长期 `ohos` 分支，不合 `main`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`。`.github/workflows/ohos.yml` 可以改；本刀测试放 `packages/sitemark_system_api/test/` 与已在清单的 `test/platform/ohos_platform_services_test.dart`。
- 不降 `sdk: ^3.12.2`。不要 page-level `if (ohos)`。
- 无 dump 不得宣称拍成 / 相册 / 分享 / 通知 / 外链 / 像素对等。队列仍是应用内内存串行。
- 官方测试必须 Flutter 3.44.6 + `--no-pub`。
- 不要重做 Task 51–59。不要写 WorkScheduler。不要改 Android `SystemShareFileService`。

## File map

- Create: `packages/sitemark_system_api/lib/src/ohos/share_cancel_policy.dart`
- Test: `packages/sitemark_system_api/test/share_cancel_policy_test.dart`
- Modify: `packages/sitemark_system_api/lib/sitemark_system_api.dart`（export 策略）
- Modify: `lib/platform/ohos_platform_services.dart`（`OhosShareFileService` 吞取消）
- Modify: `test/platform/ohos_platform_services_test.dart`（取消不 throw；其它错误仍 throw）
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets`（`shareFile` catch 取消 return）
- Docs: `README.md`, `tool/ohos/full_product_gap.md`, `tool/ohos/product_hap_review.md`, `docs/superpowers/handoffs/2026-08-20-ohos-agent-handoff.md`, `NEXT_AGENT_PROMPT.md`

---

### Task 60: 分享取消不报失败

- [ ] **Step 1: RED** — 新增 `share_cancel_policy_test.dart`；扩展 `ohos_platform_services_test.dart`。

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark_system_api/src/ohos/share_cancel_policy.dart';

void main() {
  test('cancelled and Canceled share errors are user cancel', () {
    expect(
      ShareCancelPolicy.isUserCancelled(
        Exception('User cancelled the share panel'),
      ),
      isTrue,
    );
    expect(
      ShareCancelPolicy.isUserCancelled(Exception('Operation Canceled')),
      isTrue,
    );
  });

  test('empty source, not ready, and other errors are not user cancel', () {
    expect(ShareCancelPolicy.isUserCancelled(null), isFalse);
    expect(
      ShareCancelPolicy.isUserCancelled(
        Exception('share source is empty or missing'),
      ),
      isFalse,
    );
    expect(
      ShareCancelPolicy.isUserCancelled(
        Exception('ohos_not_ready'),
      ),
      isFalse,
    );
    expect(
      ShareCancelPolicy.isUserCancelled(Exception('ability context unavailable')),
      isFalse,
    );
  });
}
```

`ohos_platform_services_test.dart` 增加：mock handler throw `PlatformException(message: 'User cancelled the share panel')` 与 `'Operation Canceled'` 时 `OhosShareFileService.shareFile` 不 throw；其它 message 仍 throw；missing plugin 仍 `ohos_not_ready`。

- [x] **Step 2: Run official test to verify RED**

```text
dart.exe --disable-dart-dev C:\Users\Administrator\Development\flutter\bin\cache\flutter_tools.snapshot test --no-pub packages/sitemark_system_api/test/share_cancel_policy_test.dart
```

Expected: FAIL because `share_cancel_policy.dart` is missing.

- [x] **Step 3: GREEN** — 新增策略，Dart service 与 ETS 吞取消。

`packages/sitemark_system_api/lib/src/ohos/share_cancel_policy.dart`:

```dart
class ShareCancelPolicy {
  static bool isUserCancelled(Object? error) {
    if (error == null) return false;
    final message = '$error';
    return message.contains('cancelled') || message.contains('Canceled');
  }
}
```

`sitemark_system_api.dart` 增加：

```dart
export 'src/ohos/share_cancel_policy.dart';
```

`OhosShareFileService.shareFile`:

```dart
@override
Future<void> shareFile(String path) async {
  try {
    await _api.shareFile(path);
  } catch (error) {
    if (ShareCancelPolicy.isUserCancelled(error)) {
      return;
    }
    rethrow;
  }
}
```

`OhosSystemHost.ets` 的 `shareFile`：空源仍 throw；`controller.show` 包 try/catch，消息含 `cancelled`/`Canceled` 则 return，其它 rethrow。不要改 UTD / 空源校验。

- [x] **Step 4: Run tests to verify they pass**

同一官方命令跑：

```text
packages/sitemark_system_api/test/share_cancel_policy_test.dart
packages/sitemark_system_api/test/publish_fallback_policy_test.dart
test/platform/ohos_platform_services_test.dart
```

Expected: 新策略测试绿；`publish_fallback_policy_test` 仍 4 绿；分享 missing plugin / invoke 契约仍绿，取消不 throw。不要宣称系统分享已通。

- [x] **Step 5: 诚实文档**

- `README.md` 计划链 Task 60 打头；分享段写「分享面板用户取消不报失败」。不得写系统分享已通。
- `tool/ohos/full_product_gap.md` 已接通加「分享取消不报失败（Dart/ETS 已锁）」；未接通仍写无分享面板 dump。
- `tool/ohos/product_hap_review.md` 顶部加 Task 60 段：官方测试闭环，未重编 HAP，无分享面板 dump。Task 46–60 Dart 未进 HAP。
- 交接文档：事实基准 Task 60；表行 59 填 `ccf39ec`；表行 60；第 9 节不要再把「分享取消再 throw 打成失败」当缺口。
- `NEXT_AGENT_PROMPT.md`：已完成 Tasks 0–60。

- [ ] **Step 6: Commit and push `ohos`**

```text
feat(ohos): ignore user-cancelled system share
```

只暂存本刀源码 / 测试 / 文档。不要提交 `ohos/entry/libs/`、HAP、一次性 ps1。不合 `main`。
