# SiteMark v0.10 项目生命周期管理实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为项目增加进行中、已完成、已归档和置顶能力，并在首页、拍摄保护、备份恢复中保持一致。

**Architecture:** Drift schema 11 保存生命周期与置顶；项目汇总查询负责照片数量、最近拍摄时间和稳定排序；独立 `ProjectLifecycleService` 在事务内执行状态变更并阻止处理中项目。单项目备份升级为 schema 5，Rust 严格验证后把标准化状态交给 Dart 恢复流程。

**Tech Stack:** Flutter 3.44 / Dart 3.12、Riverpod、GoRouter、Drift/SQLite、Rust、flutter_rust_bridge、Flutter/Rust/Android tests

## Global Constraints

- 生命周期存储值只能是 `active`、`completed`、`archived`。
- `completed` 和 `archived` 必须在数据层禁止新拍摄，但不得限制已有记录的查看、编辑、导出和清理。
- `pendingCamera`、`captured`、`rendering` 阻止完成或归档；`failed` 需要显式确认。
- 置顶与生命周期独立；排序为置顶、最近拍摄时间、项目创建时间、项目 ID。
- 首页默认进行中；搜索跨全部状态；归档恢复后仍归档。
- 单项目 ZIP 升级到 schema 5；v1-v4 恢复为进行中且未置顶；多项目外层 schema 保持 1。
- 不实现项目配置复制、标签、分组、自动归档、批量状态变更、云同步或诊断中心。
- 不手改 Drift 或 flutter_rust_bridge 生成文件，必须运行生成器。
- 目标版本 `0.10.0+14`；只提交功能分支，不推送、合并、打标签或发布。

---

## 文件结构

- Create `lib/domain/project_lifecycle.dart`：枚举、数据库转换器、只读异常。
- Create `lib/domain/project_summary.dart`：首页项目汇总值对象。
- Create `lib/workflow/project_lifecycle_service.dart`：状态预检、并发保护和事务提交。
- Create `lib/features/projects/project_status_filter_sheet.dart`：紧凑状态筛选底部弹层。
- Modify `lib/data/app_database.dart`：schema 11、迁移、汇总查询、置顶、状态写入、拍摄保护。
- Regenerate `lib/data/app_database.g.dart`：Drift 表、数据类和 companion。
- Modify `lib/features/projects/project_list_screen.dart`：状态筛选、汇总卡片、跨状态搜索、生命周期菜单。
- Modify `lib/features/projects/project_detail_screen.dart`：状态提示、生命周期操作、隐藏拍摄按钮。
- Modify `lib/app.dart`：生命周期服务 Provider。
- Modify `rust/src/api/image_core.rs`：单项目备份 schema 5 与严格验证。
- Regenerate `rust/src/frb_generated.rs` and `lib/src/rust/**`：桥接字段。
- Modify `lib/workflow/project_export_service.dart`、`project_import_service.dart`、`project_bundle_service.dart`：状态与置顶导出、恢复和结果统计。
- Modify `lib/features/projects/project_restore_flow.dart`：恢复状态摘要与归档入口。
- Modify `lib/l10n/app_strings.dart`：中英文生命周期文案。
- Modify `pubspec.yaml`、`lib/features/settings/sections/about_section_screen.dart`、README 和当前设计文档：版本与能力同步。

---

### Task 1: 生命周期类型、schema 11 与迁移

**Files:**
- Create: `lib/domain/project_lifecycle.dart`
- Modify: `lib/data/app_database.dart`
- Regenerate: `lib/data/app_database.g.dart`
- Test: `test/domain/project_lifecycle_test.dart`
- Test: `test/data/app_database_migration_test.dart`

**Interfaces:**
- Produces: `enum ProjectLifecycleStatus { active, completed, archived }`
- Produces: `ProjectLifecycleStatusConverter`
- Produces: `ProjectReadOnlyException(projectId, status)`
- Produces: generated `Project.lifecycleStatus` and `Project.isPinned`

- [ ] **Step 1: 写枚举契约失败测试**

