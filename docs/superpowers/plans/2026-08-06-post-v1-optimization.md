# SiteMark 1.0 发布后优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不扩产品边界的前提下，合入已审查的 #34–#37、收口数据路径安全与诊断、完成真机回归证据，并支持 Pre-release 标记 / 1.0.1 决策；体验性能作为 P1 跟进。

**Architecture:** 规格见 `docs/superpowers/specs/2026-08-06-post-v1-optimization-design.md`。工作包 WP-DOC → WP-MERGE → WP-DATA 与 WP-FIELD 并行 → 发布决策 → WP-UX。诊断只写枚举字段；用户错误禁止拼接原始异常；合并与发版必须维护者明确授权。

**Tech Stack:** Flutter 3.44、Dart 3.12、Riverpod、go_router、Drift、Workmanager 0.9、GitHub Actions、`gh` CLI、flutter_test

## Global Constraints

- `v1.0.0` **已经发布**（`1.0.0+15`）；Pre-release 只是 GitHub 标记，不是「尚未发版」。
- 不新开：云同步、账号、图库导入、内置相机、iOS、自由拖拽水印。
- 不 force-push `main`；不自动 merge；不擅自改 Release / 打 tag / 上传签名密钥。
- 用户可见错误禁止 `error.toString()` 与私有路径；诊断禁止项目名/路径/坐标/堆栈。
- 默认 PR CI 挡合并；integration 夜间/手动不挡 PR。
- 真机结论禁止用 CI 或模拟器冒充。
- 合入顺序固定：**#36 → #35 → #37 → #34**（除非维护者书面改序）。
- 本计划不修改 `pubspec.yaml` 版本号，除非进入明确的 1.0.1 任务且维护者授权。

---

## 文件结构

| 路径 | 职责 |
| --- | --- |
| `docs/superpowers/specs/2026-08-06-post-v1-optimization-design.md` | 已批准规格（只读参考） |
| `docs/superpowers/plans/2026-08-06-post-v1-optimization.md` | 本计划 |
| `docs/verification-v1.0.0-device.md` | 真机回归勾选（来自 #37 或合入后 main） |
| `docs/release-checklist.md` | 发布门禁 + Agent 入口 |
| `NEXT_AGENT_PROMPT.md` | 常驻 Agent 入口（#36） |
| `README.md` | 诊断覆盖表述须与接线代码一致 |
| `docs/current-product-architecture.md` | 架构与诊断说明 |
| `lib/features/projects/project_import_flow.dart` | `describeImportError` |
| `lib/features/projects/project_restore_flow.dart` | `describeProjectRestoreError`（Settings 真入口） |
| `lib/features/settings/sections/project_backup_selection_screen.dart` | `_describeBackupError` |
| `lib/workflow/project_deletion_service.dart` | 删除 + cleanup 诊断（#35） |
| `lib/workflow/project_bundle_service.dart` | 恢复诊断 `_throwRestore`（#37） |
| `lib/app.dart` | `projectDeletionServiceProvider` / `projectBundleServiceProvider` diagnostics |
| `lib/shared/ui/glass_surface.dart` | 玻璃 overlay/opacity（#34） |
| `lib/navigation/root_navigation_scaffold.dart` | 根分支滑动 scale |
| `test/features/projects/project_import_error_mapping_test.dart` | import 错误映射 |
| `test/workflow/project_deletion_service_test.dart` | 删除诊断 |
| `test/workflow/project_restore_diagnostics_test.dart` | 恢复诊断 |
| `test/shared/ui/glass_surface_test.dart` | 玻璃测试 |
| `.github/workflows/integration.yml` | 夜间/手动 integration（#37） |

---

### Task 1: 基线核对与计划入库

**Files:**
- Create: `docs/superpowers/plans/2026-08-06-post-v1-optimization.md`（本文件）
- Reference: `docs/superpowers/specs/2026-08-06-post-v1-optimization-design.md`

