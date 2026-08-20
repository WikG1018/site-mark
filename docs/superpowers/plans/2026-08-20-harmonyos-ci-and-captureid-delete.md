# HarmonyOS CI coverage + captureId delete/republish lock

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** 云端可闭环的 Task 51–52：把已绿灯的 UI / 降级引擎 / GPS 测试纳入 `ohos.yml`；把「备份恢复后同编号不得串 URI、删除/再发布按 captureId」锁进相册适配器与 `CaptureMediaService`。

**Architecture:** CI 只扩测试清单，不改 Android workflow。相册删除按 URI 方案路由（沙箱 `file://` → picker，其余 → ACL），对齐 `OhosSystemHost.deletePublishedImage`，不要按当前探测模式删。业务层删除只认本行 `captureId` + `publishedUri`。

**Predecessor:** [2026-08-20-harmonyos-dynamic-color-honesty.md](2026-08-20-harmonyos-dynamic-color-honesty.md) 已推（Task 50 / `754afe3`）。交接：[2026-08-20-ohos-agent-handoff.md](../handoffs/2026-08-20-ohos-agent-handoff.md)。

## Global Constraints

- 长期 `ohos` 分支，不合 `main`，不开 PR。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`。`.github/workflows/ohos.yml` **可以**改。
- 不降 `sdk: ^3.12.2`。
- 不要 page-level `if (ohos)`。
- 无 dump 不得宣称拍成 / 相册 / 分享 / 通知 / 外链 / 像素对等。
- 官方测试必须 Flutter 3.44.6 + `--no-pub`；搅 lock 则 `git checkout -- pubspec.lock`。
- 用户已要求直接做到功能体验对齐；本刀 inline TDD，不用子代理。

## File map

- Modify: `.github/workflows/ohos.yml`
- Modify: `packages/sitemark_system_api/lib/src/ohos/gallery_store.dart`
- Test: `packages/sitemark_system_api/test/gallery_store_test.dart`
- Test: `packages/sitemark_system_api/test/publish_journal_store_test.dart`
- Test: `test/workflow/capture_media_service_test.dart`
- Docs: `README.md`, `tool/ohos/full_product_gap.md`, `tool/ohos/product_hap_review.md`, `docs/superpowers/handoffs/2026-08-20-ohos-agent-handoff.md`, `NEXT_AGENT_PROMPT.md`

---

### Task 51: 扩充 ohos.yml 测试清单

**Files:**
- Modify: `.github/workflows/ohos.yml`

把交接文档第 5 节已绿灯、但尚未进 CI 的文件补进 `flutter test`：

- `test/platform/degraded_image_pipeline_test.dart`
- `test/platform/jpeg_gps_test.dart`
- `test/platform/ohos_platform_services_test.dart`
- `test/features/settings/sections/storage_section_screen_test.dart`
- `test/features/settings/sections/appearance_section_screen_test.dart`
- `test/features/capture/capture_form_screen_test.dart`

保留现有队列 / sitemark_system_api / 隐私门 / processor / media / scheduler。多行 `run:` 便于审。

- [x] **Step 1:** 改 `ohos.yml`
- [x] **Step 2:** 本地用官方 3.44.6 跑同一清单，确认全绿

---

### Task 52: 删除/再发布按 captureId 语义测试补强

**Files:**
- Modify: `packages/sitemark_system_api/lib/src/ohos/gallery_store.dart`
- Test: `packages/sitemark_system_api/test/gallery_store_test.dart`
- Test: `packages/sitemark_system_api/test/publish_journal_store_test.dart`
- Test: `test/workflow/capture_media_service_test.dart`

**缺口：** `ProbingGalleryStore.delete` 按探测模式转发，模式切换后会漏删另一侧 URI。宿主 ETS 已按 URI 方案删除。Dart 适配器必须对齐：沙箱 `file://`（非 `file://media/` / `datashare://`）走 picker，其余走 ACL。同时锁住「同编号恢复副本不得串 URI」。

- [x] **Step 1: Write the failing tests**

相册：

- picker 两次同 `displayName`、不同 `captureId` → URI 含各自 id，互不 superseded
- ACL 删一个 URI，同 displayName 的另一张仍在
- picker 删 c1，c2 沙箱文件仍在
- ACL 发布后探测改 picker，仍能删掉 ACL URI
- picker 发布后探测改 ACL，仍能删掉沙箱文件

日记：两个 captureId 各记一条，清其中一个，另一个 recover 仍在。

业务层：

- 删刚恢复、`publishedUri == null` 的副本，不得删原项目 gallery URI
- 副本再发布后再删，只删副本自己的 URI

- [x] **Step 2: Run tests to verify the probing-delete tests fail**
- [x] **Step 3: Minimal implementation** — `ProbingGalleryStore.delete` 按 URI 方案路由，不再 `_resolve()` 到当前模式
- [x] **Step 4: Official tests green**
- [x] **Step 5: Honest docs + commit + push origin/ohos**

不得写系统相册 / 拍成 / 备份进系统文件管理已通。
