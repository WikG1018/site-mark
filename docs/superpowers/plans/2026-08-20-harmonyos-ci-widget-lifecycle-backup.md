# HarmonyOS CI: widget + lifecycle + backup import

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. User has already chosen **inline execution** (no subagents). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Task 55。规格门禁还缺 `test/widget_test.dart`、`test/app_lifecycle_test.dart`、备份/导入测试。把现有官方测试纳入 `.github/workflows/ohos.yml`。

**Architecture:** 不改生产语义。`ohos.yml` 是本分支自有 workflow，可以扩清单。备份导入走现有 `test/workflow/project_import_test.dart`、`test/workflow/project_export_test.dart` 与备份设置页测试。

**Predecessor:** [2026-08-20-harmonyos-capture-workflow-ci-delayed.md](2026-08-20-harmonyos-capture-workflow-ci-delayed.md) 已推（Task 54 / `bf0cb6c`）。

## Global Constraints

- 长期 `ohos` 分支，不合 `main`。
- 不改 `ci.yml` / `release.yml` / `android/` / `pigeons/`。
- 不降 `sdk: ^3.12.2`。不要 page-level `if (ohos)`。
- 无 dump 不得宣称拍成 / 相册 / 分享 / 通知 / 外链 / 像素对等。队列仍是应用内内存串行。
- 官方测试必须 Flutter 3.44.6 + `--no-pub`。
- 不要重做 Task 51–54。不要写 WorkScheduler。

## File map

- Modify: `.github/workflows/ohos.yml`
- Existing tests: `test/widget_test.dart`, `test/app_lifecycle_test.dart`, `test/workflow/project_import_test.dart`, `test/workflow/project_export_test.dart`, `test/features/settings/sections/backup_restore_section_screen_test.dart`
- Docs: `README.md`, `tool/ohos/full_product_gap.md`, `tool/ohos/product_hap_review.md`, `docs/superpowers/handoffs/2026-08-20-ohos-agent-handoff.md`, `NEXT_AGENT_PROMPT.md`

---

### Task 55: CI 纳入 widget / lifecycle / backup import

- [x] **Step 1: Official `--no-pub` on the missing files**
- [x] **Step 2: Add them to `ohos.yml`**
- [x] **Step 3: Honest docs + commit + push origin/ohos**

不得写系统相册 / 拍成 / WorkScheduler。写明 Task 46–55 Dart 未进 HAP。