```dart
test('lifecycle storage values are stable', () {
  expect(ProjectLifecycleStatus.values.map((value) => value.name),
      ['active', 'completed', 'archived']);
  const converter = ProjectLifecycleStatusConverter();
  expect(converter.fromSql('completed'), ProjectLifecycleStatus.completed);
  expect(converter.toSql(ProjectLifecycleStatus.archived), 'archived');
  expect(() => converter.fromSql('deleted'), throwsStateError);
});
```

Run: `flutter test test/domain/project_lifecycle_test.dart`
Expected: FAIL，因为类型尚不存在。

- [ ] **Step 2: 实现领域类型**

```dart
enum ProjectLifecycleStatus { active, completed, archived }

class ProjectLifecycleStatusConverter
    extends TypeConverter<ProjectLifecycleStatus, String> {
  const ProjectLifecycleStatusConverter();
  @override
  ProjectLifecycleStatus fromSql(String value) =>
      ProjectLifecycleStatus.values.byName(value);
  @override
  String toSql(ProjectLifecycleStatus value) => value.name;
}

final class ProjectReadOnlyException implements Exception {
  const ProjectReadOnlyException(this.projectId, this.status);
  final String projectId;
  final ProjectLifecycleStatus status;
}
```

- [ ] **Step 3: 写 schema 10→11 迁移测试**

在 `test/data/app_database_migration_test.dart` 增加真实 v10 fixture，创建当前 v10 的三张表并插入一个项目，设置 `PRAGMA user_version = 10`。打开 `AppDatabase.forTesting` 后断言：

```dart
expect(database.schemaVersion, 11);
final project = await database.projectById('existing');
expect(project!.lifecycleStatus, ProjectLifecycleStatus.active);
expect(project.isPinned, isFalse);
```

同时在 fresh database 测试中新建项目并断言同样默认值。

Run: `flutter test test/data/app_database_migration_test.dart`
Expected: FAIL，因为 schema 仍为 10 且列不存在。

- [ ] **Step 4: 修改表和迁移并重新生成 Drift**

在 `Projects` 墀加：

```dart
TextColumn get lifecycleStatus => text()
    .map(const ProjectLifecycleStatusConverter())
    .withDefault(const Constant('active'))();
BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
```

把 `schemaVersion` 改为 11，在 `onUpgrade` 添加：

```dart
if (from < 11) {
  await migrator.addColumn(projects, projects.lifecycleStatus);
  await migrator.addColumn(projects, projects.isPinned);
}
```

执行：

```powershell
dart run build_runner build --delete-conflicting-outputs
dart format lib/domain/project_lifecycle.dart lib/data/app_database.dart test/domain/project_lifecycle_test.dart test/data/app_database_migration_test.dart
flutter test test/domain/project_lifecycle_test.dart test/data/app_database_migration_test.dart
```

Expected: PASS，生成文件只出现生命周期和置顶相关变化。

- [ ] **Step 5: 提交**

```powershell
git add lib/domain/project_lifecycle.dart lib/data/app_database.dart lib/data/app_database.g.dart test/domain/project_lifecycle_test.dart test/data/app_database_migration_test.dart
git commit -m "feat: persist project lifecycle status"
```

---

### Task 2: 项目汇总、稳定排序、置顶和拍摄数据层保护

**Files:**
- Create: `lib/domain/project_summary.dart`
- Modify: `lib/data/app_database.dart`
- Test: `test/data/project_summary_query_test.dart`
- Test: `test/data/app_database_test.dart`

**Interfaces:**
- Consumes: `Project.lifecycleStatus`, `Project.isPinned`
- Produces: `ProjectSummary(project, captureCount, lastCaptureAt)`
- Produces: `watchProjectSummaries({ProjectLifecycleStatus? status, String search = ''})`
- Produces: `watchProjectById(projectId) -> Stream<Project?>`
- Produces: `setProjectPinned(projectId, isPinned)`
- Produces: `updateProjectLifecycleStatus(projectId, expectedStatus, targetStatus) -> Project?`

- [ ] **Step 1: 写汇总排序失败测试**

创建进行中、完成、归档和空白项目，插入相同时间、不同时间、`pendingCamera` 与 `ready` 记录。断言：