**Interfaces:**
- Consumes: 已批准规格 WP-DOC / MERGE / DATA / FIELD / UX
- Produces: 可勾选任务列表；后续 Task 依赖本文件存在于仓库

- [ ] **Step 1: 确认规格与在途 PR 仍打开**

Run:

```bash
test -f docs/superpowers/specs/2026-08-06-post-v1-optimization-design.md && echo SPEC_OK
gh pr view 34 --repo WikG1018/site-mark --json state,headRefOid --jq '{state,head:.headRefOid[0:7]}'
gh pr view 35 --repo WikG1018/site-mark --json state,headRefOid --jq '{state,head:.headRefOid[0:7]}'
gh pr view 36 --repo WikG1018/site-mark --json state,headRefOid --jq '{state,head:.headRefOid[0:7]}'
gh pr view 37 --repo WikG1018/site-mark --json state,headRefOid --jq '{state,head:.headRefOid[0:7]}'
gh release view v1.0.0 --repo WikG1018/site-mark --json isPrerelease,tagName
```

Expected: SPEC_OK；四 PR `state` 为 OPEN（若已合则在计划备注中划掉对应 MERGE 步）；`v1.0.0` 存在且 `isPrerelease` 如实记录。

- [ ] **Step 2: 将本计划提交到文档分支（若尚未提交）**

```bash
git status -sb
git add docs/superpowers/plans/2026-08-06-post-v1-optimization.md
git commit -m "docs: add post-v1 optimization implementation plan"
git push -u origin HEAD
```

若当前不在 `docs/post-v1-optimization-spec`，先：

```bash
git fetch origin main
git checkout -B docs/post-v1-optimization-spec origin/main
# 确保规格文件也在分支上，或 cherry-pick 9493538
```

- [ ] **Step 3: 更新 PR #38 说明，链到本计划**

```bash
gh pr edit 38 --repo WikG1018/site-mark --body "$(cat <<'EOF'
## Summary
- 规格：`docs/superpowers/specs/2026-08-06-post-v1-optimization-design.md`
- 计划：`docs/superpowers/plans/2026-08-06-post-v1-optimization.md`

## Next
维护者确认计划后，选择 subagent-driven-development 或 executing-plans 执行。
合入 #34–#37 需要单独明确授权。

EOF
)"
```

- [ ] **Step 4: 向维护者确认计划批准**

消息模板：「计划已写入 `docs/superpowers/plans/2026-08-06-post-v1-optimization.md`。是否批准执行？合入 #36/#35/#37/#34 是否一并授权？」

**Stop:** 未获「计划批准」前不得执行 Task 2 及之后的 merge。

---

### Task 2: 合入 PR #36（Agent / 文档入口）

**Files:**
- Merge via GitHub: PR #36 `docs/refresh-agent-entry`
- Touches (on that PR): `NEXT_AGENT_PROMPT.md`, `CONTRIBUTING.md`, `README.md`, `docs/release-checklist.md`

**Interfaces:**
- Consumes: 维护者 merge 授权
- Produces: main 上常驻 Agent 入口；checklist 含 Agent 链接与「1.0 已发布」表述（以 #36 头为准，#37 合入时再强化）

- [ ] **Step 1: 确认授权与 CI**

```bash
gh pr checks 36 --repo WikG1018/site-mark
gh pr view 36 --repo WikG1018/site-mark --json mergeable,title,url
```

Expected: checks 全绿或仅可忽略项；`mergeable` 为 MERGEABLE。

- [ ] **Step 2: 仅在维护者已明确授权 merge 时执行**

```bash
gh pr merge 36 --repo WikG1018/site-mark --merge --delete-branch=false
```

若维护者要求 squash：

```bash
gh pr merge 36 --repo WikG1018/site-mark --squash --delete-branch=false
```

- [ ] **Step 3: 更新本地 main**

```bash
git fetch origin main
git log origin/main --oneline -3
```

Expected: 可见 #36 相关 commit。

