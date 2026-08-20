# HarmonyOS Kill-Process Four-Window Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline; do not dispatch subagents). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lock the spec rule that after process death, the four HarmonyOS recovery windows re-enter independently and must not block each other.

**Architecture:** `AppStartupRecovery` is **callback-based** (not a `FakeCaptureWorkflow` object graph). Keep persistence as it is (camera session store, Drift pending captures, publish journals, album cleanup pending). Serial-run the four interrupted-cleanup callbacks first, then `Future.wait` the five core windows (album media, publish journals, camera, location, queue). Extract journal recovery from album cleanup so those two windows no longer wait on each other.

**Landed (2026-08-20):** Callback API + extracted `CaptureMediaService.recoverPublishJournals()`. Official Flutter 3.44.6 `--no-pub` on `app_startup_recovery_test` + `capture_media_service_test` + `widget_test` + `app_lifecycle_test`: **88 tests, All tests passed**. No kill-process dump. HarmonyOS queue is still in-memory.

**Tech Stack:** Flutter/Dart official tests, Drift in-memory database, existing fakes in `test/workflow/`.

## Global Constraints

- Stay on `ohos`. Do not merge to `main`. Do not open a PR.
- Do not change `ci.yml`, `release.yml`, `android/`, or `pigeons/`. `.github/workflows/ohos.yml` may be updated.
- No page-level `if (ohos)`. Engine stays degraded.
- No capture dump: do not claim camera capture, gallery ACL, watermark pixel parity, location coords, system share, system notification, or system file restore.
- User covering instruction: implement through experience alignment. Do not wait for plan approval. Do not use subagents.
- TDD: failing test first. Watch RED. Minimal GREEN. Official tests with `--no-pub` locally if the sandbox `flutter test` is silent.

## File Map

- Modify: `test/workflow/app_startup_recovery_test.dart` — four-window independence tests.
- Modify: `test/workflow/capture_media_service_test.dart` — journal recovery calls the extracted API.
- Modify: `lib/workflow/app_startup_recovery.dart` — start four windows together; one error must not skip the others.
- Modify: `lib/workflow/capture_media_service.dart` — public `recoverPublishJournals()`; `cleanupInterrupted()` only album pending cleanup.
- Modify: `.github/workflows/ohos.yml` — run the startup recovery test on `ohos` CI.
- Modify: `docs/superpowers/handoffs/2026-08-20-ohos-agent-handoff.md`, `README.md`, `NEXT_AGENT_PROMPT.md`, `tool/ohos/full_product_gap.md`, `tool/ohos/product_hap_review.md` — honest Task 53 notes. No local absolute paths.

## Spec Windows

From `docs/superpowers/specs/2026-08-17-harmonyos-next-adaptation-design.md`:

1. Camera half-complete → `recoverCameraCapture` / `CaptureWorkflow.recoverPendingCapture`, then `persistOriginal`.
2. Queue not finished → Drift pending rows → `CaptureBackgroundScheduler.reconcilePending` (HarmonyOS queue is in-memory).
3. Album written, journal not committed → `CaptureMediaService.recoverPublishJournals`.
4. Journal vs Drift → `CaptureMediaService.cleanupInterrupted` album pending cleanup.

Today `run()` does `await` camera, then queue, then `cleanupInterrupted` (which also recovers journals). If camera never completes, windows 2–4 never start.

---

### Task 53: Four windows must not block each other

**Files:**
- Modify: `test/workflow/app_startup_recovery_test.dart`
- Modify: `test/workflow/capture_media_service_test.dart`
- Modify: `lib/workflow/app_startup_recovery.dart`
- Modify: `lib/workflow/capture_media_service.dart`
- Modify: `.github/workflows/ohos.yml`
- Modify: handoff / README / gap / review docs

**Interfaces:**
- Consumes: existing `AppStartupRecovery`, `CaptureWorkflow.recoverPendingCapture`, `CaptureBackgroundScheduler.reconcilePending`, `CaptureMediaService.cleanupInterrupted`.
- Produces: `Future<void> CaptureMediaService.recoverPublishJournals()`; `AppStartupRecovery.run()` starts four windows without waiting for any one to finish before starting the others; a thrown error in one window does not skip the others.

