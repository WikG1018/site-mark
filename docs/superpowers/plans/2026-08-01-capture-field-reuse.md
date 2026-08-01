# SiteMark v0.9 拍摄字段建议与命名模板实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保持“进程恢复草稿 > 上一张记录 > 空表单”和拍后清空备注规则不变的前提下，为每个项目提供最近字段建议与可备份恢复的命名模板。

**Architecture:** 数据库 schema 10 新增项目级 `capture_templates` 表；`CaptureTemplateService` 统一模板校验和 CRUD，`AppDatabase` 从现有记录按字段查询最近建议。拍摄页只负责控制器快照、弹层和撤销。项目归档 schema v4 由 Rust 严格校验模板，再由 Flutter 将其写入带恢复所有权的项目，因此继续沿用现有暂存、提交和回滚边界。

**Tech Stack:** Flutter 3.44.6、Dart、Drift 2.34、SQLite、Riverpod、GoRouter、Rust、flutter_rust_bridge、serde、zip、flutter_test、cargo test。

## Global Constraints

- 本计划必须从“记录搜索与分页”PR 合并后的最新 `main` 新建分支，起始数据库 schema 必须为 9。
- 表单初始化优先级保持：KILL 草稿 > 最近一次已拍摄记录的三个字段 > 空值。
- 连拍完成后只清空备注；建议和模板永不保存、覆盖或恢复备注。
- 最近建议只来自当前项目现存记录，排除 `pendingCamera`，但允许水印处理失败的已拍摄记录。
- 模板名称在项目内按去首尾空白、合并连续空白、ASCII 英文忽略大小写后唯一；每项目最多 100 个。
- 所有模板写操作使用事务，项目删除依靠外键级联；项目重命名不得改模板。
- 归档写出 schema v4，读取兼容 v1-v4；任一模板无效则整个项目恢复失败，不做部分恢复。
- 系统返回先关闭模板或建议弹层；`MediaQuery.disableAnimations` 为 true 时跳过新增动画。
- 不实现跨项目共享、云同步、自动套用、备注模板、定位推荐、单独历史词库或 Android 自动备份修改。

---

## 文件结构

- `lib/domain/capture_template_rules.dart`：模板名称规范化、字段限制和建议字段枚举。
- `lib/data/app_database.dart`：schema 10、模板表、CRUD、恢复插入和最近建议 SQL。
- `lib/data/app_database.g.dart`：Drift 生成文件。
- `lib/workflow/capture_template_service.dart`：业务校验、错误类型、模板增删改。
- `lib/features/capture/capture_recent_suggestions.dart`：焦点建议和“更多”历史弹层。
- `lib/features/capture/capture_template_sheet.dart`：模板列表、应用、保存、重命名、删除。
- `lib/features/capture/capture_form_screen.dart`：接入建议、模板、撤销和返回逻辑。
- `lib/l10n/app_strings.dart`：中英文文案。
- `rust/src/api/image_core.rs`：归档 schema v4 类型、写出、读取和验证。
- `rust/src/frb_generated.rs`、`lib/src/rust/**`：桥接生成文件。
- `lib/workflow/project_export_service.dart`：数据库模板映射为 Rust 导出请求。
- `lib/workflow/project_import_service.dart`：把已校验模板写入恢复所有权项目。
- `test/data/capture_template_database_test.dart`：迁移、CRUD、建议查询测试。
- `test/workflow/capture_template_service_test.dart`：模板规则测试。
- `test/features/capture/capture_field_reuse_test.dart`：表单、弹层、撤销、返回和无障碍测试。
- `test/workflow/project_export_test.dart`、`test/workflow/project_import_test.dart`、`rust/tests/core_test.rs`：归档 v4 契约测试。

---

### Task 1: 领域规则、schema 10 与模板表

