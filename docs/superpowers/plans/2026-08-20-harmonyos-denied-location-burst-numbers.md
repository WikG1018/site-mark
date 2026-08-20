# HarmonyOS: denied location still captures; burst numbers stay sequential

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Task 57。规格「拒绝定位仍出片」和「连拍编号不乱」目前只在 coordinator / `AppDatabase.markCaptured` 层部分锁定；`capture()` 端到端没有断言拒绝定位仍 `queued` 且有当日编号，也没有两张成功连拍 `001` 然后 `002`。把这两个体验锁进 `capture_workflow_test`，并把已有 `capture_location_coordinator_test` 纳入 `ohos.yml`。

**Architecture:** 生产路径已在 `CameraOutcome.captured` 时先 `markCaptured` 再 `locationCoordinator.begin`；定位 `permissionDenied` 只把坐标标 `unavailable`，仍 enqueue。编号只在 `markCaptured` 按当日已有 `photoNumber` 递增。本刀只补断言 + CI，不改生产语义，不写 WorkScheduler。

**Predecessor:** [2026-08-20-harmonyos-cancel-no-photo-number.md](2026-08-20-harmonyos-cancel-no-photo-number.md) 已推（Task 56 / `6484a86`）。

## Global Constraints

- 长期 `ohos` 分支，不合 `main`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`。`.github/workflows/ohos.yml` 可以改。
- 不降 `sdk: ^3.12.2`。不要 page-level `if (ohos)`。
- 无 dump 不得宣称拍成 / 相册 / 分享 / 通知 / 外链 / 像素对等。队列仍是应用内内存串行。
- 官方测试必须 Flutter 3.44.6 + `--no-pub`。
- 不要重做 Task 51–56。不要重写 coordinator 已有 `permissionDenied` enqueue 用例。不要写 WorkScheduler。

## File map

- Test: `test/workflow/capture_workflow_test.dart`
- Modify: `.github/workflows/ohos.yml`
- Existing: `test/workflow/capture_location_coordinator_test.dart`
- Docs: `README.md`, `tool/ohos/full_product_gap.md`, `tool/ohos/product_hap_review.md`, `docs/superpowers/handoffs/2026-08-20-ohos-agent-handoff.md`, `NEXT_AGENT_PROMPT.md`

---

### Task 57: 拒绝定位仍出片 + 连拍编号 001→002 + coordinator 进 CI

- [ ] **Step 1: RED** — 在 `capture_workflow_test.dart` 的「取消不占号」用例后追加两例：

```dart
  test(
    'permission-denied location still queues a numbered capture',
    () async {
      platform.locationOverride = Future.value(
        LocationResult(outcome: LocationOutcome.permissionDenied),
      );

      final result = await workflow.capture(
        const CaptureDraft(
          projectId: 'project-1',
          projectName: '东区厂房改造',
          workLocation: 'A 区三层',
          workContent: '风管安装检查',
          photographer: '张工',
          watermarkLocaleCode: 'zh',
        ),
      );
      await drainCoordinator();

      expect(result.outcome, CaptureWorkflowOutcome.queued);
      expect(result.failureCode, isNull);
      final record = await database.captureById('capture-1');
      expect(record?.status, CaptureStatus.captured);
      expect(record?.photoNumber, '东区厂房改造-SM-20260716-001');
      expect(record?.locationResolution, 'unavailable');
      expect(record?.locationOutcome, 'permissionDenied');
      expect(record?.latitude, isNull);
      expect(record?.longitude, isNull);
      expect(scheduler.enqueuedIds, ['capture-1', 'capture-1']);
    },
  );

  test(
    'two successful captures on the same day get 001 then 002',
    () async {
      var nextId = 1;
      workflow = CaptureWorkflow(
        database: database,
        platform: platform,
        images: images,
        outputPaths: _FakeOutputPaths(),
        fileStore: fileStore,
        scheduler: scheduler,
        locationCoordinator: coordinator,
        idFactory: () => 'capture-${nextId++}',
        now: () => DateTime(2026, 7, 16, 9, 32, 18),
      );

      const draft = CaptureDraft(
        projectId: 'project-1',
        projectName: '东区厂房改造',
        workLocation: 'A 区三层',
        workContent: '风管安装检查',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
      );
      final first = await workflow.capture(draft);
      final second = await workflow.capture(draft);
      await drainCoordinator();

      expect(first.outcome, CaptureWorkflowOutcome.queued);
      expect(second.outcome, CaptureWorkflowOutcome.queued);
      expect(
        (await database.captureById('capture-1'))?.photoNumber,
        '东区厂房改造-SM-20260716-001',
      );
      expect(
        (await database.captureById('capture-2'))?.photoNumber,
        '东区厂房改造-SM-20260716-002',
      );
    },
  );
```

- [x] **Step 2: GREEN** — 官方 `--no-pub` 跑 `capture_workflow_test`；`ohos.yml` 在 `capture_workflow_test.dart` 后加 `test/workflow/capture_location_coordinator_test.dart`。生产路径已满足则不改 Dart 业务代码。官方合计 **29 绿**（workflow 20 + coordinator 9）。

- [ ] **Step 3: Honest docs + commit + push origin/ohos**

不得写系统相册 / 拍成 / WorkScheduler。写明 Task 46–57 Dart 未进 HAP。