- [ ] **Step 4: 记录**

在 PR #38 或计划勾选旁注明：`#36 merged <date> <sha>`。

**Stop if:** 无授权 → 跳过 merge，在计划中标记 `SKIPPED-awaiting-auth`，继续 Task 6 中「仅审计已合代码」的变体（基于各 PR 分支 checkout 审计，不改 main）。

---

### Task 3: 合入 PR #35（删除诊断 + import 映射）

**Files:**
- PR #35 `fix/import-delete-failure-hardening`
- Key: `lib/workflow/project_deletion_service.dart`, `lib/features/projects/project_import_flow.dart`, `lib/app.dart`, tests under `test/workflow/project_deletion_service_test.dart`, `test/features/projects/project_import_error_mapping_test.dart`

**Interfaces:**
- Consumes: Task 2 后 main；或并行等待授权
- Produces: `projectDeletionServiceProvider` 带 `diagnostics`；cleanup 跳过仍存在项目 → `DiagnosticOutcome.blocked`

- [ ] **Step 1: 检查 CI 与 diff 相对 main**

```bash
gh pr checks 35 --repo WikG1018/site-mark
gh pr diff 35 --repo WikG1018/site-mark --name-only
```

- [ ] **Step 2: 授权后 merge**

```bash
gh pr merge 35 --repo WikG1018/site-mark --merge --delete-branch=false
git fetch origin main
```

- [ ] **Step 3: 在 main 上跑聚焦测试**

```bash
git checkout main
git pull origin main
flutter test test/workflow/project_deletion_service_test.dart test/features/projects/project_import_error_mapping_test.dart --concurrency=1
```

Expected: All tests passed.

- [ ] **Step 4: 记录** `#35 merged <date> <sha>`

---

### Task 4: 合入 PR #37（恢复诊断 + 真机清单 + integration）

**Files:**
- PR #37 `chore/post-v1-stability`
- Key: `lib/workflow/project_bundle_service.dart`, `docs/verification-v1.0.0-device.md`, `.github/workflows/integration.yml`, `lib/app.dart`, README/architecture

**Interfaces:**
- Consumes: #35 已合则 `app.dart` 已有 deletion diagnostics；本 PR 加 bundle diagnostics
- Produces: main 上真机清单文件；`ProjectBundleService.diagnostics`；integration 仅 schedule/dispatch

- [ ] **Step 1: 预览与 main 的冲突文件**

```bash
gh pr view 37 --repo WikG1018/site-mark --json mergeable,files --jq '{mergeable,files:[.files[].path]}'
git fetch origin main chore/post-v1-stability
git merge-tree $(git merge-base origin/main origin/chore/post-v1-stability) origin/main origin/chore/post-v1-stability 2>&1 | head -40
```

- [ ] **Step 2: 若 `docs/release-checklist.md` 冲突，合入后手动保证同时包含**

1. Agent → `NEXT_AGENT_PROMPT.md` 链接  
2. 「**v1.0.0 已发布**」与真机清单 `verification-v1.0.0-device.md` 链接  
3. 不得仅凭 CI 去掉 Pre-release 标记  

- [ ] **Step 3: 授权后 merge**

```bash
gh pr merge 37 --repo WikG1018/site-mark --merge --delete-branch=false
git fetch origin main && git checkout main && git pull origin main
```

- [ ] **Step 4: 聚焦测试**

```bash
flutter test test/workflow/project_restore_diagnostics_test.dart test/features/projects/project_detail_screen_test.dart --concurrency=1
dart analyze lib/workflow/project_bundle_service.dart lib/app.dart
```

Expected: tests pass；analyze 无 issues。

- [ ] **Step 5: 统一 README 诊断句（若仍分裂）**

目标句（合入 #35+#37 后）：

```markdown
- 诊断事件覆盖备份、恢复与删除结果（不含路径与项目内容）；
```

若某侧未合，不得写未接线能力。编辑后：