```dart
final active = await database.watchProjectSummaries(
  status: ProjectLifecycleStatus.active,
).first;
expect(active.map((item) => item.project.id), ['pinned', 'recent', 'empty']);
expect(active.first.captureCount, 1);
expect(active.first.lastCaptureAt, DateTime(2026, 8, 3, 10));

final search = await database.watchProjectSummaries(search: '归档厂房').first;
expect(search.single.project.lifecycleStatus, ProjectLifecycleStatus.archived);
```

还要断言 restore-owned 项目被排除，置顶取消后按拍摄时间恢复顺序，时间相同时由创建时间和 ID 稳定排序。

Run: `flutter test test/data/project_summary_query_test.dart`
Expected: FAIL，因为汇总接口尚不存在。

- [ ] **Step 2: 实现汇总查询和置顶**

`ProjectSummary` 使用不可变字段：

```dart
final class ProjectSummary {
  const ProjectSummary({
    required this.project,
    required this.captureCount,
    required this.lastCaptureAt,
  });
  final Project project;
  final int captureCount;
  final DateTime? lastCaptureAt;
}
```

使用绑定参数的 `customSelect`，`LEFT JOIN captures` 时排除 `pendingCamera`，按以下 SQL 语义聚合：

```sql
COUNT(c.id) AS capture_count,
MAX(COALESCE(c.captured_at, c.created_at)) AS last_capture_at
```

查询必须包含 `p.restore_operation_id IS NULL`，非空搜索使用 `LOWER(p.name) LIKE ? ESCAPE '\\'`，并转义 `%`、`_`、`\\`。排序固定为：

```sql
p.is_pinned DESC,
CASE WHEN last_capture_at IS NULL THEN 1 ELSE 0 END,
last_capture_at DESC,
p.created_at DESC,
p.id ASC
```

`setProjectPinned` 更新 `isPinned`，不要修改 `updatedAt`，避免置顶操作伪造项目业务更新时间。

`watchProjectById` 直接监听目标项目行，供详情页和拍摄表单响应其他页面的状态变化。`createProject` 增加具名参数 `lifecycleStatus = ProjectLifecycleStatus.active` 与 `isPinned = false`，普通新建保持默认值，恢复流程可显式传值。

- [ ] **Step 3: 写只读拍摄和条件状态写入失败测试**

```dart
await database.updateProjectLifecycleStatus(
  projectId: 'done',
  expectedStatus: ProjectLifecycleStatus.active,
  targetStatus: ProjectLifecycleStatus.completed,
);
expect(
  () => database.createPendingCapture(/* projectId: 'done', ... */),
  throwsA(isA<ProjectReadOnlyException>()),
);
expect(await database.updateProjectLifecycleStatus(
  projectId: 'done',
  expectedStatus: ProjectLifecycleStatus.active,
  targetStatus: ProjectLifecycleStatus.archived,
), isNull);
```

Run: `flutter test test/data/app_database_test.dart`
Expected: FAIL，当前插入不检查项目状态。

- [ ] **Step 4: 在事务内实现写保护**

`createPendingCapture` 改为 `transaction`：先读取项目；不存在抛 `StateError('Project does not exist')`，非 active 抛 `ProjectReadOnlyException`，再插入记录。`updateProjectLifecycleStatus` 使用 `WHERE id = ? AND lifecycle_status = ?` 条件更新，更新数量不是 1 时返回 null；成功后读取并返回项目。

执行：

```powershell
dart format lib/domain/project_summary.dart lib/data/app_database.dart test/data/project_summary_query_test.dart test/data/app_database_test.dart
flutter test test/data/project_summary_query_test.dart test/data/app_database_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/domain/project_summary.dart lib/data/app_database.dart test/data/project_summary_query_test.dart test/data/app_database_test.dart
git commit -m "feat: query and protect project lifecycle"
```

---

### Task 3: 生命周期服务与并发保护

**Files:**
- Create: `lib/workflow/project_lifecycle_service.dart`
- Modify: `lib/app.dart`
- Test: `test/workflow/project_lifecycle_service_test.dart`

**Interfaces:**
- Produces: `ProjectLifecyclePreview(project, targetStatus, processingCount, failedCount)`
- Produces: `preview(projectId, targetStatus)`
- Produces: `transition(preview, {required bool confirmFailed}) -> Project`
- Produces: typed `ProjectLifecycleProcessingException`, `ProjectLifecycleConfirmationRequiredException`, `ProjectLifecycleConflictException`

