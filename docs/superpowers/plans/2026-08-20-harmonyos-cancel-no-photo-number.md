# HarmonyOS: cancelled camera does not consume photo number

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Task 56。规格「取消拍照不占号」现有用例只断言 pending 被删，不锁下一张成功拍摄仍是当日 `001`。把该体验锁进 `capture_workflow_test`，并把已有 `capture_failure_guidance_test` 纳入 `ohos.yml`（规格：错误只显示稳定类别）。

**Architecture:** 生产路径已在 `CameraOutcome.cancelled` 时 `deleteCapture` 且不调用 `markCaptured`，编号只在 `markCaptured` 按当日已有 `photoNumber` 递增。本刀只补断言 + CI，不改生产语义，不写 WorkScheduler。

**Predecessor:** [2026-08-20-harmonyos-ci-widget-lifecycle-backup.md](2026-08-20-harmonyos-ci-widget-lifecycle-backup.md) 已推（Task 55 / `d742817`）。

## Global Constraints

- 长期 `ohos` 分支，不合 `main`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`。`.github/workflows/ohos.yml` 可以改。
- 不降 `sdk: ^3.12.2`。不要 page-level `if (ohos)`。
- 无 dump 不得宣称拍成 / 相册 / 分享 / 通知 / 外链 / 像素对等。队列仍是应用内内存串行。
- 官方测试必须 Flutter 3.44.6 + `--no-pub`。
- 不要重做 Task 51–55。不要写 WorkScheduler。

## File map

- Test: `test/workflow/capture_workflow_test.dart`
- Modify: `.github/workflows/ohos.yml`
- Existing: `test/features/capture/capture_failure_guidance_test.dart`
- Docs: `README.md`, `tool/ohos/full_product_gap.md`, `tool/ohos/product_hap_review.md`, `docs/superpowers/handoffs/2026-08-20-ohos-agent-handoff.md`, `NEXT_AGENT_PROMPT.md`

---

### Task 56: 取消拍照不占号 + 失败引导进 CI

- [x] **Step 1: RED** — 取消后再拍，断言下一张 `photoNumber` 仍是 `东区厂房改造-SM-20260716-001`
- [x] **Step 2: GREEN** — 官方 `--no-pub` 跑 `capture_workflow_test`；`ohos.yml` 加 `capture_failure_guidance_test.dart`
- [x] **Step 3: Honest docs + commit + push origin/ohos** (`6484a86`)

不得写系统相册 / 拍成 / WorkScheduler。写明 Task 46–56 Dart 未进 HAP。