```bash
git add README.md docs/current-product-architecture.md
git commit -m "docs: align diagnostics coverage with merged services"
git push origin main
```

（仅在维护者允许直推 main 时；否则开小 PR `docs/align-diagnostics-wording`。）

---

### Task 5: 合入 PR #34（动效 / 玻璃，P1）

**Files:**
- PR #34 `feat/v1-motion-glass-polish-clean`
- Key: `lib/shared/ui/glass_surface.dart`, `lib/navigation/root_navigation_scaffold.dart`, `lib/navigation/root_navigation_dock.dart`, glass/nav tests

**Interfaces:**
- Consumes: 审查修复后的 overlay-under-content + opacity clamp
- Produces: main 上 P1 体验

- [ ] **Step 1: CI 与关键测试**

```bash
gh pr checks 34 --repo WikG1018/site-mark
```

本地（checkout PR 分支或合入后 main）：

```bash
flutter test test/shared/ui/glass_surface_test.dart test/navigation/root_navigation_scaffold_test.dart test/navigation/root_navigation_dock_test.dart --concurrency=1
```

Expected: All tests passed. 尤其：`overlay tint sits under content`、`clamps blur-enabled opacity`。

- [ ] **Step 2: 授权后 merge**

```bash
gh pr merge 34 --repo WikG1018/site-mark --merge --delete-branch=false
```

- [ ] **Step 3: 记录** `#34 merged`；P1 不阻塞 Task 7–8

---

### Task 6: 合入后数据路径审计（WP-DATA D5）

**Files:**
- Read: 全库 `lib/**/*.dart`（排除 `lib/src/rust/**`、`*.g.dart`）
- Modify only if发现泄漏：对应 UI 映射函数与测试
- Test: 现有 mapping/diagnostics 测试 + 必要时新测

**Interfaces:**
- Consumes: main 上 #35+#37 行为
- Produces: 审计记录（可写在 `docs/verification-v1.0.0-device.md` 附录或 issue 评论）；零已知 SnackBar 路径泄漏

- [ ] **Step 1: 扫描危险拼接**

```bash
git checkout main && git pull origin main
rg -n "importFailed\}:|'\\\$error|\"\\\$error|error\.toString\(\)|\$\{error" lib --glob '!**/src/rust/**' --glob '!**/*.g.dart'
rg -n "describeImportError|describeProjectRestoreError|_describeBackupError" lib --glob '!**/src/rust/**'
```

Expected: 无 `'${...}: $error'` 式用户文案；三套描述函数仍在。

- [ ] **Step 2: 确认诊断接线**

```bash
rg -n "diagnostics:" lib/app.dart
rg -n "DiagnosticCategory\.(backup|restore|deletion)" lib --glob '!**/src/rust/**'
```

Expected: backup / restore / deletion 均有记录点；`projectDeletionServiceProvider` 与 `projectBundleServiceProvider` 传入 `diagnosticRecorderProvider`。

- [ ] **Step 3: 跑数据路径测试簇**

```bash
flutter test \
  test/workflow/project_deletion_service_test.dart \
  test/workflow/project_restore_diagnostics_test.dart \
  test/workflow/project_import_test.dart \
  test/workflow/project_bundle_service_test.dart \
  test/features/projects/project_import_error_mapping_test.dart \
  test/features/settings/sections/backup_restore_section_screen_test.dart \
  --concurrency=1
```

Expected: All tests passed（若某文件仅在未合 PR 上，跳过并注明）。

- [ ] **Step 4: 若发现泄漏，TDD 修复**

1. 先写失败测试：断言 message `isNot(contains('/data/'))` 且 `isNot(contains('StateError'))`。  
2. 改映射函数去掉原始拼接。  
3. 再跑测试 PASS。  
4. Commit：`fix: remove user-visible raw exception text in <surface>`

- [ ] **Step 5: 提交审计笔记（可选小 commit）**

在 `docs/verification-v1.0.0-device.md` 文末追加：