- [ ] **Step 1: 写服务失败测试**

覆盖以下独立场景：

```dart
expect((await service.preview('active', ProjectLifecycleStatus.completed))
    .processingCount, 0);
expect(
  () => service.transition(processingPreview, confirmFailed: false),
  throwsA(isA<ProjectLifecycleProcessingException>()),
);
expect(
  () => service.transition(failedPreview, confirmFailed: false),
  throwsA(isA<ProjectLifecycleConfirmationRequiredException>()),
);
expect((await service.transition(failedPreview, confirmFailed: true))
    .lifecycleStatus, ProjectLifecycleStatus.completed);
```

另外验证全部合法转换；转换表中未列出的转换和相同状态转换均被拒绝；预检后另一调用先改状态时抛 conflict；事务提交前新增 processing 记录时必须重新计数并阻止。

Run: `flutter test test/workflow/project_lifecycle_service_test.dart`
Expected: FAIL，因为服务尚不存在。

- [ ] **Step 2: 实现不可伪造的预检对象和事务提交**

`ProjectLifecyclePreview` 保存项目 ID、预期状态、目标状态和数量。服务内部使用允许转换集合：

```dart
const allowed = {
  ProjectLifecycleStatus.active: {
    ProjectLifecycleStatus.completed,
    ProjectLifecycleStatus.archived,
  },
  ProjectLifecycleStatus.completed: {
    ProjectLifecycleStatus.active,
    ProjectLifecycleStatus.archived,
  },
  ProjectLifecycleStatus.archived: {ProjectLifecycleStatus.active},
};
```

`transition` 必须开启数据库事务、重新读取项目并重新统计 `pendingCamera/captured/rendering` 与 `failed`；处理中始终阻止，失败且 `confirmFailed == false` 要求确认；最后调用条件状态更新，null 结果视为冲突。

在 `lib/app.dart` 注册：

```dart
final projectLifecycleServiceProvider = Provider<ProjectLifecycleService>((ref) {
  return ProjectLifecycleService(ref.watch(databaseProvider));
});
```

- [ ] **Step 3: 运行服务与拍摄工作流回归测试**

```powershell
dart format lib/workflow/project_lifecycle_service.dart lib/app.dart test/workflow/project_lifecycle_service_test.dart
flutter test test/workflow/project_lifecycle_service_test.dart test/workflow/capture_workflow_test.dart
```

Expected: PASS；已有 active 项目拍摄流程不变。

- [ ] **Step 4: 提交**

```powershell
git add lib/workflow/project_lifecycle_service.dart lib/app.dart test/workflow/project_lifecycle_service_test.dart
git commit -m "feat: manage project lifecycle transitions"
```

---

### Task 4: 首页状态筛选、汇总卡片和生命周期操作

**Files:**
- Create: `lib/features/projects/project_status_filter_sheet.dart`
- Modify: `lib/features/projects/project_list_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/features/projects/project_list_screen_test.dart`
- Test: `test/l10n/app_strings_test.dart`

**Interfaces:**
- Consumes: `watchProjectSummaries`, `ProjectLifecycleService`
- Produces: keys `project-status-filter`, `project-status-active/completed/archived`, `project-pin-<id>`, `project-lifecycle-<id>`

- [ ] **Step 1: 写首页行为失败测试**

测试必须证明：默认只显示 active；底部弹层切换 completed/archived；搜索时三个状态都能命中并显示状态文字；退出搜索恢复原筛选；卡片显示照片数、最近时间和置顶；状态弹层系统返回只关闭弹层；360dp 与 textScale 1.5 无溢出；`disableAnimations: true` 时不添加自定义过渡。

关键断言：

```dart
expect(find.text('已归档'), findsNothing);
await tester.tap(find.byKey(const Key('project-status-filter')));
await tester.tap(find.byKey(const Key('project-status-archived')));
expect(find.text('归档厂房'), findsOneWidget);
await tester.tap(find.byKey(const Key('search-projects')));
await tester.enterText(find.byKey(const Key('project-search-field')), '已完成项目');
expect(find.byKey(const Key('project-status-badge-completed')), findsOneWidget);
```