**Files:**
- Create: `lib/domain/capture_template_rules.dart`
- Modify: `lib/data/app_database.dart`
- Regenerate: `lib/data/app_database.g.dart`
- Create: `test/domain/capture_template_rules_test.dart`
- Create: `test/data/capture_template_database_test.dart`

**Interfaces:**
- Consumes: schema 9 数据库和现有 `Projects` 外键。
- Produces: schema 10、`CaptureTemplate` 数据类和三层可共用的限制常量。

- [ ] **Step 1: 先写模板名称规范化失败测试**

```dart
expect(normalizeCaptureTemplateName('  日常   巡检  '), '日常 巡检');
expect(captureTemplateNameKey('  AbC  '), 'abc');
expect(captureTemplateNameKey('模板A'), '模板a');
```

明确 `captureTemplateNameKey` 只折叠 ASCII `A-Z`，不对中文或其他 Unicode 做不可控大小写转换。

Run: `flutter test test/domain/capture_template_rules_test.dart`

Expected: FAIL，函数尚不存在。

- [ ] **Step 2: 实现领域常量和值对象**

```dart
const captureTemplateNameMaxLength = 80;
const captureTemplateLocationMaxLength = 160;
const captureTemplateContentMaxLength = 240;
const captureTemplatePhotographerMaxLength = 80;
const captureTemplateLimitPerProject = 100;

enum CaptureSuggestionField { workLocation, workContent, photographer }

String normalizeCaptureTemplateName(String value);
String captureTemplateNameKey(String value);
```

名称规范化使用 `trim()` 后将连续 Unicode 空白折叠为一个普通空格；唯一键再把 ASCII 大写转小写。三个模板内容字段只 `trim()`，不得折叠用户正文内部空格。

- [ ] **Step 3: 先写 schema 9→10 和全新建库失败测试**

测试必须断言：

- 旧项目与记录完整保留；
- `capture_templates` 的 `id`、`project_id`、`name`、内部 `name_key`、三个内容字段和两个时间字段存在；
- `project_id` 删除级联；
- `(project_id, name_key)` 唯一；
- `(project_id, updated_at DESC, name)` 排序索引存在。

- [ ] **Step 4: 增加 Drift 表和迁移**

```dart
@DataClassName('CaptureTemplate')
class CaptureTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get nameKey => text().withLength(min: 1, max: 80)();
  TextColumn get workLocation => text().withLength(min: 1, max: 160)();
  TextColumn get workContent => text().withLength(min: 1, max: 240)();
  TextColumn get photographer => text().withLength(min: 1, max: 80)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {projectId, nameKey},
  ];
}
```

把表加入 `@DriftDatabase`，将 `schemaVersion` 改为 10；`from < 10` 创建表和排序索引。`beforeOpen` 继续启用外键。

- [ ] **Step 5: 重新生成并运行定向测试**

Run: `dart run build_runner build --delete-conflicting-outputs`

Run: `dart format lib/domain/capture_template_rules.dart lib/data/app_database.dart test/domain/capture_template_rules_test.dart test/data/capture_template_database_test.dart && flutter test test/domain/capture_template_rules_test.dart test/data/capture_template_database_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交基础数据结构**

```bash
git add lib/domain/capture_template_rules.dart lib/data/app_database.dart lib/data/app_database.g.dart test/domain/capture_template_rules_test.dart test/data/capture_template_database_test.dart
git commit -m "feat: add project capture templates schema"
```

---

### Task 2: 模板 CRUD 与最近字段建议查询

**Files:**
- Modify: `lib/data/app_database.dart`
- Create: `lib/workflow/capture_template_service.dart`
- Modify: `test/data/capture_template_database_test.dart`
- Create: `test/workflow/capture_template_service_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `CaptureTemplates` 和规则常量。
- Produces: UI 与备份恢复只需调用的稳定数据库/服务接口。

- [ ] **Step 1: 先写 CRUD 失败测试**

覆盖：项目内规范化重名拒绝、不同项目可同名、100 个上限、更新时间排序、重命名、删除、项目删除级联和项目重命名不影响模板。

