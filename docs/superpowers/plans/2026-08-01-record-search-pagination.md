# SiteMark v0.9 记录搜索与分页实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让项目记录和全部记录使用 SQLite 搜索、稳定游标分页和按需相邻照片加载，在 1 万条记录下不再一次物化全部数据。

**Architecture:** 以 `CaptureListQuery` 统一项目、日期和关键词语义；`CaptureQueryRepository` 负责绑定参数的 SQL、计数、日期选项、全选 ID 和相邻记录；`CapturePagerController` 负责异步版本、分页去重和新记录提示。两个记录页面只组合控制器和现有卡片/批量操作，不复制查询逻辑。

**Tech Stack:** Flutter 3.44.6、Dart、Drift 2.34、SQLite、Riverpod、GoRouter、Skeletonizer、flutter_test。

## Global Constraints

- Android 最低版本保持 API 31，不新增权限或网络依赖。
- 单页固定 50 条，距离末尾 8 条时预取。
- 排序固定为 `COALESCE(captured_at, created_at) DESC, id DESC`。
- 多关键词之间为 AND，每个关键词可命中项目名称、工程部位、工作内容、拍摄人、备注、照片编号或地址。
- `%`、`_`、`\` 必须按普通文字搜索；所有用户输入使用 SQL 绑定参数。
- 搜索等待 250 毫秒；过期异步结果不得覆盖新查询。
- 全选覆盖完整查询结果，详情和全屏不得依赖完整列表常驻内存。
- 保持现有后台处理状态自动刷新、Hero 标识、批量操作语义和减少动画支持。
- 不实现 FTS、中文分词、云端搜索或 Android 自动备份修改。

---

## 文件结构

- `lib/domain/capture_list_query.dart`：查询规范化、关键词、游标和日期选项纯类型。
- `lib/data/capture_query_repository.dart`：SQLite 查询、分页、计数、全选、日期选项、状态监听和相邻记录。
- `lib/features/capture/capture_pager_controller.dart`：分页状态机、异步版本、去重、新记录提示。
- `lib/features/capture/capture_search_field.dart`：两个记录页面共用的搜索标题栏。
- `lib/features/capture/capture_paged_list.dart`：骨架、首屏错误、下一页进度/重试和新记录提示。
- `lib/features/capture/capture_fullscreen_sequence.dart`：全屏照片前后页按需加载。
- 修改 `AppDatabase` 仅负责 schema 9、游标索引和按 ID 监听；复杂搜索留在 repository。

### Task 1: 查询值对象与规范化契约

**Files:**
- Create: `lib/domain/capture_list_query.dart`
- Create: `test/domain/capture_list_query_test.dart`

**Interfaces:**
- Consumes: `CaptureFilter` from `lib/domain/capture_filter.dart`。
- Produces: `CaptureListQuery`、`CapturePageCursor`、`CaptureDateOptions`、`normalizeCaptureSearchTerms(String)`。

- [ ] **Step 1: 写失败测试**

```dart
test('normalizes whitespace and keeps literal wildcard characters', () {
  expect(normalizeCaptureSearchTerms('  21栋   巡检  '), ['21栋', '巡检']);
  expect(normalizeCaptureSearchTerms(r'100% A_B\C'), [r'100%', r'A_B\C']);
});