Run: `flutter test test/features/projects/project_list_screen_test.dart test/l10n/app_strings_test.dart`
Expected: FAIL。

- [ ] **Step 2: 实现紧凑筛选弹层**

`showProjectStatusFilterSheet` 返回 `Future<ProjectLifecycleStatus?>`。使用 `showModalBottomSheet`、`SafeArea` 和三个 `ListTile`，当前项显示 check；动画由 Material 路由负责，`MediaQuery.disableAnimations` 时不额外添加动画组件。

- [ ] **Step 3: 把首页切换到项目汇总流**

状态保存在 `_status = ProjectLifecycleStatus.active`。非搜索传 `_status`，搜索传 `status: null` 和 `_query`。卡片组件接收 `ProjectSummary`，用 `Wrap` 展示状态、照片数、最近拍摄和置顶，不能用固定宽度。空状态按状态分别显示；搜索无结果仍保留退出入口。

卡片更多菜单根据状态显示：

- active：置顶/取消置顶、标记完成、归档；
- completed：置顶/取消置顶、重新启用、归档；
- archived：置顶/取消置顶、恢复使用。

状态操作先 `preview`；processing 显示阻止数量；failed 显示确认对话框；确认后 `transition`。冲突时提示“项目状态已变化，请重试”，依赖数据库流自动刷新卡片。

- [ ] **Step 4: 补齐中英文文案并验证**

文案必须包含状态名、筛选标题、置顶、取消置顶、标记完成、归档、重新启用、处理中阻止、失败记录确认、冲突、三种空状态、照片数量和最近拍摄。

```powershell
dart format lib/features/projects/project_status_filter_sheet.dart lib/features/projects/project_list_screen.dart lib/l10n/app_strings.dart test/features/projects/project_list_screen_test.dart test/l10n/app_strings_test.dart
flutter test test/features/projects/project_list_screen_test.dart test/l10n/app_strings_test.dart
```

Expected: PASS，无 overflow exception。

- [ ] **Step 5: 提交**

```powershell
git add lib/features/projects/project_status_filter_sheet.dart lib/features/projects/project_list_screen.dart lib/l10n/app_strings.dart test/features/projects/project_list_screen_test.dart test/l10n/app_strings_test.dart
git commit -m "feat: browse projects by lifecycle status"
```

---

### Task 5: 项目详情只读状态与操作入口

**Files:**
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `lib/features/capture/capture_form_screen.dart`
- Test: `test/widget_test.dart`
- Test: `test/features/capture/capture_form_screen_test.dart`

**Interfaces:**
- Consumes: `ProjectLifecycleService`, `ProjectReadOnlyException`
- Produces: keys `project-status-banner`, `reopen-project`, `capture-read-only`

- [ ] **Step 1: 写详情页失败测试**

分别打开 completed 与 archived 项目，断言状态横幅存在、`capture-fab` 不存在、已有记录和编辑按钮仍存在、重新启用后拍摄按钮恢复。active 项目无横幅且保留拍摄按钮。

直接打开 `/projects/completed/capture`，提交表单时断言不会调用系统相机，并显示只读提示；用于锁定深层路由和旧页面状态不能绕过数据层。

Run: `flutter test test/widget_test.dart test/features/capture/capture_form_screen_test.dart`
Expected: FAIL。

- [ ] **Step 2: 实现详情状态横幅和菜单**

把 `_projectFuture` 与 `FutureBuilder` 替换为 `database.watchProjectById(widget.projectId)` 的 `StreamBuilder<Project?>`，并用 `initialProject` 作为 `initialData`，确保其他页面修改状态会刷新。`_ProjectHeader` 下方为非 active 项目添加可换行的 Material banner，显示状态原因和“重新启用”。

`floatingActionButton` 的条件增加：

```dart
project.lifecycleStatus != ProjectLifecycleStatus.active || editing
    ? const SizedBox.shrink()
    : FloatingActionButton.extended(/* existing capture action */)
```

详情更多菜单增加与首页一致的生命周期操作；已有重命名、删除保持不变。

- [ ] **Step 3: 捕获深层路由只读异常**

拍摄页加载项目后若非 active，显示 `capture-read-only` 状态并禁用提交。即便页面加载后状态变化，`createPendingCapture` 抛出的 `ProjectReadOnlyException` 也必须转为用户可读提示，不能显示原始异常或启动相机。