- [ ] **Step 2: 定义数据库接口**

```dart
Stream<List<CaptureTemplate>> watchCaptureTemplates(String projectId);
Future<List<CaptureTemplate>> captureTemplatesForProject(String projectId);
Future<int> countCaptureTemplates(String projectId);
Future<CaptureTemplate> insertCaptureTemplate(CaptureTemplatesCompanion row);
Future<CaptureTemplate> renameCaptureTemplate({
  required String id,
  required String projectId,
  required String name,
  required String nameKey,
  required DateTime updatedAt,
});
Future<int> deleteCaptureTemplate({required String id, required String projectId});
Future<void> insertRestoredCaptureTemplates({
  required String projectId,
  required String restoreOperationId,
  required List<CaptureTemplatesCompanion> templates,
});
```

`insertRestoredCaptureTemplates` 必须先确认项目的 `restore_operation_id` 匹配，再在同一事务批量写入；所有删除和修改都同时约束 `id` 与 `projectId`。

- [ ] **Step 3: 实现业务服务和明确错误码**

```dart
enum CaptureTemplateFailure {
  emptyName,
  nameTooLong,
  emptyWorkLocation,
  workLocationTooLong,
  emptyWorkContent,
  workContentTooLong,
  emptyPhotographer,
  photographerTooLong,
  duplicateName,
  projectLimitReached,
  notFound,
}

class CaptureTemplateException implements Exception {
  const CaptureTemplateException(this.failure);
  final CaptureTemplateFailure failure;
}

class CaptureTemplateService {
  Stream<List<CaptureTemplate>> watch(String projectId);
  Future<CaptureTemplate> create({
    required String projectId,
    required String name,
    required String workLocation,
    required String workContent,
    required String photographer,
  });
  Future<CaptureTemplate> rename({
    required String projectId,
    required String templateId,
    required String name,
  });
  Future<void> delete({
    required String projectId,
    required String templateId,
  });
}
```

服务在事务中检查数量和规范化名称；SQLite 唯一约束竞争失败要映射为 `duplicateName`，不得向 UI 泄露数据库错误文字。

- [ ] **Step 4: 先写最近建议失败测试**

插入多个项目、重复大小写/首尾空白、`pendingCamera`、`ready`、`failed` 和已删除记录，断言：

- 只返回指定项目和指定字段；
- 排除 `pendingCamera`；
- `failed` 已拍摄记录可以进入建议；
- 按 `COALESCE(captured_at, created_at) DESC, id DESC` 取最新显示文本；
- ASCII 大小写不敏感，中文按原文；
- 默认 20 条且没有空值。

- [ ] **Step 5: 实现建议查询**

```dart
Future<List<String>> recentCaptureSuggestions({
  required String projectId,
  required CaptureSuggestionField field,
  int limit = 20,
});
```

字段名只能由枚举映射到固定列，不能拼接用户输入。SQL 用窗口函数或分组后连接取每个规范化值的最新原文；`limit` 在 1..20 内校验。若目标 Android SQLite 对窗口函数的现有最低版本测试不稳定，则在最多 200 条候选行内按时间读取后由 Dart 去重，但对 UI 最多返回 20 条，且测试锁定行为。

- [ ] **Step 6: 运行测试并提交**

Run: `dart format lib/data/app_database.dart lib/workflow/capture_template_service.dart test/data/capture_template_database_test.dart test/workflow/capture_template_service_test.dart && flutter test test/data/capture_template_database_test.dart test/workflow/capture_template_service_test.dart`

```bash
git add lib/data/app_database.dart lib/data/app_database.g.dart lib/workflow/capture_template_service.dart test/data/capture_template_database_test.dart test/workflow/capture_template_service_test.dart
git commit -m "feat: query recent capture fields and manage templates"
```

---

### Task 3: 最近建议组件与拍摄表单接入