```markdown
## 附录 A — 数据路径审计

| 日期 | main SHA | 泄漏扫描 | 诊断接线 | 测试簇 |
| --- | --- | --- | --- | --- |
| YYYY-MM-DD | abc1234 | PASS/FAIL | backup+restore+deletion | PASS/FAIL |
```

```bash
git add docs/verification-v1.0.0-device.md
git commit -m "docs: record post-merge data-path audit"
```

---

### Task 7: 真机回归执行（WP-FIELD）

**Files:**
- Modify: `docs/verification-v1.0.0-device.md`（填表，不改产品代码）

**Interfaces:**
- Consumes: 可安装的 arm64 APK（Release v1.0.0 或 main 构建）
- Produces: §0 矩阵 ≥2 行；§2/§4 勾选；§9 决策摘要

- [ ] **Step 1: 确认清单在 main**

```bash
test -f docs/verification-v1.0.0-device.md && head -20 docs/verification-v1.0.0-device.md
```

若文件仍只在 #37：先完成 Task 4，或从 PR 检出只读复制说明。

- [ ] **Step 2: 准备安装包**

优先：

```text
https://github.com/WikG1018/site-mark/releases/tag/v1.0.0
```

若验证「合入后 main」：

```bash
flutter build apk --release
# 产物路径以本机 build/ 为准；签名策略遵循 release-checklist
```

- [ ] **Step 3: 人工执行清单 §0–§4、§6–§7**

最低要求：

- §0 ≥2 类厂商（例如小米系 + Pixel/三星）  
- §2 连拍 ≥10、杀进程恢复  
- §4 单项目备份恢复至少一次  

- [ ] **Step 4: 填写 §9 结果摘要**

```markdown
| 日期 | 版本 | 通过机型数 | 阻塞问题 | 决定 |
| --- | --- | --- | --- | --- |
| 2026-08-xx | 1.0.0+15 | 2 | 无 / 列出 issue | 保持 Pre-release / 去标记 / 发 1.0.1 |
```

- [ ] **Step 5: 提交填表结果**

```bash
git add docs/verification-v1.0.0-device.md
git commit -m "docs: fill v1.0 device regression results"
git push
```

**Stop if:** 无真机 — 在 §9 写「待真机」，**不得**在 Task 8 宣称可去 Pre-release。

---

### Task 8: 发布决策包（不自动改 GitHub）

**Files:**
- Possibly: `docs/verification-v1.0.0-device.md` §8–§9 only  
- Does **not** run `gh release edit` unless维护者**另行**粘贴授权句

**Interfaces:**
- Consumes: Task 6 审计 + Task 7 真机表  
- Produces: 决策记录；可选 1.0.1 范围列表

- [ ] **Step 1: 汇总证据清单**

输出一段维护者可读摘要：

```text
DATA audit: PASS/FAIL
Device matrix rows: N
§2/§4 open failures: ...
Open PRs remaining: ...
Recommendation: keep-prerelease | unmark | cut-1.0.1
```

- [ ] **Step 2: 若推荐 unmark — 仅生成命令，不执行**

```bash
# 维护者授权后才可运行：
# gh release edit v1.0.0 --repo WikG1018/site-mark --prerelease=false
```

- [ ] **Step 3: 若推荐 1.0.1 — 列出纳入提交范围**

示例范围（按实际 merge 调整）：

```text
- #35 删除诊断 + import 映射
- #37 恢复诊断 + 真机清单 + integration workflow
- #34 动效/玻璃（若合）
- #36 Agent 入口
- 审计/真机文档 commit
```

版本号变更**另开** `chore/prepare-1.0.1` 任务，修改 `pubspec.yaml` `version:` 与关于页兜底，遵循 `docs/release-checklist.md`。本 Task **不**改版本号。

- [ ] **Step 4: 提交决策摘要（文档）**

```bash
git commit -m "docs: record v1.0 maintenance release decision"
```

---