- [ ] **Step 4: 运行详情、导航和返回回归**

```powershell
dart format lib/features/projects/project_detail_screen.dart lib/features/capture/capture_form_screen.dart test/widget_test.dart test/features/capture/capture_form_screen_test.dart
flutter test test/widget_test.dart test/features/capture/capture_form_screen_test.dart test/features/capture/capture_search_paging_ui_test.dart
```

Expected: PASS；编辑模式返回仍只取消编辑，搜索返回仍先退出搜索。

- [ ] **Step 5: 提交**

```powershell
git add lib/features/projects/project_detail_screen.dart lib/features/capture/capture_form_screen.dart test/widget_test.dart test/features/capture/capture_form_screen_test.dart
git commit -m "feat: make completed projects capture read only"
```

---

### Task 6: 单项目备份 schema 5 与跨层严格验证

**Files:**
- Modify: `rust/src/api/image_core.rs`
- Modify: `rust/tests/core_test.rs`
- Modify: `lib/workflow/project_export_service.dart`
- Modify: `lib/workflow/project_import_service.dart`
- Regenerate: `rust/src/frb_generated.rs`
- Regenerate: `lib/src/rust/api/image_core.dart`
- Regenerate: `lib/src/rust/frb_generated.dart`
- Regenerate: `lib/src/rust/frb_generated.io.dart`
- Regenerate: `lib/src/rust/frb_generated.web.dart`
- Test: `test/workflow/project_export_test.dart`
- Test: `test/workflow/project_import_test.dart`

**Interfaces:**
- Adds to `ExportProjectRequest`: `projectLifecycleStatus: String`, `projectIsPinned: bool`
- Adds to `ProjectArchivePreview`: normalized `projectLifecycleStatus: String`, `projectIsPinned: bool`
- Adds to `ProjectImportResult`: `lifecycleStatus`, `isPinned`

- [ ] **Step 1: 写 Rust schema 5 失败测试**

新增测试验证导出 manifest 精确包含：

```json
{
  "schema_version": 5,
  "project_lifecycle_status": "archived",
  "project_is_pinned": true
}
```

再建立 v1-v4 fixtures，断言 preview 标准化为 `active/false`；v5 缺字段、未知状态、字符串形式的布尔值均拒绝；合法 active/completed/archived 均接受；外层 bundle schema 仍为 1。

Run: `cargo test --manifest-path rust/Cargo.toml project_archive -- --nocapture`
Expected: FAIL。

- [ ] **Step 2: 修改 Rust 请求、manifest 和 preview**

`ExportProjectRequest` 增加 String/bool；导出前验证状态集合；`ExportManifest` 写两个字段并把 schema 改为 5。

`ProjectManifestFile` 使用：

```rust
#[serde(default)]
project_lifecycle_status: Option<String>,
#[serde(default)]
project_is_pinned: Option<bool>,
```

解析规则：schema 5 两字段都必须存在且状态合法；schema 1..=4 无论字段缺失都标准化为 `active`、`false`；支持范围改为 `1..=5`。`ProjectArchivePreview` 返回非可空的标准化 String/bool。

- [ ] **Step 3: 写 Dart 导入导出失败测试**

导出测试断言 `ExportProjectRequest` 收到项目真实状态和置顶；导入测试分别传 v4 与 v5 preview，断言 `createProject` 最终保存默认值或原值。非法 preview 状态在 Dart 再次拒绝，不能只信任桥接层。

Run: `flutter test test/workflow/project_export_test.dart test/workflow/project_import_test.dart`
Expected: FAIL。

- [ ] **Step 4: 修改 Dart 服务并生成桥接**

`ProjectExportService` 把 `project.lifecycleStatus.name` 与 `project.isPinned` 传给 Rust。`ProjectImportService._validatedPreview` 支持 1..5；v5 用 `ProjectLifecycleStatus.values.byName` 验证，v1-v4固定 active/false；`createProject` 增加 lifecycleStatus/isPinned 参数。`ProjectImportResult` 返回最终状态与置顶。

执行：