**Files:**
- Create: `lib/features/capture/capture_recent_suggestions.dart`
- Modify: `lib/features/capture/capture_form_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Create: `test/features/capture/capture_field_reuse_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `recentCaptureSuggestions`。
- Produces: 每个必填输入框的 3 条快捷建议和最多 20 条历史弹层。

- [ ] **Step 1: 先写建议交互失败测试**

测试必须覆盖：输入框聚焦后最多 3 个建议；点击只替换当前字段；“更多”显示最多 20 条并本地过滤；失败时保留输入且显示重试；切换项目不会沿用建议。

- [ ] **Step 2: 实现可复用建议组件**

```dart
class CaptureRecentSuggestions extends StatefulWidget {
  const CaptureRecentSuggestions({
    super.key,
    required this.projectId,
    required this.field,
    required this.controller,
    required this.focusNode,
    required this.load,
  });
}
```

只在字段获得焦点时加载，缓存当前项目/字段结果；前三条用紧凑 `ActionChip`，超过三条显示“更多”。本地过滤同样 trim 并对 ASCII 忽略大小写。建议加载错误不在表单顶部弹全局错误，只在建议区域显示重试。

- [ ] **Step 3: 把 `_RequiredField` 改为接受焦点与建议槽位**

为三个控制器各持有 `FocusNode`，在 `dispose` 释放。保持原有 Key：`work-location`、`work-content`、`photographer`，避免破坏已有测试和无障碍定位。

- [ ] **Step 4: 锁定初始化和连拍契约**

扩充 `test/widget_test.dart`：

- 有 KILL 草稿时仍覆盖最近记录；
- 没草稿时仍使用最近记录三个字段且备注为空；
- 点击建议只改变目标字段，备注不变；
- 拍摄 queued/delayed 后仍只清空备注；
- 相机 cancelled 不新增建议来源。

- [ ] **Step 5: 添加中英文文案并验证减少动画**

至少包含“最近使用”“更多”“搜索历史”“暂无历史”“加载失败”“重试”。当 `disableAnimations` 为 true，建议显隐时长为 `Duration.zero`。

- [ ] **Step 6: 运行测试并提交**

Run: `dart format lib/features/capture/capture_recent_suggestions.dart lib/features/capture/capture_form_screen.dart lib/l10n/app_strings.dart test/features/capture/capture_field_reuse_test.dart test/widget_test.dart && flutter test test/features/capture/capture_field_reuse_test.dart test/widget_test.dart`

```bash
git add lib/features/capture/capture_recent_suggestions.dart lib/features/capture/capture_form_screen.dart lib/l10n/app_strings.dart test/features/capture/capture_field_reuse_test.dart test/widget_test.dart
git commit -m "feat: suggest recent capture fields"
```

---

### Task 4: 模板弹层、应用撤销与返回语义

**Files:**
- Create: `lib/features/capture/capture_template_sheet.dart`
- Modify: `lib/features/capture/capture_form_screen.dart`
- Modify: `lib/app.dart`
- Modify: `lib/l10n/app_strings.dart`
- Modify: `test/features/capture/capture_field_reuse_test.dart`
- Create: `test/navigation/back_navigation_test.dart`

**Interfaces:**
- Consumes: `CaptureTemplateService.watch/create/rename/delete` 和表单三个控制器。
- Produces: 当前项目模板的完整管理、应用和一次撤销。

- [ ] **Step 1: 先写模板弹层失败测试**

覆盖：

- 表单顶部有紧凑“模板”入口；
- 列表按更新时间倒序；
- 点击模板替换三个必填字段，备注保持原值；
- SnackBar 撤销只恢复应用前的三个字段；
- 连续应用两个模板时，撤销只回到第二次应用前状态；
- 空值、超长、重名、100 个上限在弹层内显示且弹层不关闭；
- 重命名成功会更新排序；
- 删除必须确认，失败仍留在弹层；
- 返回键先关闭确认框，再关闭模板弹层，再由拍摄页处理离开。