### Task 9: P1 体验验收与可选内存跟进

**Files:**
- Read: `lib/navigation/root_navigation_scaffold.dart`, `lib/shared/ui/glass_surface.dart`, `lib/main.dart`（imageCache）, `lib/platform/memory_pressure_coordinator.dart`
- Modify: only if Task 7 §7 有**可复现**卡顿证据

**Interfaces:**
- Consumes: #34 已合 main  
- Produces: §7 观察记录；或可选小 PR（非必须）

- [ ] **Step 1: 确认 glass 契约测试仍在 main**

```bash
flutter test test/shared/ui/glass_surface_test.dart --concurrency=1
```

Expected: PASS（含 under-content 与 clamp）。

- [ ] **Step 2: 真机 §7 观察（可与 Task 7 同场）**

勾选：

- 三页滚过缩略图后反复 Dock 切换是否明显卡顿  
- 若卡顿：机型、Android 版本、步骤  

- [ ] **Step 3: 无证据则停止（YAGNI）**

不要拆 Offstage 保活。在清单 §7 注明「观察通过，无代码变更」。

- [ ] **Step 4: 仅当有证据时开缓解 PR（单独计划外 PR）**

允许方向（示例，需新失败测试或 profiling 笔记）：

- 非当前根分支降低图片 decode 优先级 / 离开时 `evict`  
- 禁止：默认去掉三分支保活、手指横滑切页  

Commit message 示例：`perf: reduce inactive root-branch image cache pressure`

---

### Task 10: 收尾核对（verification-before-completion）

**Files:** none required

- [ ] **Step 1: 对照规格成功标准打勾**

| 规格标准 | 本计划证据 |
| --- | --- |
| 规格无 TBD | spec 文件 |
| 计划存在 | 本文件 |
| P0 代码 | Task 6 测试簇 |
| P0 现场 | Task 7 填表 |
| P1 | Task 5+9 |
| 发布决策 | Task 8 |

- [ ] **Step 2: 运行合入后主回归（main）**

```bash
git checkout main && git pull origin main
dart format --output=none --set-exit-if-changed lib test pigeons packages/sitemark_system_api/lib
flutter analyze
flutter test
```

Expected: format clean；analyze 0 issues；test 全绿（耗时长，可在 CI 确认）。

- [ ] **Step 3: 向维护者交付摘要**

```text
Merged: #36 #35 #37 #34 (list actual)
Data audit: ...
Device: ...
Decision: ...
Follow-ups: ...
```

---

## Spec coverage（自检）

| 规格章节 | 计划任务 |
| --- | --- |
| §2 P0 现场 | Task 7, 8 |
| §2 P0 数据 | Task 3, 4, 6 |
| §2 P1 体验 | Task 5, 9 |
| §3 非目标 | Global Constraints + Task 8/9 边界 |
| §5 阶段 0–5 | Task 1–10 |
| §6 WP-DOC | Task 1 |
| §6 WP-MERGE | Task 2–5 |
| §6 WP-DATA | Task 6 |
| §6 WP-FIELD | Task 7–8 |
| §6 WP-UX | Task 5, 9 |
| 人工门禁 | 每 Task merge/release 的 Stop 条件 |

## Placeholder scan

无 TBD/TODO/「类似 Task N」/空「写测试」步骤；merge 命令完整；审计用具体 `rg`/`flutter test` 命令。

---

## 执行交接

计划完成并保存于 `docs/superpowers/plans/2026-08-06-post-v1-optimization.md`。

**两种执行方式：**

1. **Subagent-Driven（推荐）** — 每任务新开 subagent，任务间审查（`superpowers:subagent-driven-development`）  
2. **Inline Execution** — 本会话按 `superpowers:executing-plans` 顺序执行，设检查点  

**请选择 1 或 2。**  
若尚未授权 merge #34–#37，执行时 Task 2–5 会停在授权门禁，可先做 Task 1 与基于分支的只读审计变体。