```powershell
cargo fmt --manifest-path rust/Cargo.toml
cargo test --manifest-path rust/Cargo.toml
flutter_rust_bridge_codegen generate
dart format lib/workflow/project_export_service.dart lib/workflow/project_import_service.dart test/workflow/project_export_test.dart test/workflow/project_import_test.dart
flutter test test/workflow/project_export_test.dart test/workflow/project_import_test.dart
```

Expected: Rust 与 Dart 聚焦测试通过，生成文件与源接口一致。

- [ ] **Step 5: 提交**

```powershell
git add rust/src/api/image_core.rs rust/src/frb_generated.rs rust/tests/core_test.rs lib/src/rust lib/workflow/project_export_service.dart lib/workflow/project_import_service.dart test/workflow/project_export_test.dart test/workflow/project_import_test.dart
git commit -m "feat: preserve lifecycle in project backups"
```

---

### Task 7: 多项目恢复状态摘要和归档入口

**Files:**
- Modify: `lib/workflow/project_bundle_service.dart`
- Modify: `lib/features/projects/project_restore_flow.dart`
- Modify: `lib/features/settings/sections/project_backup_selection_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/workflow/project_bundle_service_test.dart`
- Test: `test/features/settings/sections/backup_restore_section_screen_test.dart`
- Test: `test/features/settings/sections/project_backup_selection_screen_test.dart`

**Interfaces:**
- Consumes: `ProjectImportResult.lifecycleStatus`, `ProjectImportResult.isPinned`
- Produces: restore summary counts for active/completed/archived
- Produces: restore result action that selects archived projects on home

- [ ] **Step 1: 写多项目恢复失败测试**

构造 active、completed、archived 三个内层 schema 5 ZIP，外层 bundle schema 1。恢复后断言三者状态和置顶完全保留，恢复事务仍是全成或全回滚。v4 内层仍恢复为 active/unpinned。

Run: `flutter test test/workflow/project_bundle_service_test.dart`
Expected: FAIL。

- [ ] **Step 2: 保持状态穿过 bundle 编排**

不修改外层 manifest。`ProjectBundleService.restorePrepared` 继续返回 `List<ProjectImportResult>`，但所有结果必须带最终 lifecycle/pin；恢复 ownership 清理前后不得重写这两个字段；回滚继续按 operationId 删除完整项目。

- [ ] **Step 3: 写恢复 UI 和备份选择失败测试**

恢复完成对话框显示“进行中 1、已完成 1、已归档 1”。存在 archived 时显示 `view-archived-projects`；点击后关闭恢复流程并让首页切换到 archived。备份选择页列出所有状态项目并显示小型状态标签，默认选中逻辑和全选/取消全选不变。

Run: `flutter test test/features/settings/sections/backup_restore_section_screen_test.dart test/features/settings/sections/project_backup_selection_screen_test.dart`
Expected: FAIL。

- [ ] **Step 4: 实现恢复结果与首页筛选参数**

为 `ProjectListScreen` 增加 nullable `ProjectLifecycleStatus? initialStatus`，路由根页面从 `state.extra is ProjectLifecycleStatus` 读取。`initState` 采用传入状态，`didUpdateWidget` 在值变化时更新筛选。恢复成功后统计结果：

```dart
final activeCount = results.where((r) =>
  r.lifecycleStatus == ProjectLifecycleStatus.active).length;
final completedCount = results.where((r) =>
  r.lifecycleStatus == ProjectLifecycleStatus.completed).length;
final archivedCount = results.where((r) =>
  r.lifecycleStatus == ProjectLifecycleStatus.archived).length;
```

若 archivedCount > 0，对话框提供“查看归档项目”，使用 `context.go('/', extra: ProjectLifecycleStatus.archived)`。单个非归档恢复仍可进入项目详情；所有恢复路径都必须给出明确完成反馈。

- [ ] **Step 5: 验证恢复、返回与多选**

```powershell
dart format lib/workflow/project_bundle_service.dart lib/features/projects/project_restore_flow.dart lib/features/settings/sections/project_backup_selection_screen.dart lib/features/projects/project_list_screen.dart lib/app.dart lib/l10n/app_strings.dart test/workflow/project_bundle_service_test.dart test/features/settings/sections/backup_restore_section_screen_test.dart test/features/settings/sections/project_backup_selection_screen_test.dart
flutter test test/workflow/project_bundle_service_test.dart test/features/settings/sections/backup_restore_section_screen_test.dart test/features/settings/sections/project_backup_selection_screen_test.dart test/features/projects/project_list_screen_test.dart
```