- [ ] **Step 2: 定义不可包含备注的表单快照**

```dart
@immutable
class CaptureRequiredFieldsSnapshot {
  const CaptureRequiredFieldsSnapshot({
    required this.workLocation,
    required this.workContent,
    required this.photographer,
  });

  final String workLocation;
  final String workContent;
  final String photographer;
}
```

模板应用回调只接受此类型，从类型层面禁止备注进入模板或撤销快照。

- [ ] **Step 3: 实现模板弹层**

```dart
Future<CaptureRequiredFieldsSnapshot?> showCaptureTemplateSheet({
  required BuildContext context,
  required String projectId,
  required CaptureRequiredFieldsSnapshot current,
  required CaptureTemplateService service,
});
```

弹层使用 `showModalBottomSheet(useSafeArea: true, isScrollControlled: true)`；键盘出现时用 `viewInsets` 保证名称输入可见。加载错误显示重试；写失败保留用户已输入的名称和三个字段。删除对话框明确只删除模板，不影响照片或已填表单。

- [ ] **Step 4: 接入 Provider 和表单应用/撤销**

在 `lib/app.dart` 增加：

```dart
final captureTemplateServiceProvider = Provider<CaptureTemplateService>((ref) {
  return CaptureTemplateService(database: ref.watch(databaseProvider));
});
```

打开弹层前保存当前三个字段，选择结果后一次性更新控制器；立即显示可撤销 SnackBar。撤销前先确认页面仍 mounted 且 projectId 未变化。备注控制器不得出现在该路径。

- [ ] **Step 5: 加入返回与动画无障碍测试**

使用现有 PopScope/路由返回测试方式断言：弹层打开时系统返回只关闭弹层，拍摄页仍存在。`MediaQuery.disableAnimations=true` 时底部弹层内部 AnimatedSwitcher/AnimatedSize 时长为零，并保持可操作。

- [ ] **Step 6: 运行测试并提交**

Run: `dart format lib/features/capture/capture_template_sheet.dart lib/features/capture/capture_form_screen.dart lib/app.dart lib/l10n/app_strings.dart test/features/capture/capture_field_reuse_test.dart test/navigation/back_navigation_test.dart && flutter test test/features/capture/capture_field_reuse_test.dart test/navigation/back_navigation_test.dart test/widget_test.dart`

```bash
git add lib/features/capture/capture_template_sheet.dart lib/features/capture/capture_form_screen.dart lib/app.dart lib/l10n/app_strings.dart test/features/capture/capture_field_reuse_test.dart test/navigation/back_navigation_test.dart test/widget_test.dart
git commit -m "feat: apply and manage capture templates"
```

---

### Task 5: Rust 项目归档 schema v4 与桥接类型

**Files:**
- Modify: `rust/src/api/image_core.rs`
- Modify: `rust/tests/core_test.rs`
- Regenerate: `rust/src/frb_generated.rs`
- Regenerate: `lib/src/rust/api/image_core.dart`
- Regenerate: `lib/src/rust/frb_generated.dart`
- Regenerate: 其他由 `flutter_rust_bridge_codegen` 报告变化的 `lib/src/rust/**`

**Interfaces:**
- Consumes: 项目归档 schema v1-v3 和模板限制常量的同值 Rust 实现。
- Produces: v4 导出请求、manifest 和严格验证后的预览模板。

- [ ] **Step 1: 先写 Rust v4 往返失败测试**

增加带两个模板的项目归档，断言 manifest 为 schema 4，预览保留名称、三个字段和时间戳，但不依赖数据库 ID。

- [ ] **Step 2: 增加导出与预览类型**

```rust
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ExportCaptureTemplate {
    pub name: String,
    pub work_location: String,
    pub work_content: String,
    pub photographer: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Clone, Debug)]
pub struct ArchiveCaptureTemplate {
    pub name: String,
    pub work_location: String,
    pub work_content: String,
    pub photographer: String,
    pub created_at: String,
    pub updated_at: String,
}
```

