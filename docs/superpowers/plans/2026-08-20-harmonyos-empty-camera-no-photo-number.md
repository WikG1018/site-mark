# HarmonyOS: empty camera file does not consume photo number

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Task 58。规格「取消或空文件 → 清会话、删占位，不占编号」。取消路径已由 Task 56 锁定。本刀锁 pending 空文件恢复不占下一张当日编号，并把 live `launchCamera` 在 picker 成功但无内容时从 `cameraFailed` 改成 `cameraCancelled`，避免留下失败行。

**Architecture:** 编号只在 `AppDatabase.markCaptured` 写入；`markFailed` 不写 `photoNumber`。`recoverPendingCapture` 在 `pendingCamera && !hasContent` 时已 `deleteCapture`。缺口是：workflow 没有端到端断言空恢复后再拍仍是 `001`；宿主 `launchCamera` 对空 `resultUri` / `materializeCapture` 后无内容返回 `failed`，workflow 会 `markFailed` 留下失败行，与规格「清会话、删占位」不一致。本刀不把权限拒绝、无 Ability、picker 抛错改成取消。不写 WorkScheduler。

**Predecessor:** [2026-08-20-harmonyos-denied-location-burst-numbers.md](2026-08-20-harmonyos-denied-location-burst-numbers.md) 已推（Task 57 / `7b82a42`）。

## Global Constraints

- 长期 `ohos` 分支，不合 `main`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`。`.github/workflows/ohos.yml` 可以改，本刀规格点名测试已在清单，不必为了进 CI 再加文件。
- 不降 `sdk: ^3.12.2`。不要 page-level `if (ohos)`。
- 无 dump 不得宣称拍成 / 相册 / 分享 / 通知 / 外链 / 像素对等。队列仍是应用内内存串行。
- 官方测试必须 Flutter 3.44.6 + `--no-pub`。
- 不要重做 Task 51–57。不要写 WorkScheduler。

## File map

- Test: `test/workflow/capture_workflow_test.dart`
- Test: `packages/sitemark_system_api/test/capture_session_store_test.dart`
- Modify: `packages/sitemark_system_api/ohos/src/main/ets/components/plugin/OhosSystemHost.ets`
- Existing: `packages/sitemark_system_api/lib/src/ohos/capture_target_policy.dart`（`length: 0` 已是 not captured）
- Docs: `README.md`, `tool/ohos/full_product_gap.md`, `tool/ohos/product_hap_review.md`, `docs/superpowers/handoffs/2026-08-20-ohos-agent-handoff.md`, `NEXT_AGENT_PROMPT.md`

---

### Task 58: 空相机文件不占号 + live 空文件当取消

- [x] **Step 1: RED** — 在 `capture_workflow_test.dart` 的「取消不占号」用例后追加：pending 空文件恢复为 cancelled，再拍仍 `001`。在 `capture_session_store_test.dart` 追加真实空文件 `hasContent: false`。

```dart
  test(
    'empty pending camera recovery does not consume the next photo number',
    () async {
      await database.createPendingCapture(
        id: 'capture-empty',
        projectId: 'project-1',
        originalPath: '/private/capture-empty.jpg',
        workLocation: 'A 区三层',
        workContent: '风管安装检查',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 7, 16, 9, 30),
      );
      platform.recoveredCapture = RecoveredCameraCapture(
        captureId: 'capture-empty',
        outputPath: '/private/capture-empty.jpg',
        hasContent: false,
      );

      final recovered = await workflow.recoverPendingCapture();
      expect(recovered?.outcome, CaptureWorkflowOutcome.cancelled);
      expect(await database.captureById('capture-empty'), isNull);
      expect(platform.finishedCapture, ('capture-empty', false));

      platform.recoveredCapture = null;
      platform.cameraOutcome = CameraOutcome.captured;
      workflow = CaptureWorkflow(
        database: database,
        platform: platform,
        images: images,
        outputPaths: _FakeOutputPaths(),
        fileStore: fileStore,
        scheduler: scheduler,
        locationCoordinator: coordinator,
        idFactory: () => 'capture-2',
        now: () => DateTime(2026, 7, 16, 9, 32, 18),
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
      final record = await database.captureById('capture-2');
      expect(record?.photoNumber, '东区厂房改造-SM-20260716-001');
    },
  );
```

```dart
  test('recover reports empty on-disk target as no content', () async {
    final directory = await Directory.systemTemp.createTemp('sitemark-empty-');
    addTearDown(() => directory.delete(recursive: true));
    final empty = File('${directory.path}/empty.jpg')..createSync();
    final filled = File('${directory.path}/filled.jpg')
      ..writeAsBytesSync(const <int>[1, 2, 3]);

    final store = CaptureSessionStore(MemoryKeyValueStore());
    await store.write(captureId: 'empty', outputPath: empty.path);
    expect((await store.recover())!.hasContent, isFalse);

    await store.write(captureId: 'filled', outputPath: filled.path);
    expect((await store.recover())!.hasContent, isTrue);
  });
```

- [x] **Step 2: Run tests** — 恢复编号用例可能立刻绿（生产已删 pending 空文件）。session store 用例应对现有 `CaptureTargetPolicy.isCaptured` 绿。不要为了制造红灯改断言。

- [x] **Step 3: GREEN host mapping** — 只改 picker 成功后的空内容，不改权限/Ability/picker 异常：

```ts
        if (resultUri.length === 0) {
          return this.cameraCancelled(target);
        }
```

```ts
    if (this.hasCaptureContent(target)) {
      return this.cameraCaptured(target);
    }
    return this.cameraCancelled(target);
```

`copyUriToPath` 抛错仍 `cameraFailed`。无 Ability / 相机权限拒绝 / picker catch 仍 `cameraFailed`。

- [x] **Step 4: 官方 Flutter 3.44.6 `--no-pub` 跑绿** `capture_workflow_test.dart` 与 `capture_session_store_test.dart`（合计 **24 绿**）。

- [x] **Step 5: Honest docs + commit + push origin/ohos**

不得写系统相册 / 拍成 / WorkScheduler。写明 Task 46–58 Dart 未进 HAP。