test('query equality includes filter and normalized text', () {
  const a = CaptureListQuery(
    filter: CaptureFilter(projectId: 'p1', year: 2026),
    searchText: '  风管 ',
  );
  const b = CaptureListQuery(
    filter: CaptureFilter(projectId: 'p1', year: 2026),
    searchText: '风管',
  );
  expect(a.normalizedTerms, b.normalizedTerms);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/domain/capture_list_query_test.dart`

Expected: FAIL，提示 `CaptureListQuery` 尚不存在。

- [ ] **Step 3: 实现纯类型**

```dart
typedef CapturePageCursor = ({DateTime sortTime, String id});

final class CaptureDateOptions {
  const CaptureDateOptions({
    this.years = const [],
    this.months = const [],
    this.days = const [],
  });
  final List<int> years;
  final List<int> months;
  final List<int> days;
}

final class CaptureListQuery {
  const CaptureListQuery({
    this.filter = const CaptureFilter(),
    this.searchText = '',
  });
  final CaptureFilter filter;
  final String searchText;
  List<String> get normalizedTerms => normalizeCaptureSearchTerms(searchText);
  CaptureListQuery copyWith({CaptureFilter? filter, String? searchText}) =>
      CaptureListQuery(
        filter: filter ?? this.filter,
        searchText: searchText ?? this.searchText,
      );
}

List<String> normalizeCaptureSearchTerms(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .where((term) => term.isNotEmpty)
    .toList(growable: false);
```

- [ ] **Step 4: 运行测试并格式化**

Run: `dart format lib/domain/capture_list_query.dart test/domain/capture_list_query_test.dart && flutter test test/domain/capture_list_query_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/domain/capture_list_query.dart test/domain/capture_list_query_test.dart
git commit -m "feat: define capture list query contract"
```

### Task 2: schema 9 与稳定游标索引

**Files:**
- Modify: `lib/data/app_database.dart`
- Regenerate: `lib/data/app_database.g.dart`
- Modify: `test/data/app_database_migration_test.dart`
- Modify: `test/data/app_database_test.dart`

**Interfaces:**
- Consumes: schema 8 `captures` 表。
- Produces: schema 9、`capture_records_sort_cursor_idx`、`capture_records_project_sort_cursor_idx`、`watchCaptureSummariesByIds(Set<String>)`。

- [ ] **Step 1: 添加迁移失败测试**

```dart
test('v8 to v9 creates stable cursor indexes', () async {
  final db = await openV8AndUpgrade();
  final indexes = await indexSql(db, 'capture_records_%_cursor_idx');
  expect(indexes.keys, containsAll({
    'capture_records_sort_cursor_idx',
    'capture_records_project_sort_cursor_idx',
  }));
  expect(
    normalizedSql(indexes['capture_records_sort_cursor_idx']!),
    contains('coalesce(captured_at, created_at) desc, id desc'),
  );
});
```

同时添加按 ID 监听测试：更新一个 `rendering` 记录为 `ready` 后，`watchCaptureSummariesByIds({'id'})` 必须发出新状态。

- [ ] **Step 2: 运行目标测试确认失败**

Run: `flutter test test/data/app_database_migration_test.dart test/data/app_database_test.dart`

Expected: FAIL，schema 仍为 8，索引和监听接口不存在。

- [ ] **Step 3: 实现迁移和监听**

```dart
@override
int get schemaVersion => 9;

if (from < 9) {
  await _createCaptureCursorIndexes();
}

Future<void> _createCaptureCursorIndexes() async {
  await customStatement(
    'CREATE INDEX IF NOT EXISTS capture_records_sort_cursor_idx '
    'ON captures (COALESCE(captured_at, created_at) DESC, id DESC)',
  );
  await customStatement(
    'CREATE INDEX IF NOT EXISTS capture_records_project_sort_cursor_idx '
    'ON captures (project_id, COALESCE(captured_at, created_at) DESC, id DESC)',
  );
}

Stream<List<CaptureSummary>> watchCaptureSummariesByIds(Set<String> ids) {
  if (ids.isEmpty) return Stream.value(const []);
  final query = _captureSummarySelectable(null)
    ..where(captureRecords.id.isIn(ids));
  return query.watch();
}
```

`onCreate` 同时调用 `_createCaptureCursorIndexes()`；不要删除 v6 旧索引，避免迁移路径分叉。

- [ ] **Step 4: 重新生成并运行测试**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter test test/data/app_database_migration_test.dart test/data/app_database_test.dart`

Expected: PASS，生成文件只有预期 schema 变化。

- [ ] **Step 5: 提交**

```bash
git add lib/data/app_database.dart lib/data/app_database.g.dart test/data/app_database_migration_test.dart test/data/app_database_test.dart
git commit -m "feat: add stable capture cursor indexes"
```

### Task 3: SQLite 查询仓库

**Files:**
- Create: `lib/data/capture_query_repository.dart`
- Create: `test/data/capture_query_repository_test.dart`
- Modify: `lib/app.dart`

**Interfaces:**
- Consumes: `AppDatabase`、`CaptureListQuery`、`CapturePageCursor`。
- Produces:
  - `CapturePage(rows, nextCursor, hasMore)`
  - `CaptureSelectionSnapshot(ids, allReady)`
  - `Future<CapturePage> loadPage(CaptureListQuery, {CapturePageCursor? after, int limit = 50})`
  - `Future<int> count(CaptureListQuery)`
  - `Future<CaptureDateOptions> loadDateOptions(CaptureListQuery)`
  - `Future<CaptureSelectionSnapshot> loadSelectable(CaptureListQuery)`
  - `Future<CaptureSelectionSnapshot> inspectSelection(Set<String>)`
  - `Future<List<CaptureSummary>> loadAdjacent(CaptureListQuery, CapturePageCursor, {required bool newer, int limit = 10})`
  - `Stream<CapturePageCursor?> watchNewestCursor(CaptureListQuery)`
  - `Stream<List<CaptureSummary>> watchByIds(Set<String>)`

- [ ] **Step 1: 写查询契约失败测试**

建立包含 1 万条记录的内存数据库夹具，至少验证：

```dart
final first = await repository.loadPage(
  const CaptureListQuery(searchText: r'21栋 100%'),
);
expect(first.rows, hasLength(50));
expect(first.rows.every((row) =>
  row.capture.workLocation.contains('21栋') &&
  row.capture.notes!.contains('100%')), isTrue);

final second = await repository.loadPage(
  query,
  after: first.nextCursor,
);
expect(second.rows.map((e) => e.capture.id).toSet()
    .intersection(first.rows.map((e) => e.capture.id).toSet()), isEmpty);
```

增加 `%`、`_`、`\` 字面匹配、英文大小写、相同时间 ID 排序、日期组合、计数、全选和相邻记录断言。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/data/capture_query_repository_test.dart`

Expected: FAIL，repository 尚不存在。

- [ ] **Step 3: 实现绑定参数 SQL**

`loadPage` 使用 `limit + 1` 判断 `hasMore`。每个关键词生成一个括号，字段之间 OR、关键词之间 AND：

```sql
AND (
  lower(p.name) LIKE lower(?) ESCAPE '\'
  OR lower(c.work_location) LIKE lower(?) ESCAPE '\'
  OR lower(c.work_content) LIKE lower(?) ESCAPE '\'
  OR lower(c.photographer) LIKE lower(?) ESCAPE '\'
  OR lower(COALESCE(c.notes, '')) LIKE lower(?) ESCAPE '\'
  OR lower(COALESCE(c.photo_number, '')) LIKE lower(?) ESCAPE '\'
  OR lower(COALESCE(c.address, '')) LIKE lower(?) ESCAPE '\'
)
```

转义函数必须按顺序处理 `\`、`%`、`_`：

```dart
String escapeLikeLiteral(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');
```

游标条件为：

```sql
AND (
  COALESCE(c.captured_at, c.created_at) < ?
  OR (
    COALESCE(c.captured_at, c.created_at) = ?
    AND c.id < ?
  )
)
ORDER BY COALESCE(c.captured_at, c.created_at) DESC, c.id DESC
LIMIT ?
```

日期选项使用 `SELECT DISTINCT`，全选只选择 `ready`/`failed` 的 ID 并用聚合判断是否全部 `ready`。通过 `captureQueryRepositoryProvider` 暴露单例仓库。

- [ ] **Step 4: 运行仓库测试和查询计划断言**

Run: `flutter test test/data/capture_query_repository_test.dart`

Expected: PASS；无搜索、带/不带项目的 `EXPLAIN QUERY PLAN` 分别引用两个 cursor index。

- [ ] **Step 5: 提交**

```bash
git add lib/data/capture_query_repository.dart lib/app.dart test/data/capture_query_repository_test.dart
git commit -m "feat: query capture pages in SQLite"
```

### Task 4: 分页控制器与过期结果保护

**Files:**
- Create: `lib/features/capture/capture_pager_controller.dart`
- Create: `test/features/capture/capture_pager_controller_test.dart`

**Interfaces:**
- Consumes: `CaptureQuerySource`（Task 3 repository 实现的接口）。
- Produces: `CapturePagerState`、`CapturePagerController.setQuery`、`refresh`、`loadMore`、`setAtTop`、`acceptNewer`、`replaceWatchedRows`。

- [ ] **Step 1: 写状态机失败测试**

```dart
test('drops an older response after query changes', () async {
  final source = ControlledCaptureQuerySource();
  final controller = CapturePagerController(source);
  final old = controller.setQuery(const CaptureListQuery(searchText: '旧'));
  final fresh = controller.setQuery(const CaptureListQuery(searchText: '新'));
  source.complete('新', pageOf(['new']));
  await fresh;
  source.complete('旧', pageOf(['old']));
  await old;
  expect(controller.state.rows.single.capture.id, 'new');
});
```

再测试分页去重、下一页失败保留旧行、`hasNewer`、顶部自动刷新和 `dispose` 后不通知。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/features/capture/capture_pager_controller_test.dart`

Expected: FAIL，控制器尚不存在。

- [ ] **Step 3: 实现不可变状态与 generation**

```dart
final class CapturePagerState {
  const CapturePagerState({
    required this.query,
    this.rows = const [],
    this.initialLoading = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.hasNewer = false,
    this.totalCount,
    this.initialError,
    this.nextPageError,
  });
  final CaptureListQuery query;
  final List<CaptureSummary> rows;
  final bool initialLoading;
  final bool loadingMore;
  final bool hasMore;
  final bool hasNewer;
  final int? totalCount;
  final Object? initialError;
  final Object? nextPageError;
}
```

每次 `setQuery` 递增 `_generation`；所有 await 返回后先比较局部 generation。合并页面时以 `LinkedHashMap<String, CaptureSummary>` 去重并保持顺序。

- [ ] **Step 4: 运行测试**

Run: `dart format lib/features/capture/capture_pager_controller.dart test/features/capture/capture_pager_controller_test.dart && flutter test test/features/capture/capture_pager_controller_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/features/capture/capture_pager_controller.dart test/features/capture/capture_pager_controller_test.dart
git commit -m "feat: add stale-safe capture pager"
```

### Task 5: 搜索标题栏、日期选项和分页列表

**Files:**
- Create: `lib/features/capture/capture_search_field.dart`
- Create: `lib/features/capture/capture_paged_list.dart`
- Modify: `lib/features/capture/capture_date_filter_bar.dart`
- Modify: `lib/features/capture/capture_record_card.dart`
- Modify: `lib/features/capture/all_captures_screen.dart`
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Modify: `test/features/capture/capture_filter_ui_test.dart`
- Create: `test/features/capture/capture_search_paging_ui_test.dart`

**Interfaces:**
- Consumes: `CapturePagerController`、`CaptureDateOptions`。
- Produces: 两个页面一致的搜索、分页、错误、新记录和返回逻辑。

- [ ] **Step 1: 写界面失败测试**

覆盖以下完整流程：

```dart
await tester.tap(find.byKey(const Key('search-captures')));
await tester.enterText(find.byKey(const Key('capture-search-field')), '21栋');
await tester.pump(const Duration(milliseconds: 249));
expect(source.queries, isEmpty);
await tester.pump(const Duration(milliseconds: 1));
expect(source.queries.single.searchText, '21栋');

await tester.binding.handlePopRoute();
await tester.pumpAndSettle();
expect(find.byKey(const Key('capture-search-field')), findsNothing);
expect(find.byType(AllCapturesScreen), findsOneWidget);
```

再覆盖清空图标唯一、搜索命中说明、首屏错误、下一页重试、底部加载、新记录提示和减少动画。

- [ ] **Step 2: 运行界面测试确认失败**

Run: `flutter test test/features/capture/capture_search_paging_ui_test.dart test/features/capture/capture_filter_ui_test.dart`

Expected: FAIL，搜索和分页控件尚未接入。

- [ ] **Step 3: 接入两个页面**

`CaptureSearchField` 内部使用 250 毫秒 Timer，只有文本变化才提交；dispose 必须取消 Timer。`PopScope` 优先级固定为：编辑模式 → 搜索模式 → 页面返回。

`CaptureDateFilterBar` 改为直接消费 `CaptureDateOptions`，不再接收完整 `CaptureSummary`。`CapturePagedList` 根据 `CapturePagerState` 显示 Skeletonizer、内容、底部进度、重试和“有新记录”。

`CaptureRecordCard` 增加可空 `searchTerms`；仅在备注、地址或照片编号首次命中时显示一行本地化摘要，最多一行并省略溢出。

- [ ] **Step 4: 运行界面与现有导航测试**

Run: `flutter test test/features/capture/capture_search_paging_ui_test.dart test/features/capture/capture_filter_ui_test.dart test/widget_test.dart`

Expected: PASS，现有返回、编辑和筛选用例继续通过。

- [ ] **Step 5: 提交**

```bash
git add lib/features/capture lib/features/projects/project_detail_screen.dart lib/l10n/app_strings.dart test/features/capture test/widget_test.dart
git commit -m "feat: search and page capture records"
```

### Task 6: 分页全选与批量操作资格

**Files:**
- Modify: `lib/features/capture/capture_selection_controller.dart`
- Modify: `lib/features/capture/capture_batch_action_bar.dart`
- Modify: `lib/features/capture/all_captures_screen.dart`
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `test/features/capture/capture_selection_controller_test.dart`
- Create: `test/features/capture/capture_batch_paged_selection_test.dart`

**Interfaces:**
- Consumes: `CaptureSelectionSnapshot` from Task 3。
- Produces: `replaceAll(ids, {required bool allReady})`、`allSelectedReady`；批量栏不再依赖仅已加载的 `summaries`。

- [ ] **Step 1: 写失败测试**

```dart
controller.replaceAll(
  List.generate(120, (index) => 'id-$index'),
  allReady: false,
);
expect(controller.selectedIds, hasLength(120));
expect(controller.allSelectedReady, isFalse);
controller.toggleAllSnapshot(const CaptureSelectionSnapshot(ids: [], allReady: false));
expect(controller.selectedIds, isEmpty);
```

界面测试验证只加载 50 张卡片时可以选择 120 个查询结果，导出/再次保存因其中含 `failed` 而禁用，清理原图和删除仍可用。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/features/capture/capture_selection_controller_test.dart test/features/capture/capture_batch_paged_selection_test.dart`

Expected: FAIL，新接口不存在。

- [ ] **Step 3: 改为查询驱动的选择资格**

控制器保存 `_allSelectedReady`，任何单条 toggle 后由页面调用 `inspectSelection(selectedIds)` 刷新；异步资格检查同样使用 generation 防止旧结果。`CaptureBatchActionBar` 接收 `allSelectedReady`，删除 `summaries` 参数和同步 `_allReady` 映射。

点击全选时先显示短进度，调用 `loadSelectable(query)`，成功后一次更新控制器；失败保持原选择并显示重试提示。

- [ ] **Step 4: 运行批量操作测试**

Run: `flutter test test/features/capture/capture_selection_controller_test.dart test/features/capture/capture_batch_paged_selection_test.dart test/features/capture/motion_selection_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/features/capture lib/features/projects/project_detail_screen.dart test/features/capture
git commit -m "feat: select full paged capture results"
```

### Task 7: 详情与全屏相邻记录按需加载

**Files:**
- Create: `lib/features/capture/capture_fullscreen_sequence.dart`
- Modify: `lib/features/capture/capture_detail_screen.dart`
- Modify: `lib/features/capture/capture_image_preview.dart`
- Modify: `lib/features/capture/capture_fullscreen_screen.dart`
- Modify: `lib/features/capture/all_captures_screen.dart`
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `lib/app.dart`
- Create: `test/features/capture/capture_fullscreen_sequence_test.dart`
- Modify: `test/features/capture/capture_fullscreen_screen_test.dart`
- Modify: `test/features/capture/capture_image_preview_test.dart`

**Interfaces:**
- Consumes: `CaptureListQuery`、`CapturePageCursor`、`CaptureQuerySource.loadAdjacent`。
- Produces: `CaptureNavigationContext`、`CaptureFullscreenSequence.loadNewer/loadOlder`；删除 `siblingCaptures` 全列表参数。

- [ ] **Step 1: 写失败测试**

测试从当前照片进入时立即显示当前预览，到达最后一页后只请求 older；向前插入照片后保持当前照片 ID 和视觉页不变；重复返回的 ID 被去重；加载失败只显示边缘重试。

```dart
expect(sequence.photos.map((photo) => photo.id), ['current']);
await sequence.loadOlder();
expect(sequence.photos.map((photo) => photo.id), ['current', 'older-1']);
expect(sequence.currentId, 'current');
```

- [ ] **Step 2: 运行目标测试确认失败**

Run: `flutter test test/features/capture/capture_fullscreen_sequence_test.dart test/features/capture/capture_fullscreen_screen_test.dart test/features/capture/capture_image_preview_test.dart`

Expected: FAIL，sequence 和 navigation context 尚不存在。

- [ ] **Step 3: 实现动态序列**

```dart
final class CaptureNavigationContext {
  const CaptureNavigationContext({required this.query, required this.cursor});
  final CaptureListQuery query;
  final CapturePageCursor cursor;
}

enum CaptureFullscreenDirection { newer, older }

typedef CaptureFullscreenPageLoader =
    Future<List<CaptureFullscreenPhoto>> Function(
      CaptureFullscreenDirection direction,
      String anchorId,
    );
```

`CaptureDetailArguments` 改为携带 `CaptureNavigationContext?`。全屏序列初始只有当前照片，进入页面后预取前后各 10 条。向列表前方插入时，更新 PageController 索引以保持当前 ID；这次校正不播放额外动画。页面到达两端 2 张以内时继续预取。

- [ ] **Step 4: 运行 Hero、详情和全屏回归测试**

Run: `flutter test test/features/capture/capture_fullscreen_sequence_test.dart test/features/capture/capture_fullscreen_screen_test.dart test/features/capture/capture_image_preview_test.dart test/features/capture/capture_photo_hero_test.dart test/widget_test.dart`

Expected: PASS，进入和返回 Hero 仍使用 `capture-photo-{id}`。

- [ ] **Step 5: 提交**

```bash
git add lib/app.dart lib/features/capture lib/features/projects/project_detail_screen.dart test/features/capture test/widget_test.dart
git commit -m "feat: load adjacent fullscreen captures on demand"
```

### Task 8: 文档、全量验证和 PR 1 收口

**Files:**
- Modify: `docs/current-product-architecture.md`
- Modify: `docs/record-watermark-settings.md`
- Modify: `README.md`
- Modify: `test/features/settings/a11y_test.dart` when new semantics require coverage

**Interfaces:**
- Consumes: Tasks 1–7 完整功能。
- Produces: 可独立合并的记录搜索与分页 PR。

- [ ] **Step 1: 更新当前设计正文**

明确记录列表使用 SQLite 搜索、50 条游标分页、数据库日期选项、完整查询全选和按需相邻图片。README 只更新累计功能，不把尚未发布的版本写成已发布版本。

- [ ] **Step 2: 运行格式、静态检查和全量 Flutter 测试**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test`

Expected: 0 issues，全部 Flutter 测试通过。

- [ ] **Step 3: 运行 Rust、Android 与构建门禁**

Run: `cargo fmt --manifest-path rust/Cargo.toml --check && cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings && cargo test --manifest-path rust/Cargo.toml`

Run: `.\android\gradlew.bat -p android :sitemark_system_api:testDebugUnitTest`

Run: `flutter build apk --debug && flutter build apk --release`

Expected: 全部成功。

- [ ] **Step 4: 检查生成文件、差异与范围**

Run: `git diff --check && git status --short && git diff origin/main...HEAD --stat`

Expected: 无未跟踪生成物；不包含模板、备份 v4、权限或自动备份修改。

- [ ] **Step 5: 提交文档收口**

```bash
git add README.md docs/current-product-architecture.md docs/record-watermark-settings.md test/features/settings/a11y_test.dart
git commit -m "docs: describe paged capture search"
```

完成后创建 PR 1，等待 CI 通过并逐项审查；PR 1 合并后，字段复用计划从新的 `main` 分支开始。