给 `ExportProjectRequest`、`ExportManifest`、`ProjectManifestFile` 和 `ProjectArchivePreview` 添加模板数组。读取结构上的数组使用 `#[serde(default)]`，使 v1-v3 自然得到空列表；写出版本改为 4。

- [ ] **Step 3: 先写恶意/损坏模板失败测试**

逐项覆盖：101 个模板、空名称、空三个字段、四类长度超限、规范化重名、无效时间戳、schema 99。断言 `inspect_project_archive` 整体失败，不返回部分照片预览。

- [ ] **Step 4: 实现 Rust 规范化和验证**

```rust
const MAX_CAPTURE_TEMPLATES_PER_PROJECT: usize = 100;
const MAX_TEMPLATE_NAME_CHARS: usize = 80;
const MAX_WORK_LOCATION_CHARS: usize = 160;
const MAX_WORK_CONTENT_CHARS: usize = 240;
const MAX_PHOTOGRAPHER_CHARS: usize = 80;

fn normalized_template_name(value: &str) -> String;
fn template_name_key(value: &str) -> String;
fn validate_archive_templates(templates: &[ManifestCaptureTemplate]) -> Result<(), String>;
```

长度统一按 Unicode scalar 计数：Dart 使用 `value.runes.length`，Rust 使用 `value.chars().count()`；名称键仅把 ASCII 大写转小写，必须与 Dart 测试用例一致。时间戳复用照片/项目现有严格解析器，不允许用“当前时间”替代坏值。

- [ ] **Step 5: 锁定 v1-v3 兼容**

现有 v1、v2、v3 fixtures 全部继续可读取，并断言 `preview.templates.is_empty()`；v3 空项目继续合法。不要改多项目 bundle 的外层 schema。

- [ ] **Step 6: 生成桥接代码并验证 Rust**

Run: `flutter_rust_bridge_codegen generate`

Run: `cargo fmt --manifest-path rust/Cargo.toml --check && cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings && cargo test --manifest-path rust/Cargo.toml`

Expected: 全部通过，生成的 Dart 构造器显式要求/提供 `templates`。

- [ ] **Step 7: 提交 Rust 契约**

```bash
git add rust/src/api/image_core.rs rust/src/frb_generated.rs rust/tests/core_test.rs lib/src/rust
git commit -m "feat: include capture templates in archive v4"
```

---

### Task 6: Flutter 导出、恢复事务与回滚

**Files:**
- Modify: `lib/workflow/project_export_service.dart`
- Modify: `lib/workflow/project_import_service.dart`
- Modify: `test/workflow/project_export_test.dart`
- Modify: `test/workflow/project_import_test.dart`
- Modify: `test/workflow/project_bundle_service_test.dart`

**Interfaces:**
- Consumes: Task 2 数据库 API 和 Task 5 Rust v4 桥接类型。
- Produces: 单项目与多项目备份中模板完整往返，并保持恢复原子性。

- [ ] **Step 1: 先写导出映射失败测试**

创建包含模板但没有照片的项目，调用 `ProjectExportService.exportProject`，断言 Rust 请求包含模板、归档成功且 v4 可检查。再覆盖有照片项目和多项目 bundle。

- [ ] **Step 2: 导出时读取并映射模板**

`exportProject` 在构造 `ExportProjectRequest` 前调用 `captureTemplatesForProject(projectId)`，映射为 `rust.ExportCaptureTemplate`。时间使用项目归档现有 UTC/offset 格式化函数，不另造格式。模板读取失败应让该项目备份失败，并由现有备份预检/诊断层展示具体项目，不静默跳过。

- [ ] **Step 3: 先写恢复原子性失败测试**

覆盖：

