# HarmonyOS capture workflow CI + delayed continue

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Task 54。把已有的 `test/workflow/capture_workflow_test.dart` 纳入 `.github/workflows/ohos.yml`；拍摄页锁住「入队失败返回 delayed 后仍可继续拍」。

**Architecture:** 生产 `CaptureWorkflow._captureAndEnqueue` 入队失败已返回 `CaptureWorkflowOutcome.delayed`，表单已清 `_working` 并显示 `captureQueueDelayedContinue`。本刀只补 CI 与 widget 锁，不重做四窗、同 id 替换、WorkScheduler。

**Predecessor:** [2026-08-20-harmonyos-kill-process-four-windows.md](2026-08-20-harmonyos-kill-process-four-windows.md) 已推（Task 53 / `9328d05`）。交接：[2026-08-20-ohos-agent-handoff.md](../handoffs/2026-08-20-ohos-agent-handoff.md)。

## Global Constraints

- 长期 `ohos` 分支，不合 `main`，不开 PR。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`。`.github/workflows/ohos.yml` **可以**改。
- 不降 `sdk: ^3.12.2`。不要 page-level `if (ohos)`。
- 无 dump 不得宣称拍成 / 相册 / 分享 / 通知 / 外链 / 像素对等。队列仍是应用内内存串行。
- 官方测试必须 Flutter 3.44.6 + `--no-pub`。
- 用户已要求直接做到功能体验对齐；本刀 inline TDD，不用子代理。
- 不要重做 Task 51–53。不要写 FakeCaptureWorkflow 四窗。

## File map

- Modify: `.github/workflows/ohos.yml`
- Test: `test/features/capture/capture_form_screen_test.dart`
- Existing lock: `test/workflow/capture_workflow_test.dart`（`initial queue failure returns delayed and keeps captured record`）
- Production already present: `lib/workflow/capture_workflow.dart`、`lib/features/capture/capture_form_screen.dart`
- Docs: `README.md`, `tool/ohos/full_product_gap.md`, `tool/ohos/product_hap_review.md`, `docs/superpowers/handoffs/2026-08-20-ohos-agent-handoff.md`, `NEXT_AGENT_PROMPT.md`

---

### Task 54: CI 纳入 capture_workflow + delayed 可继续拍

**Files:**

- Modify: `.github/workflows/ohos.yml`
- Test: `test/features/capture/capture_form_screen_test.dart`

**缺口：** 规格要求 `capture_workflow_test.dart` 进 ohos CI，当前 `ohos.yml` 没有。拍摄页 delayed 文案与 `_working = false` 已实现，表单测试未锁「snackbar 后按钮仍可再拍」。

- [x] **Step 1: Write the failing widget lock**

`pumpCaptureForm` 增加可选 `backgroundScheduler`。注入永远 `enqueue` 抛错的 scheduler，`cameraOutcome: captured`。填必填字段后点 `capture-button`：

- 出现 `captureQueueDelayedContinue`（中文：照片已安全保留，后台处理启动延迟并会自动重试，可继续拍摄）
- `capture-button` 的 `onPressed` 非空
- 再点一次，`launchCameraCount` 从 1 到 2

不要改生产 delayed 语义，除非测试证明 UI 仍卡住。

- [x] **Step 2: Run the new widget test**（官方 3.44.6 `--no-pub`）
- [x] **Step 3: Minimal implementation** — 生产 delayed 已有，未改表单语义；`ohos.yml` 增加 `test/workflow/capture_workflow_test.dart`
- [x] **Step 4: Official tests green** — `capture_workflow_test` 17 绿；`capture_form_screen_test` 20 绿
- [ ] **Step 5: Honest docs + commit + push origin/ohos**

不得写系统相册 / 拍成 / WorkScheduler / 杀进程 dump。写明 Task 46–54 Dart 未进 HAP。