Expected: PASS；全选可再次取消，返回不跳过页面。

- [ ] **Step 6: 提交**

```powershell
git add lib/workflow/project_bundle_service.dart lib/features/projects/project_restore_flow.dart lib/features/settings/sections/project_backup_selection_screen.dart lib/features/projects/project_list_screen.dart lib/app.dart lib/l10n/app_strings.dart test/workflow/project_bundle_service_test.dart test/features/settings/sections/backup_restore_section_screen_test.dart test/features/settings/sections/project_backup_selection_screen_test.dart test/features/projects/project_list_screen_test.dart
git commit -m "feat: surface lifecycle after project restore"
```

---

### Task 8: 版本、当前文档与全量门禁

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/features/settings/sections/about_section_screen.dart`
- Modify: `test/features/settings/sections/about_section_screen_test.dart`
- Modify: `README.md`
- Modify: `docs/current-product-architecture.md`
- Modify: `docs/capture-processing-storage.md`
- Modify: `docs/decision-records.md`
- Modify: `docs/record-watermark-settings.md` only if its project behavior text needs lifecycle clarification

**Interfaces:**
- Produces: candidate version `0.10.0+14`
- Produces: current documentation matching schema 11 and backup schema 5

- [ ] **Step 1: 更新版本测试和版本号**

把 `pubspec.yaml` 改为：

```yaml
version: 0.10.0+14
```

关于页 fallback 改为 `(version: '0.10.0', buildNumber: '14')`，测试断言版本与构建号。README 不得把候选版本写成已经发布；下载链接继续指向实际已发布版本，直到单独发布流程更新。

- [ ] **Step 2: 更新当前文档**

README 增加生命周期、置顶、状态筛选、备份保留状态说明。架构文档把 Drift 改为 schema 11、单项目备份改为 schema 5。`decision-records.md` 新增一条决策：生命周期由数据库强制、归档默认隐藏、备份保留精确状态。拍摄存储文档说明非 active 项目在 `createPendingCapture` 前被拒绝。

- [ ] **Step 3: 运行生成、格式和静态检查**

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter_rust_bridge_codegen generate
dart format --set-exit-if-changed lib test
cargo fmt --manifest-path rust/Cargo.toml --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
flutter analyze
git diff --check
```

Expected: 全部退出码 0；二次生成不再产生 diff。

- [ ] **Step 4: 运行全量自动化与构建**

```powershell
flutter test --reporter compact
cargo test --manifest-path rust/Cargo.toml
.\android\gradlew.bat -p android :sitemark_system_api:testDebugUnitTest
flutter build apk --debug
python -m unittest tool.test_generate_launcher_icon tool.test_verify_launcher_icon_resources tool.test_verify_release_tag tool.test_release_workflow
```

Expected: Flutter、Rust、Android、Python 全部通过，debug APK 构建成功。

- [ ] **Step 5: 进行定向人工代码审查**

检查以下不变量：

- 搜索跨状态，但退出后恢复原筛选；
- completed/archived 的拍摄按钮隐藏，深层路由也无法插入待拍记录；
- 状态转换提交前重新检查 processing/failed；
- restore-owned 项目不出现在汇总和计数；
- v1-v4 默认 active/unpinned，v5 精确保留，外层 schema 仍为 1；
- 无项目配置复制入口；
- 360dp、大字体、英文和 `disableAnimations` 无溢出或额外动画。

- [ ] **Step 6: 提交最终收口**

```powershell
git add pubspec.yaml lib/features/settings/sections/about_section_screen.dart test/features/settings/sections/about_section_screen_test.dart README.md docs/current-product-architecture.md docs/capture-processing-storage.md docs/decision-records.md docs/record-watermark-settings.md
git commit -m "docs: prepare project lifecycle candidate"
git status --short --branch
```

Expected: 工作区干净，分支只包含设计提交和 8 个实施阶段的相关提交；不要 push、merge、tag 或 release。