- v4 恢复为新模板 ID；
- v1-v3 模板为空；
- 模板插入失败后恢复项目、记录、文件和模板全部回滚；
- 中断清理删除 restore-owned 项目时模板随外键级联；
- 提交标记写入后重启收尾不会重复插入模板；
- 新项目因模板损坏不得残留。

- [ ] **Step 4: 在恢复所有权窗口内插入模板**

在 `_importProject` 创建带 `restoreOperationId` 的项目后、清除恢复所有权前，调用 `insertRestoredCaptureTemplates`。为每个模板生成新 UUID，并把 Rust 已验证字符串再经 Dart 同值规则校验；任何不一致视为 `InvalidArchiveException`，立即进入现有 `_rollback`。

模板不单独写 pending 文件；项目的 restore ownership 是唯一提交边界。恢复完成后才清除 ownership。不要把模板写入相册，也不要改变文件移动顺序。

- [ ] **Step 5: 更新测试假对象和构造器**

所有直接构造 `ExportProjectRequest` / `ProjectArchivePreview` 的测试必须显式传 `templates`；旧版本 fixture 使用空列表。禁止用可空字段绕过编译错误。

- [ ] **Step 6: 运行工作流测试并提交**

Run: `dart format lib/workflow/project_export_service.dart lib/workflow/project_import_service.dart test/workflow/project_export_test.dart test/workflow/project_import_test.dart test/workflow/project_bundle_service_test.dart && flutter test test/workflow/project_export_test.dart test/workflow/project_import_test.dart test/workflow/project_bundle_service_test.dart`

```bash
git add lib/workflow/project_export_service.dart lib/workflow/project_import_service.dart test/workflow/project_export_test.dart test/workflow/project_import_test.dart test/workflow/project_bundle_service_test.dart
git commit -m "feat: back up and restore capture templates"
```

---

### Task 7: 跨层契约、边界和回归测试

**Files:**
- Modify: `test/data/capture_template_database_test.dart`
- Modify: `test/workflow/capture_template_service_test.dart`
- Modify: `test/features/capture/capture_field_reuse_test.dart`
- Modify: `test/workflow/project_export_test.dart`
- Modify: `test/workflow/project_import_test.dart`
- Modify: `rust/tests/core_test.rs`
- Create: `test/l10n/app_strings_test.dart`

**Interfaces:**
- Consumes: Tasks 1–6 全部功能。
- Produces: Dart、SQLite、Rust 三层一致的边界契约和 UI 回归证据。

- [ ] **Step 1: 建立固定跨层用例表**

至少使用以下名称和预期：

| 输入 | 规范显示名 | 唯一键 | 结果 |
|---|---|---|---|
| `  日常   巡检  ` | `日常 巡检` | `日常 巡检` | 接受 |
| `ABC` / `abc` | 各自显示 | `abc` | 同项目重名 |
| `模板A` / `模板a` | 各自显示 | `模板a` | 同项目重名 |
| 80 个 Unicode 字符 | 原文 | 同规则 | 接受 |
| 81 个 Unicode 字符 | 原文 | 同规则 | 拒绝 |

确保 Dart 和 Rust 都把连续空白折叠为一个普通空格，并在唯一键中保留这个空格。

- [ ] **Step 2: 验证建议来源状态矩阵**

对每个 `CaptureStatus` 建 fixture，明确 `pendingCamera` 排除；只要记录已经进入 captured/rendering/ready/failed 等已拍摄阶段就允许进入建议。测试必须读取当前枚举全部值，新增状态时迫使维护者更新预期。

- [ ] **Step 3: 验证表单草稿和备注不回归**

在中文、英文、减少动画三种环境分别执行：草稿恢复、最近记录预填、建议应用、模板应用、撤销、连续拍摄。每一步都断言备注值。

- [ ] **Step 4: 验证归档兼容矩阵**

Rust 与 Flutter 测试共同覆盖 v1、v2、v3、v4；单项目有/无照片、有/无模板；多项目 bundle 中项目模板互不串联。损坏模板必须在 `inspect` 阶段拒绝。

