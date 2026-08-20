# HarmonyOS in-app queue retry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 鸿蒙应用内串行队列对 `CaptureProcessResult.retry` 做与 Android WorkManager 一致的指数退避重试（首延迟 30s），避免瞬时 IO 失败只跑一轮、要等下次冷启动 `reconcilePending` 才再试。

**Architecture:** 不接 WorkScheduler / 前台长时任务（无进程保活 dump，不得写后台已对等）。只改 `InAppSerialBackgroundWorkClient`：`runner` 返回 `CaptureProcessResult`；`retry` 或 runner 抛错时不阻塞后续 capture，按 30s × 2^(n-1) 延迟后再 `appendCapture`。`failed` / `succeeded` / `alreadyComplete` / `deferred` / `missing` 不自动重排。无拍成 dump 不得写后台渲染已对等。

**Predecessor:** [2026-08-20-harmonyos-degraded-exif-bake.md](2026-08-20-harmonyos-degraded-exif-bake.md) 已推。

## Global Constraints

- 不降 SDK，不合 `main`，不改 CI/Android/Pigeon。
- 官方测试搅 lock 后必须 `git checkout -- pubspec.lock`。
- 绿灯后只 add 产品/文档并 `git push origin ohos`。
- 用户已要求直接做到功能体验对齐；本刀 inline TDD，不用子代理。

## File map

- Modify: `lib/platform/ohos_background_work_client.dart`
- Modify: `lib/app.dart`（`processCaptureOnOhos` 返回 `CaptureProcessResult`）
- Modify: `test/platform/ohos_background_work_client_test.dart`
- Docs: `README.md`、`tool/ohos/full_product_gap.md`、`tool/ohos/product_hap_review.md`

---

### Task 46: In-app serial queue exponential retry

- [x] **Step 1: Failing tests** — retry 两次再成功，记录等待 `30s` 再 `60s`；c1 retry 不挡住 c2；runner 抛错当 retry；`failed` 不重排
- [x] **Step 2: `runner` 改为返回 `CaptureProcessResult`；retry 延迟后 `appendCapture`；wait/backoff 可注入**
- [x] **Step 3: `processCaptureOnOhos` 返回 processor 结果**
- [x] **Step 4: Official tests; honest docs; commit + push `origin/ohos`**