- [ ] **Step 1: Write the failing tests**

In `test/workflow/app_startup_recovery_test.dart`:

1. Give `FakeCaptureWorkflow` a `Completer<CaptureRecord?>? recoverHang` and `Object? recoverError`.
2. Give `FakeCaptureMediaService` `int recoverPublishJournalsCalls` and a hang/error hook; override `recoverPublishJournals()`.
3. Give `RecordingCaptureBackgroundScheduler` a hang/error hook for `reconcilePending`.
4. Add these tests (names are the contract):

```dart
test('hanging camera recovery still starts queue journal and album windows', () async {
  final cameraHang = Completer<CaptureRecord?>();
  workflow.recoverHang = cameraHang;
  unawaited(recovery.run());
  await pumpEventQueue();
  expect(scheduler.reconcileCount, 1);
  expect(media.cleanupCalls, 1);
  expect(media.recoverPublishJournalsCalls, 1);
  expect(cameraHang.isCompleted, isFalse);
});

test('camera recovery error does not skip queue reconcile', () async {
  workflow.recoverError = StateError('camera host dead');
  await recovery.run();
  expect(scheduler.reconcileCount, 1);
  expect(media.cleanupCalls, 1);
  expect(media.recoverPublishJournalsCalls, 1);
});
```

In `test/workflow/capture_media_service_test.dart`, change the two process-death journal tests to call `await service.recoverPublishJournals()` instead of `cleanupInterrupted()`, so journal recovery is a first-class window.

- [ ] **Step 2: Run tests to verify they fail**

Run: official `flutter test --no-pub test/workflow/app_startup_recovery_test.dart`

Expected RED: hanging-camera test sees `reconcileCount == 0` (sequential `await` never reaches queue). Missing `recoverPublishJournals` on the fake/service.

- [ ] **Step 3: Write minimal implementation**

`CaptureMediaService`:

```dart
Future<void> cleanupInterrupted() async {
  // pending album cleanup only — do not call recoverPublishJournals here
}

Future<void> recoverPublishJournals() async {
  // move the existing _recoverPublishJournals body here
}
```

`AppStartupRecovery.run()`:

```dart
Future<void> run() async {
  await Future.wait([
    _runWindow(_recoverCamera),
    _runWindow(_scheduler.reconcilePending),
    _runWindow(_media.cleanupInterrupted),
    _runWindow(_media.recoverPublishJournals),
  ]);
}

Future<void> _runWindow(Future<void> Function() window) async {
  try {
    await window();
  } catch (_) {}
}

Future<void> _recoverCamera() async {
  final recovered = await _workflow.recoverPendingCapture();
  if (recovered != null) {
    await _scheduler.persistOriginal(recovered);
  }
}
```

Keep the existing recovered-capture persist test green: camera success still calls `persistOriginal`.

- [x] **Step 4: Run tests to verify they pass**

Run:

- `test/workflow/app_startup_recovery_test.dart`
- `test/workflow/capture_media_service_test.dart`
- `test/background/capture_background_scheduler_test.dart`

Expected: all green. Existing sequential recovered-capture test still passes.

- [x] **Step 5: CI + honest docs**

Add to `.github/workflows/ohos.yml`:

```yaml
test/workflow/app_startup_recovery_test.dart
```

Update handoff Task table (53 done), next-step (DevEco HAP rebuild / dumps; do not claim four-window dump). README / NEXT_AGENT_PROMPT / gap / review: semantic tests only; HarmonyOS queue is still in-memory; process death still depends on Drift reconcile; no capture dump.

- [x] **Step 6: Commit and push `ohos`**

```bash
git add test/workflow/app_startup_recovery_test.dart test/workflow/capture_media_service_test.dart lib/workflow/app_startup_recovery.dart lib/workflow/capture_media_service.dart .github/workflows/ohos.yml docs README.md NEXT_AGENT_PROMPT.md tool/ohos/full_product_gap.md tool/ohos/product_hap_review.md
git commit -m "fix(ohos): recover kill-process windows without blocking"
git push origin ohos
```

Do not merge `main`. Do not add `ohos/entry/libs/` or one-shot scripts.