- [ ] **Step 5: 运行定向跨层回归并提交**

Run: `flutter test test/domain/capture_template_rules_test.dart test/data/capture_template_database_test.dart test/workflow/capture_template_service_test.dart test/features/capture/capture_field_reuse_test.dart test/workflow/project_export_test.dart test/workflow/project_import_test.dart test/workflow/project_bundle_service_test.dart test/l10n/app_strings_test.dart`

Run: `cargo test --manifest-path rust/Cargo.toml`

```bash
git add test rust/tests/core_test.rs
git commit -m "test: lock capture template cross-layer contracts"
```

---

### Task 8: 版本、文档、全量验证和 PR 2 收口

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/l10n/app_strings.dart`
- Modify: `lib/features/settings/sections/about_section_screen.dart`
- Modify: `test/features/settings/sections/about_section_screen_test.dart`
- Modify: `README.md`
- Modify: `docs/current-product-architecture.md`
- Modify: `docs/record-watermark-settings.md`
- Modify: `docs/capture-processing-storage.md`
- Modify: `docs/decision-records.md`

**Interfaces:**
- Consumes: Tasks 1–7 完整功能和已经合并的记录搜索分页。
- Produces: v0.9.0 候选代码、同步文档和可独立审查的 PR 2。

- [ ] **Step 1: 更新候选版本，不伪造发布状态**

把 `pubspec.yaml` 从实施时 main 的版本升级为 `0.9.0+13`；同步关于页 fallback 和测试。README 可以写“当前开发版本 v0.9.0”，但 GitHub Release 区域仍链接实际最新已发布版本，不把候选包描述为已发布。

- [ ] **Step 2: 更新中文设计正文**

在现行架构、拍摄记录/水印设置、处理与存储、决策记录文档中写明：schema 10、最近建议来源、模板不含备注、项目级限制、归档 v4 和回滚所有权。不要写测试设备型号，也不要增加“完全本地”隐私承诺。

- [ ] **Step 3: 执行格式、静态检查和 Flutter 全量测试**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test`

Expected: 0 issues，全部 Flutter 测试通过。

- [ ] **Step 4: 执行 Rust、Android 与 APK 构建门禁**

Run: `cargo fmt --manifest-path rust/Cargo.toml --check && cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings && cargo test --manifest-path rust/Cargo.toml`

Run: `.\android\gradlew.bat -p android :sitemark_system_api:testDebugUnitTest`

Run: `flutter build apk --debug && flutter build apk --release`

Expected: 全部成功；release APK 的应用内版本显示为 0.9.0。

- [ ] **Step 5: 审计差异与禁止范围**

Run: `git diff --check && git status --short && git diff origin/main...HEAD --stat`

Run: `rg -n "notes" lib/features/capture/capture_template_sheet.dart lib/workflow/capture_template_service.dart rust/src/api/image_core.rs`

Expected: 模板类型、弹层和归档模板结构不含备注字段；无未提交生成文件；没有跨项目模板、云同步、Android 自动备份或定位推荐改动。

- [ ] **Step 6: 提交文档与版本**

```bash
git add pubspec.yaml lib/l10n/app_strings.dart lib/features/settings/sections/about_section_screen.dart test/features/settings/sections/about_section_screen_test.dart README.md docs
git commit -m "docs: describe v0.9 capture field reuse"
```

- [ ] **Step 7: 创建并审查 PR 2**

推送分支并创建 PR，正文列出：最近建议、命名模板、归档 v4、兼容 v1-v3、schema 9→10 迁移、测试结果和不在范围。等待 CI 全绿后逐文件审查生成代码范围、恢复事务边界、备注隔离和系统返回语义，再决定合并。

完成标准：两种复用方式都只能在当前项目工作；失败不会阻断手动拍摄；旧备份仍可恢复；新备份模板完整往返；所有验证通过且工作区干净。
