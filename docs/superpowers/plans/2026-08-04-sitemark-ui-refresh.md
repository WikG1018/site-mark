# SiteMark 界面重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变照片、备份和项目生命周期业务契约的前提下，完成悬浮一级导航、玻璃视觉系统以及项目、记录、拍摄、照片详情和设置页面重构。

**Architecture:** 使用 `StatefulShellRoute` 保留三个一级页面的状态，二级页面继续压入根导航器以隐藏 Dock。玻璃材质、日期分组、筛选面板和操作面板拆成独立小组件；现有 Riverpod、Drift、分页、后台处理和 Hero 数据链路保持不变。

**Tech Stack:** Flutter 3 / Material 3、Dart、Riverpod、go_router、Drift、Skeletonizer、flutter_test。

## Global Constraints

- 基线为 `main` / `0.10.0+14`，实现阶段不直接调整发布版本号。
- 不修改照片水印内容、文件命名、备份格式、恢复契约、生命周期状态或数据库 schema。
- 一级页面为“项目、全部记录、设置”；二级页面不显示 Dock。
- 项目首页继续支持进行中、已完成、已归档筛选，搜索仍覆盖全部生命周期。
- 全面玻璃化必须保留最低不透明度、边框与文字对比度；减少动画模式下关闭非必要动效和实时模糊。
- 系统返回键先关闭弹层或退出搜索、筛选、编辑、批量选择，再执行页面返回。
- Hero 仅用于照片查看链路，原图逻辑删除后不得回退读取原图。
- 中文、英文、360dp 窄屏、大字体和系统减少动画均属于验收范围。

---

## 文件结构

新增文件及职责：

- `lib/shared/ui/glass_surface.dart`：统一玻璃背景、边框、模糊降级和重绘边界。
- `lib/navigation/root_navigation_scaffold.dart`：一级 Dock、分支保活和项目页新建按钮。
- `lib/features/projects/project_summary_card.dart`：项目玻璃卡片及最近照片缩略图。
- `lib/features/projects/project_action_sheet.dart`：项目详情全部低频操作的文字面板。
- `lib/features/capture/capture_filter_sheet.dart`：项目、年、月、日筛选草稿与提交。
- `lib/features/capture/capture_active_filter_chips.dart`：当前筛选条件标签及单项清除。
- `lib/features/capture/capture_detail_action_sheet.dart`：编辑、清理原图和删除记录操作面板。
- `lib/features/capture/capture_detail_tabs.dart`：现场记录与文件信息双页签。
- `lib/features/settings/settings_group.dart`：设置首页的分组玻璃列表。
- `lib/shared/ui/adaptive_skeleton_count.dart`：按可视高度计算骨架数量。

现有文件继续保持各自职责，不把业务服务搬进 UI 组件。所有操作面板只返回枚举，由原屏幕调用现有服务。

---

### Task 1: 建立玻璃视觉系统和统一动效

**Files:**
- Create: `lib/shared/ui/glass_surface.dart`
- Modify: `lib/app_theme.dart`
- Modify: `lib/motion.dart`
- Test: `test/shared/ui/glass_surface_test.dart`
- Test: `test/navigation/route_transitions_test.dart`

**Interfaces:**
- Produces: `GlassSurface({child, borderRadius, padding, opacity, blurSigma})`。
- Produces: `GlassCard({child, onTap, borderRadius, padding})`。
- Produces: `AppMotion.rootSwitch = 240ms`、`AppMotion.pageTransition = 260ms`。

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('glass surface disables blur when animations are disabled', (tester) async {
  await tester.pumpWidget(
    const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: GlassSurface(child: Text('content'))),
    ),
  );
  expect(find.text('content'), findsOneWidget);
  expect(find.byType(BackdropFilter), findsNothing);
});

testWidgets('glass card keeps a semantic tap target', (tester) async {
  var tapped = false;
  await tester.pumpWidget(MaterialApp(home: GlassCard(onTap: () => tapped = true, child: const Text('项目'))));
  await tester.tap(find.text('项目'));
  expect(tapped, isTrue);
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `flutter test test/shared/ui/glass_surface_test.dart test/navigation/route_transitions_test.dart`

Expected: FAIL，提示 `GlassSurface`、`GlassCard` 或新动效常量不存在。

- [ ] **Step 3: 实现统一玻璃组件和时长**

```dart
class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child, this.borderRadius = const BorderRadius.all(Radius.circular(20)), this.padding, this.opacity = .72, this.blurSigma = 16});
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final double opacity;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blurEnabled = blurSigma > 0 && !MediaQuery.disableAnimationsOf(context);
    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: opacity.clamp(.58, .92).toDouble()),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
        borderRadius: borderRadius,
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    if (blurEnabled) content = BackdropFilter(filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma), child: content);
    return RepaintBoundary(child: ClipRRect(borderRadius: borderRadius, child: content));
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.onTap, this.borderRadius = const BorderRadius.all(Radius.circular(20)), this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => GlassSurface(
    borderRadius: borderRadius,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

abstract final class AppMotion {
  static const rootSwitch = Duration(milliseconds: 240);
  static const pageTransition = Duration(milliseconds: 260);
  static const short4 = Duration(milliseconds: 180);
  static const medium2 = pageTransition;
  static const medium4 = Duration(milliseconds: 320);
  static const long2 = Duration(milliseconds: 500);
  // 保留现有曲线和 durationOf 实现。
}
```

在 `app_theme.dart` 统一背景、卡片圆角、输入框和操作按钮样式；玻璃卡片不得依赖固定浅色，暗色主题使用同一 `ColorScheme` 推导。

- [ ] **Step 4: 运行定向测试**

Run: `flutter test test/shared/ui/glass_surface_test.dart test/navigation/route_transitions_test.dart`

Expected: PASS，减少动画时无 `BackdropFilter`，原有转场测试仍通过。

- [ ] **Step 5: 提交**

```bash
git add lib/shared/ui/glass_surface.dart lib/app_theme.dart lib/motion.dart test/shared/ui/glass_surface_test.dart test/navigation/route_transitions_test.dart
git commit -m "feat: add adaptive glass visual system"
```

---

### Task 2: 改为保活的悬浮一级导航

**Files:**
- Create: `lib/navigation/root_navigation_scaffold.dart`
- Modify: `lib/app.dart`
- Modify: `lib/features/projects/project_list_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/navigation/root_navigation_scaffold_test.dart`
- Test: `test/navigation/back_navigation_test.dart`
- Test: `test/features/settings/global_settings_screen_test.dart`

**Interfaces:**
- Consumes: `GlassSurface`、`AppMotion.rootSwitch`。
- Produces: `RootNavigationScaffold(navigationShell)`。
- Produces: `RootBranchContainer(currentIndex, children)`，分支保持挂载但非活动分支禁用点击、语义和 ticker。
- Produces: `AppStrings.projects`，中文“项目”、英文“Projects”。

- [ ] **Step 1: 写一级导航失败测试**

```dart
testWidgets('dock switches three preserved root branches', (tester) async {
  await pumpRouter(tester);
  expect(find.byKey(const Key('root-dock')), findsOneWidget);
  await tester.tap(find.byKey(const Key('root-destination-records')));
  expect(find.byType(AllCapturesScreen), findsOneWidget);
  await tester.tap(find.byKey(const Key('root-destination-settings')));
  expect(find.byType(GlobalSettingsScreen), findsOneWidget);
});

testWidgets('secondary routes hide dock', (tester) async {
  final router = await pumpRouter(tester);
  router.go('/projects/project-1');
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('root-dock')), findsNothing);
});
```

- [ ] **Step 2: 运行并确认失败**

Run: `flutter test test/navigation/root_navigation_scaffold_test.dart test/navigation/back_navigation_test.dart`

Expected: FAIL，当前路由没有 `StatefulShellRoute` 和悬浮 Dock。

- [ ] **Step 3: 实现 `StatefulShellRoute`**

```dart
StatefulShellRoute(
  builder: (context, state, shell) => RootNavigationScaffold(navigationShell: shell),
  navigatorContainerBuilder: (context, shell, children) => RootBranchContainer(currentIndex: shell.currentIndex, children: children),
  branches: [
    StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const ProjectListScreen())]),
    StatefulShellBranch(routes: [GoRoute(path: '/records', builder: (_, _) => const AllCapturesScreen())]),
    StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, _) => const GlobalSettingsScreen())]),
  ],
)
```

`root_navigation_scaffold.dart` 的核心结构固定为：

```dart
class RootNavigationScaffold extends StatelessWidget {
  const RootNavigationScaffold({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      body: navigationShell,
      floatingActionButton: navigationShell.currentIndex == 0
          ? FloatingActionButton(key: const Key('new-project-fab'), onPressed: () => context.push('/projects/new'), child: const Icon(Icons.add))
          : null,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: GlassSurface(
          key: const Key('root-dock'),
          borderRadius: BorderRadius.circular(24),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
            destinations: [
              NavigationDestination(key: const Key('root-destination-projects'), icon: const Icon(Icons.domain_outlined), label: strings.projects),
              NavigationDestination(key: const Key('root-destination-records'), icon: const Icon(Icons.photo_library_outlined), label: strings.allRecords),
              NavigationDestination(key: const Key('root-destination-settings'), icon: const Icon(Icons.settings_outlined), label: strings.settings),
            ],
          ),
        ),
      ),
    );
  }
}

class RootBranchContainer extends StatelessWidget {
  const RootBranchContainer({super.key, required this.currentIndex, required this.children});
  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (final (index, child) in children.indexed)
        Positioned.fill(
          child: TickerMode(
            enabled: index == currentIndex,
            child: IgnorePointer(
              ignoring: index != currentIndex,
              child: ExcludeSemantics(
                excluding: index != currentIndex,
                child: AnimatedOpacity(
                  opacity: index == currentIndex ? 1 : 0,
                  duration: AppMotion.durationOf(context, AppMotion.rootSwitch),
                  child: child,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
```

项目详情、新建项目和全部设置子页使用 `parentNavigatorKey: rootNavigatorKey` 压入根导航器，从而隐藏 Dock。移除项目首页原有“全部记录、设置”图标和自身 FAB；新建项目 FAB 由 `RootNavigationScaffold` 仅在索引 0 显示。

- [ ] **Step 4: 验证状态保留和返回顺序**

Run: `flutter test test/navigation/root_navigation_scaffold_test.dart test/navigation/back_navigation_test.dart test/features/settings/global_settings_screen_test.dart`

Expected: PASS；切换分支后滚动/搜索状态仍在，二级页不显示 Dock，搜索状态下返回不会退出应用。

- [ ] **Step 5: 提交**

```bash
git add lib/navigation/root_navigation_scaffold.dart lib/app.dart lib/features/projects/project_list_screen.dart lib/l10n/app_strings.dart test/navigation/root_navigation_scaffold_test.dart test/navigation/back_navigation_test.dart test/features/settings/global_settings_screen_test.dart
git commit -m "feat: add floating root navigation dock"
```

---

### Task 3: 重构项目首页卡片和最近照片

**Files:**
- Modify: `lib/domain/project_summary.dart`
- Modify: `lib/data/app_database.dart`
- Create: `lib/features/projects/project_summary_card.dart`
- Modify: `lib/features/projects/project_list_screen.dart`
- Test: `test/data/project_summary_query_test.dart`
- Test: `test/features/projects/project_list_screen_test.dart`

**Interfaces:**
- Produces: `ProjectSummary.recentCaptureIds: List<String>`，最多三个、按拍摄时间倒序。
- Produces: `ProjectSummaryCard(summary, outputPaths, onOpen)`，卡片内部不执行生命周期操作。

- [ ] **Step 1: 写查询和卡片失败测试**

```dart
expect(summaries.first.recentCaptureIds, ['capture-3', 'capture-2', 'capture-1']);
expect(summaries.first.recentCaptureIds, hasLength(3));

testWidgets('project card is one tap target and shows recent thumbnails', (tester) async {
  await pumpProjectList(tester, captures: 3);
  expect(find.byKey(const Key('project-thumbnail-capture-3')), findsOneWidget);
  expect(find.byType(PopupMenuButton), findsNothing);
});
```

- [ ] **Step 2: 运行并确认失败**

Run: `flutter test test/data/project_summary_query_test.dart test/features/projects/project_list_screen_test.dart`

Expected: FAIL，`recentCaptureIds` 和新卡片不存在。

- [ ] **Step 3: 扩展只读汇总查询并实现卡片**

在 `watchProjectSummaries` 的同一只读 SQL 中增加最多三个 `ready` 记录 ID，按拍摄时间倒序；不新增表或迁移。解析为空时返回 `const []`。

```sql
WITH ranked_ready AS (
  SELECT
    c.id,
    c.project_id,
    ROW_NUMBER() OVER (
      PARTITION BY c.project_id
      ORDER BY COALESCE(c.captured_at, c.created_at) DESC, c.id DESC
    ) AS row_number
  FROM captures AS c
  WHERE c.status = 'ready'
), recent_ready AS (
  SELECT project_id, GROUP_CONCAT(id, CHAR(31)) AS recent_capture_ids
  FROM ranked_ready
  WHERE row_number <= 3
  GROUP BY project_id
)
SELECT p.*, COUNT(c.id) AS capture_count,
       MAX(COALESCE(c.captured_at, c.created_at)) AS last_capture_at,
       recent_ready.recent_capture_ids
FROM projects AS p
LEFT JOIN captures AS c ON c.project_id = p.id AND c.status != 'pendingCamera'
LEFT JOIN recent_ready ON recent_ready.project_id = p.id
```

将上述 CTE 和 `recent_ready` 连接接入当前查询；现有动态 `WHERE`、完整 `GROUP BY`、置顶及最近拍摄排序原样保留，并把 `recent_ready.recent_capture_ids` 加入分组列。

```dart
final class ProjectSummary {
  const ProjectSummary({required this.project, required this.captureCount, required this.lastCaptureAt, this.recentCaptureIds = const []});
  final Project project;
  final int captureCount;
  final DateTime? lastCaptureAt;
  final List<String> recentCaptureIds;
}
```

卡片只暴露一个页面操作回调，缩略图解析留在独立私有组件：

```dart
class ProjectSummaryCard extends StatelessWidget {
  const ProjectSummaryCard({super.key, required this.summary, required this.outputPaths, required this.onOpen});
  final ProjectSummary summary;
  final CaptureOutputPaths outputPaths;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => GlassCard(
    onTap: onOpen,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Expanded(child: Text(summary.project.name, style: Theme.of(context).textTheme.titleMedium)), const Icon(Icons.chevron_right)]),
        _ProjectSummaryMetadata(summary: summary),
        if (summary.recentCaptureIds.isNotEmpty) ProjectRecentThumbnails(captureIds: summary.recentCaptureIds, outputPaths: outputPaths),
      ],
    ),
  );
}

class ProjectRecentThumbnails extends StatelessWidget {
  const ProjectRecentThumbnails({super.key, required this.captureIds, required this.outputPaths});
  final List<String> captureIds;
  final CaptureOutputPaths outputPaths;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final id in captureIds)
        Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: AspectRatio(
              aspectRatio: 1,
              child: RepaintBoundary(
                child: FutureBuilder<String>(
                  future: outputPaths.renderedPhotoPath(id),
                  builder: (context, snapshot) => snapshot.hasData
                      ? Image.file(File(snapshot.data!), key: Key('project-thumbnail-$id'), fit: BoxFit.cover, cacheWidth: 192, gaplessPlayback: true, errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12))
                      : const ColoredBox(color: Colors.black12),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
```

`_ProjectSummaryMetadata(summary)` 是同文件私有小组件，继续使用现有生命周期、`projectPhotoCount` 和 `lastCaptureAtLabel` 文案，以 `Wrap` 显示并允许大字体换行。

`ProjectSummaryCard` 使用 `CaptureOutputPaths.renderedPhotoPath(id)` 加载缩略图，`Image.file` 设置 `cacheWidth: 192`、`gaplessPlayback: true`，每张图包裹 `RepaintBoundary`；路径或文件缺失时显示中性占位，不显示“失败”文字。项目状态筛选改为一个紧凑入口，继续调用现有 `project_status_filter_sheet.dart`；搜索仍传入 `status: null`，覆盖全部生命周期。

- [ ] **Step 4: 运行定向测试**

Run: `flutter test test/data/project_summary_query_test.dart test/features/projects/project_list_screen_test.dart`

Expected: PASS；空项目仍无缩略图，排序和生命周期筛选原测试不变。

- [ ] **Step 5: 提交**

```bash
git add lib/domain/project_summary.dart lib/data/app_database.dart lib/features/projects/project_summary_card.dart lib/features/projects/project_list_screen.dart test/data/project_summary_query_test.dart test/features/projects/project_list_screen_test.dart
git commit -m "feat: redesign project summary cards"
```

---

### Task 4: 精简项目详情并统一项目操作面板

**Files:**
- Create: `lib/features/projects/project_action_sheet.dart`
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/features/capture/capture_filter_ui_test.dart`
- Test: `test/navigation/back_navigation_test.dart`

**Interfaces:**
- Produces: `enum ProjectAction { watermark, backup, rename, pin, unpin, complete, archive, reopen, delete }`。
- Produces: `Future<ProjectAction?> showProjectActionSheet(BuildContext context, Project project)`。

- [ ] **Step 1: 写操作面板和顶部栏失败测试**

```dart
expect(find.byKey(const Key('project-watermark-action')), findsNothing);
expect(find.byKey(const Key('project-backup-action')), findsNothing);
expect(find.byKey(const Key('project-actions')), findsOneWidget);
await tester.tap(find.byKey(const Key('project-actions')));
expect(find.byKey(const Key('project-action-sheet')), findsOneWidget);
expect(find.text('此项目水印设置'), findsOneWidget);
expect(find.text('重命名项目'), findsOneWidget);
```

- [ ] **Step 2: 运行并确认失败**

Run: `flutter test test/features/capture/capture_filter_ui_test.dart test/navigation/back_navigation_test.dart`

Expected: FAIL，当前仍有独立水印和备份图标，更多操作是弹出菜单。

- [ ] **Step 3: 实现文字操作面板和紧凑摘要**

```dart
final action = await showProjectActionSheet(context, project);
if (!mounted || action == null) return;
switch (action) {
  case ProjectAction.watermark: context.push('/projects/${project.id}/settings');
  case ProjectAction.backup: context.push('/settings/backup-restore/backup', extra: ProjectBackupSelectionArguments(initialProjectIds: {project.id}));
  case ProjectAction.rename: await _renameProject(project);
  case ProjectAction.pin: await ref.read(databaseProvider).setProjectPinned(project.id, true);
  case ProjectAction.unpin: await ref.read(databaseProvider).setProjectPinned(project.id, false);
  case ProjectAction.complete: await _transitionLifecycle(project.id, ProjectLifecycleStatus.completed);
  case ProjectAction.archive: await _transitionLifecycle(project.id, ProjectLifecycleStatus.archived);
  case ProjectAction.reopen: await _transitionLifecycle(project.id, ProjectLifecycleStatus.active);
  case ProjectAction.delete: await _deleteProject(project);
}
```

操作面板本身只返回枚举，不持有数据库或服务：

```dart
enum ProjectAction { watermark, backup, rename, pin, unpin, complete, archive, reopen, delete }

typedef ProjectActionItem = ({ProjectAction action, Key key, IconData icon, String label});

List<ProjectActionItem> projectActionsFor(Project project, AppStrings strings) => [
  (action: ProjectAction.watermark, key: const Key('project-watermark-action'), icon: Icons.tune_outlined, label: strings.projectWatermarkSettings),
  (action: ProjectAction.backup, key: const Key('project-backup-action'), icon: Icons.archive_outlined, label: strings.backupProjects),
  (action: ProjectAction.rename, key: const Key('rename-project'), icon: Icons.edit_outlined, label: strings.renameProject),
  project.isPinned
      ? (action: ProjectAction.unpin, key: const Key('unpin-project'), icon: Icons.push_pin, label: strings.unpinProject)
      : (action: ProjectAction.pin, key: const Key('pin-project'), icon: Icons.push_pin_outlined, label: strings.pinProject),
  ...switch (project.lifecycleStatus) {
    ProjectLifecycleStatus.active => [
      (action: ProjectAction.complete, key: const Key('complete-project'), icon: Icons.check_circle_outline, label: strings.markProjectCompleted),
      (action: ProjectAction.archive, key: const Key('archive-project'), icon: Icons.archive_outlined, label: strings.archiveProject),
    ],
    ProjectLifecycleStatus.completed => [
      (action: ProjectAction.reopen, key: const Key('reopen-project'), icon: Icons.replay_outlined, label: strings.reopenProject),
      (action: ProjectAction.archive, key: const Key('archive-project'), icon: Icons.archive_outlined, label: strings.archiveProject),
    ],
    ProjectLifecycleStatus.archived => [
      (action: ProjectAction.reopen, key: const Key('reopen-project'), icon: Icons.unarchive_outlined, label: strings.restoreProjectToActive),
    ],
  },
  (action: ProjectAction.delete, key: const Key('delete-project'), icon: Icons.delete_outline, label: strings.deleteProject),
];

Future<ProjectAction?> showProjectActionSheet(BuildContext context, Project project) {
  final strings = AppStrings.of(context);
  final actions = projectActionsFor(project, strings);
  return showModalBottomSheet<ProjectAction>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => ListView(
      key: const Key('project-action-sheet'),
      shrinkWrap: true,
      children: [
        for (final item in actions)
          ListTile(
            key: item.key,
            leading: Icon(item.icon, color: item.action == ProjectAction.delete ? Theme.of(context).colorScheme.error : null),
            title: Text(item.label),
            onTap: () => Navigator.pop(sheetContext, item.action),
          ),
      ],
    ),
  );
}
```

操作面板使用 `showModalBottomSheet(useSafeArea: true, showDragHandle: true)`；删除行使用 `colorScheme.error` 并保持现有二次确认。项目摘要改为紧凑玻璃表面，顶部仅保留返回、搜索、更多；选择模式的“全选/取消全选”逻辑不得改变。

- [ ] **Step 4: 运行定向测试**

Run: `flutter test test/features/capture/capture_filter_ui_test.dart test/navigation/back_navigation_test.dart`

Expected: PASS；返回键先关闭操作面板，再退出搜索/选择，再返回列表。

- [ ] **Step 5: 提交**

```bash
git add lib/features/projects/project_action_sheet.dart lib/features/projects/project_detail_screen.dart lib/l10n/app_strings.dart test/features/capture/capture_filter_ui_test.dart test/navigation/back_navigation_test.dart
git commit -m "feat: simplify project detail actions"
```

---

### Task 5: 将全部记录改为筛选面板、条件标签和日期分组

**Files:**
- Create: `lib/features/capture/capture_filter_sheet.dart`
- Create: `lib/features/capture/capture_active_filter_chips.dart`
- Modify: `lib/features/capture/all_captures_screen.dart`
- Modify: `lib/features/capture/capture_paged_list.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/features/capture/capture_filter_ui_test.dart`
- Test: `test/features/capture/capture_search_paging_ui_test.dart`

**Interfaces:**
- Produces: `Future<CaptureFilter?> showCaptureFilterSheet({context, initial, projects, options})`；取消返回 `null`，应用返回完整 `CaptureFilter`。
- Produces: `CaptureActiveFilterChips(filter, projects, onChanged)`。
- Produces: `CapturePagedList.groupKey` 与 `CapturePagedList.groupHeaderBuilder` 可选参数。

- [ ] **Step 1: 写筛选草稿、单项清除和日期分组失败测试**

```dart
await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
await tester.tap(find.byKey(const Key('filter-project-project-1')));
await tester.tap(find.byKey(const Key('filter-apply')));
expect(find.byKey(const Key('active-filter-project')), findsOneWidget);
await tester.tap(find.byKey(const Key('remove-filter-project')));
expect(find.byKey(const Key('active-filter-project')), findsNothing);
expect(find.byKey(const Key('capture-date-2026-08-04')), findsOneWidget);
```

- [ ] **Step 2: 运行并确认失败**

Run: `flutter test test/features/capture/capture_filter_ui_test.dart test/features/capture/capture_search_paging_ui_test.dart`

Expected: FAIL，当前四个筛选控件常驻且列表没有日期分组标题。

- [ ] **Step 3: 实现草稿式筛选和分组 sliver**

```dart
final next = await showCaptureFilterSheet(
  context: context,
  initial: _filter,
  projects: projects,
  options: _dateOptions,
);
if (next != null) _onFilterChanged(next);
```

筛选入口与条件标签的公共结构为：

```dart
Future<CaptureFilter?> showCaptureFilterSheet({
  required BuildContext context,
  required CaptureFilter initial,
  required List<Project> projects,
  required CaptureDateOptions options,
}) => showModalBottomSheet<CaptureFilter>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => CaptureFilterSheet(initial: initial, projects: projects, options: options),
);

class CaptureActiveFilterChips extends StatelessWidget {
  const CaptureActiveFilterChips({super.key, required this.filter, required this.projects, required this.onChanged});
  final CaptureFilter filter;
  final List<Project> projects;
  final ValueChanged<CaptureFilter> onChanged;

  List<Widget> _chips(BuildContext context) {
    final strings = AppStrings.of(context);
    final chips = <Widget>[];
    if (filter.projectId != null) {
      var label = strings.allProjects;
      for (final project in projects) {
        if (project.id == filter.projectId) label = project.name;
      }
      chips.add(InputChip(key: const Key('active-filter-project'), label: Text(label), onDeleted: () => onChanged(const CaptureFilter())));
    }
    if (filter.year != null) chips.add(InputChip(key: const Key('active-filter-year'), label: Text('${filter.year}'), onDeleted: () => onChanged(filter.selectYear(null))));
    if (filter.month != null) chips.add(InputChip(key: const Key('active-filter-month'), label: Text('${filter.month}${strings.monthSuffix}'), onDeleted: () => onChanged(filter.selectMonth(null))));
    if (filter.day != null) chips.add(InputChip(key: const Key('active-filter-day'), label: Text('${filter.day}${strings.daySuffix}'), onDeleted: () => onChanged(filter.selectDay(null))));
    return chips;
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: _chips(context)),
  );
}
```

`CaptureFilterSheet` 内部保存 `CaptureFilter _draft`；项目、年、月、日控件只更新 `_draft`，重置设置 `const CaptureFilter()`，应用按钮执行 `Navigator.pop(context, _draft)`。删除项目条件同时清空日期条件；删除年份、月份、日期分别使用现有 `selectYear(null)`、`selectMonth(null)`、`selectDay(null)` 级联规则。

面板内部级联规则沿用现有 `CaptureFilter`：清除年份同时清除月、日；清除月份同时清除日；改变项目清空日期。只有点击“应用”才更新页面查询，取消不得污染原筛选。

`CapturePagedList` 将连续相同日期的记录组成 `SliverMainAxisGroup`，每组使用 `SliverPersistentHeader(pinned: true)` 和 `SliverList.separated`；加载更多仍由最后八条记录触发，分页游标和 `watchByIds` 不变。

- [ ] **Step 4: 验证筛选、分页、搜索和选择互斥**

Run: `flutter test test/features/capture/capture_filter_ui_test.dart test/features/capture/capture_search_paging_ui_test.dart test/features/capture/capture_batch_paged_selection_test.dart`

Expected: PASS；筛选变化清空选择，搜索状态不能同时打开筛选面板，360dp 下标签无溢出。

- [ ] **Step 5: 提交**

```bash
git add lib/features/capture/capture_filter_sheet.dart lib/features/capture/capture_active_filter_chips.dart lib/features/capture/all_captures_screen.dart lib/features/capture/capture_paged_list.dart lib/l10n/app_strings.dart test/features/capture/capture_filter_ui_test.dart test/features/capture/capture_search_paging_ui_test.dart
git commit -m "feat: add record filter sheet and date groups"
```

---

### Task 6: 将设置首页改为三组玻璃列表

**Files:**
- Create: `lib/features/settings/settings_group.dart`
- Modify: `lib/features/settings/global_settings_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/features/settings/global_settings_screen_test.dart`
- Test: `test/features/settings/a11y_test.dart`

**Interfaces:**
- Produces: `SettingsGroup(title, children)`。
- Produces: `SettingsEntry(icon, title, subtitle, route, key)`。
- Produces: `AppStrings.settingsCaptureAndRecords`、`settingsDataAndSafety`、`settingsApplication` 中英文分组标题。

- [ ] **Step 1: 写分组和实时摘要失败测试**

```dart
expect(find.byKey(const Key('settings-group-capture')), findsOneWidget);
expect(find.byKey(const Key('settings-group-data')), findsOneWidget);
expect(find.byKey(const Key('settings-group-app')), findsOneWidget);
expect(find.text('1.0 KB'), findsOneWidget);
expect(find.text('简体中文'), findsOneWidget);
expect(find.byType(BackButton), findsNothing);
```

- [ ] **Step 2: 运行并确认失败**

Run: `flutter test test/features/settings/global_settings_screen_test.dart test/features/settings/a11y_test.dart`

Expected: FAIL，当前是九张独立卡片且没有分组和状态摘要。

- [ ] **Step 3: 实现三组设置**

```dart
SettingsGroup(
  key: const Key('settings-group-data'),
  title: strings.settingsDataAndSafety,
  children: [
    SettingsEntry(route: '/settings/backup-restore', icon: Icons.settings_backup_restore_outlined, title: strings.backupAndRestore),
    SettingsEntry(route: '/settings/storage', icon: Icons.storage_outlined, title: strings.storageMenuLabel, subtitle: storageSummary),
    SettingsEntry(route: '/settings/diagnostics', icon: Icons.health_and_safety_outlined, title: strings.diagnosticsAndFeedback),
  ],
)
```

分组组件不得自行读取设置，`SettingsEntry` 只负责导航：

```dart
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(padding: const EdgeInsets.fromLTRB(8, 16, 8, 6), child: Text(title, style: Theme.of(context).textTheme.labelLarge)),
      GlassSurface(child: Column(children: children)),
    ],
  );
}

class SettingsEntry extends StatelessWidget {
  const SettingsEntry({super.key, required this.icon, required this.title, required this.route, this.subtitle});
  final IconData icon;
  final String title;
  final String route;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 48,
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.push(route),
  );
}
```

`GlobalSettingsScreen` 改为 `ConsumerWidget`，使用 `appSettingsProvider` 显示语言、通知状态，使用缓存的 `storageUsageProvider` 和 `formatStorageBytes` 显示总占用。异步值未完成时留空副标题，不显示转圈或跳动占位。

- [ ] **Step 4: 运行设置与无障碍测试**

Run: `flutter test test/features/settings/global_settings_screen_test.dart test/features/settings/a11y_test.dart`

Expected: PASS；每行点击区域至少 48dp，中文和英文均可完整访问。

- [ ] **Step 5: 提交**

```bash
git add lib/features/settings/settings_group.dart lib/features/settings/global_settings_screen.dart lib/l10n/app_strings.dart test/features/settings/global_settings_screen_test.dart test/features/settings/a11y_test.dart
git commit -m "feat: group settings into glass sections"
```

---

### Task 7: 将拍摄表单压缩为单屏并固定拍摄按钮

**Files:**
- Modify: `lib/features/capture/capture_form_screen.dart`
- Modify: `lib/features/capture/location_permission_prompt.dart`
- Modify: `lib/features/capture/capture_recent_suggestions.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/features/capture/capture_form_screen_test.dart`
- Test: `test/features/capture/capture_field_reuse_test.dart`
- Test: `test/workflow/location_permission_service_test.dart`

**Interfaces:**
- 保留现有 `CaptureRecentSuggestions` 数据接口和 `CaptureFormDraftStore`。
- Produces: `CaptureNotesField(controller)`，默认折叠。
- Produces: 紧凑 `LocationPermissionPrompt`，授权、拒绝或关闭后由现有服务持久隐藏。

- [ ] **Step 1: 写单屏结构和连续拍摄失败测试**

```dart
expect(find.byKey(const Key('work-location')), findsOneWidget);
expect(find.byKey(const Key('work-content')), findsOneWidget);
expect(find.byKey(const Key('photographer')), findsOneWidget);
expect(find.byKey(const Key('notes')), findsNothing);
await tester.tap(find.byKey(const Key('notes-expander')));
expect(find.byKey(const Key('notes')), findsOneWidget);
expect(tester.getBottomRight(find.byKey(const Key('capture-button'))).dy, lessThanOrEqualTo(visibleHeight));
```

连续拍摄测试在第一次返回系统相机后断言三个必填控制器值不变、备注清空、按钮重新可用。

- [ ] **Step 2: 运行并确认失败**

Run: `flutter test test/features/capture/capture_form_screen_test.dart test/features/capture/capture_field_reuse_test.dart test/workflow/location_permission_service_test.dart`

Expected: FAIL，备注当前常驻，拍摄按钮在滚动列表底部。

- [ ] **Step 3: 重排表单**

```dart
return Scaffold(
  appBar: AppBar(title: Text(strings.captureFormTitle)),
  body: _CaptureFormBody(
    locationController: _locationController,
    contentController: _contentController,
    photographerController: _photographerController,
    notesController: _notesController,
    locationFocusNode: _locationFocusNode,
    contentFocusNode: _contentFocusNode,
    photographerFocusNode: _photographerFocusNode,
    projectId: widget.projectId,
    loadSuggestions: _loadRecentSuggestions,
    strings: strings,
    working: _working,
    onTemplates: _openTemplates,
    onCapture: () => _capture(project),
    permissionPrompt: prompt,
  ),
  bottomNavigationBar: readOnly ? null : SafeArea(
    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: CaptureSubmitButton(working: _working, onPressed: () => _capture(project)))),
  ),
);
```

备注组件固定为：

```dart
class CaptureNotesField extends StatefulWidget {
  const CaptureNotesField({super.key, required this.controller});
  final TextEditingController controller;
  @override
  State<CaptureNotesField> createState() => _CaptureNotesFieldState();
}

class _CaptureNotesFieldState extends State<CaptureNotesField> {
  var expanded = false;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        key: const Key('notes-expander'),
        title: Text(AppStrings.of(context).notesOptional),
        trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
        onTap: () => setState(() => expanded = !expanded),
      ),
      AnimatedSize(
        duration: AppMotion.durationOf(context, AppMotion.short4),
        child: expanded ? TextFormField(key: const Key('notes'), controller: widget.controller, maxLines: 3) : const SizedBox.shrink(),
      ),
    ],
  );
}

class CaptureSubmitButton extends StatelessWidget {
  const CaptureSubmitButton({super.key, required this.working, required this.onPressed});
  final bool working;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    key: const Key('capture-button'),
    onPressed: working ? null : () { HapticFeedback.lightImpact(); onPressed(); },
    icon: working
        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.photo_camera_outlined),
    label: Text(AppStrings.of(context).openSystemCamera),
  );
}
```

必填项保持在同一 `Form` 中，建议标签紧邻字段且最多显示三项；备注用 `AnimatedSize` 展开。定位说明压缩为一行正文加一个操作按钮，不再使用大卡片。移除表单底部重复的长篇拍摄说明，改为按钮上方一行简短提示。

- [ ] **Step 4: 验证键盘、草稿、模板和后台拍摄契约**

Run: `flutter test test/features/capture/capture_form_screen_test.dart test/features/capture/capture_field_reuse_test.dart test/platform/capture_form_draft_store_test.dart test/workflow/capture_workflow_test.dart`

Expected: PASS；模板、建议、草稿恢复和后台处理调用不变。

- [ ] **Step 5: 提交**

```bash
git add lib/features/capture/capture_form_screen.dart lib/features/capture/location_permission_prompt.dart lib/features/capture/capture_recent_suggestions.dart lib/l10n/app_strings.dart test/features/capture/capture_form_screen_test.dart test/features/capture/capture_field_reuse_test.dart
git commit -m "feat: compact the continuous capture form"
```

---

### Task 8: 重构照片详情双页签和危险操作

**Files:**
- Create: `lib/features/capture/capture_detail_action_sheet.dart`
- Create: `lib/features/capture/capture_detail_tabs.dart`
- Modify: `lib/features/capture/capture_detail_screen.dart`
- Modify: `lib/domain/capture_display_name.dart`
- Modify: `lib/l10n/app_strings.dart`
- Test: `test/domain/capture_display_name_test.dart`
- Test: `test/features/capture/capture_detail_screen_test.dart`

**Interfaces:**
- Produces: `enum CaptureDetailSection { fieldRecord, fileInfo }`。
- Produces: `enum CaptureDetailAction { edit, deleteOriginal, deleteRecord }`。
- Produces: `Future<CaptureDetailAction?> showCaptureDetailActionSheet(BuildContext context, {required bool canEdit, required bool canDeleteOriginal})`。
- Reuses: `captureListDisplayName({required DateTime? capturedAt, required String? photoNumber, required String fallback})` 作为详情页短标题。
- Produces: `AppStrings.fieldRecordTab`、`fileInfoTab`、`fullFileName` 中英文文案。

- [ ] **Step 1: 写短标题、双页签和操作面板失败测试**

```dart
expect(find.text('2026-08-04 · 003'), findsOneWidget);
expect(find.byKey(const Key('detail-tab-field-record')), findsOneWidget);
expect(find.byKey(const Key('detail-tab-file-info')), findsOneWidget);
expect(find.byKey(const Key('delete-original')), findsNothing);
await tester.tap(find.byKey(const Key('capture-detail-actions')));
expect(find.byKey(const Key('capture-detail-action-sheet')), findsOneWidget);
```

- [ ] **Step 2: 运行并确认失败**

Run: `flutter test test/domain/capture_display_name_test.dart test/features/capture/capture_detail_screen_test.dart`

Expected: FAIL，详情仍使用完整编号且三个操作图标直接放在顶部。

- [ ] **Step 3: 实现 P2 详情结构**

```dart
final title = captureListDisplayName(
  capturedAt: capture.capturedAt,
  photoNumber: capture.photoNumber,
  fallback: strings.captureDetail,
);
```

双页签与操作面板保持无业务状态：

```dart
enum CaptureDetailSection { fieldRecord, fileInfo }
enum CaptureDetailAction { edit, deleteOriginal, deleteRecord }

class CaptureDetailTabs extends StatelessWidget {
  const CaptureDetailTabs({super.key, required this.value, required this.onChanged});
  final CaptureDetailSection value;
  final ValueChanged<CaptureDetailSection> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<CaptureDetailSection>(
    segments: [
      ButtonSegment(value: CaptureDetailSection.fieldRecord, label: Text(AppStrings.of(context).fieldRecordTab, key: const Key('detail-tab-field-record'))),
      ButtonSegment(value: CaptureDetailSection.fileInfo, label: Text(AppStrings.of(context).fileInfoTab, key: const Key('detail-tab-file-info'))),
    ],
    selected: {value},
    onSelectionChanged: (selection) => onChanged(selection.single),
  );
}

Future<CaptureDetailAction?> showCaptureDetailActionSheet(BuildContext context, {required bool canEdit, required bool canDeleteOriginal}) {
  return showModalBottomSheet<CaptureDetailAction>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => CaptureDetailActionList(
      key: const Key('capture-detail-action-sheet'),
      canEdit: canEdit,
      canDeleteOriginal: canDeleteOriginal,
      onSelected: (action) => Navigator.pop(sheetContext, action),
    ),
  );
}

class CaptureDetailActionList extends StatelessWidget {
  const CaptureDetailActionList({super.key, required this.canEdit, required this.canDeleteOriginal, required this.onSelected});
  final bool canEdit;
  final bool canDeleteOriginal;
  final ValueChanged<CaptureDetailAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (canEdit) ListTile(leading: const Icon(Icons.edit_outlined), title: Text(strings.editRecord), onTap: () => onSelected(CaptureDetailAction.edit)),
      if (canDeleteOriginal) ListTile(leading: const Icon(Icons.cleaning_services_outlined), title: Text(strings.deleteOriginal), onTap: () => onSelected(CaptureDetailAction.deleteOriginal)),
      ListTile(leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error), title: Text(strings.deleteRecord, style: TextStyle(color: Theme.of(context).colorScheme.error)), onTap: () => onSelected(CaptureDetailAction.deleteRecord)),
    ]);
  }
}
```

成片/原图切换放在照片上方；照片下方使用 `CaptureDetailTabs`。现场记录页只展示工程部位、工作内容、拍摄人、备注、时间和坐标；文件信息页展示完整文件名、原图状态、两种文件大小/分辨率/格式、发布状态和 SHA-256。

顶部只保留返回与 `capture-detail-actions`。操作面板返回枚举后继续调用现有 `_deleteOriginal`、`_deleteAll` 和编辑路由；删除确认和 5 秒撤销逻辑保持不变。

- [ ] **Step 4: 运行详情测试**

Run: `flutter test test/domain/capture_display_name_test.dart test/features/capture/capture_detail_screen_test.dart`

Expected: PASS；原图缺失时来源切换与删除原图入口均隐藏，文件信息仍说明原图状态。

- [ ] **Step 5: 提交**

```bash
git add lib/features/capture/capture_detail_action_sheet.dart lib/features/capture/capture_detail_tabs.dart lib/features/capture/capture_detail_screen.dart lib/domain/capture_display_name.dart lib/l10n/app_strings.dart test/domain/capture_display_name_test.dart test/features/capture/capture_detail_screen_test.dart
git commit -m "feat: redesign capture detail information"
```

---

### Task 9: 固化 Hero、全屏加载和页面刷新稳定性

**Files:**
- Modify: `lib/features/capture/capture_image_preview.dart`
- Modify: `lib/features/capture/capture_photo_hero.dart`
- Modify: `lib/features/capture/capture_detail_screen.dart`
- Modify: `lib/features/capture/capture_fullscreen_screen.dart`
- Test: `test/features/capture/capture_image_preview_test.dart`
- Test: `test/features/capture/capture_photo_hero_test.dart`
- Test: `test/features/capture/capture_fullscreen_screen_test.dart`

**Interfaces:**
- 保留现有 `CapturePhotoHero(tag, path, child)` 和 `CaptureFullscreenSequence` 公共接口。
- `CaptureImagePreview` 的 `initialImagePath` 在异步路径解析完成前必须持续绘制，不能切换到失败占位。

- [ ] **Step 1: 写前进、返回和全屏首帧回归测试**

```dart
testWidgets('forward hero never exposes failure placeholder at handoff', (tester) async {
  await openRecordDetailWithDelayedResolution(tester);
  await tester.pump(const Duration(milliseconds: 260));
  expect(find.text('失败'), findsNothing);
  expect(find.byKey(const Key('capture-photo-hero-flight')), findsNothing);
  expect(find.byType(Image), findsWidgets);
});

testWidgets('fullscreen paints preview on its first black frame', (tester) async {
  await openFullscreenWithDelayedPath(tester);
  await tester.pump();
  expect(find.byType(Image), findsOneWidget);
  expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
});
```

- [ ] **Step 2: 运行并确认测试能捕获闪烁**

Run: `flutter test test/features/capture/capture_image_preview_test.dart test/features/capture/capture_photo_hero_test.dart test/features/capture/capture_fullscreen_screen_test.dart`

Expected: 现有 Hero 保护测试在 Task 8 新布局上继续 PASS；若新增首帧用例失败，只修复它暴露的预览交接，不重写现有序列与分页逻辑。

- [ ] **Step 3: 统一 Hero 首帧和落点图像**

保持同一个 `ResizeImage(FileImage(File(path)))` 缓存键贯穿列表、Hero shuttle 和详情落点；详情页不得用新的 `AnimatedSwitcher` 包住 Hero。全屏继续接收详情已解码的 `previewImage`，异步路径未完成或失败时保留该预览；只有预览和目标文件都不存在才显示缺图图标。

来源切换只更新详情内容，不重建 Hero 的外层 `HeroState`。原图已逻辑删除时继续使用 `OriginalPhotoState` 阻止路径回退。

- [ ] **Step 4: 运行照片链路测试**

Run: `flutter test test/features/capture/capture_image_preview_test.dart test/features/capture/capture_photo_hero_test.dart test/features/capture/capture_fullscreen_screen_test.dart test/features/capture/capture_fullscreen_sequence_test.dart`

Expected: PASS；前进、返回、切换来源和全屏第一帧都没有失败占位或重复淡入。

- [ ] **Step 5: 提交**

```bash
git add lib/features/capture/capture_image_preview.dart lib/features/capture/capture_photo_hero.dart lib/features/capture/capture_detail_screen.dart lib/features/capture/capture_fullscreen_screen.dart test/features/capture/capture_image_preview_test.dart test/features/capture/capture_photo_hero_test.dart test/features/capture/capture_fullscreen_screen_test.dart
git commit -m "fix: stabilize photo transitions and first frames"
```

---

### Task 10: 统一骨架、错误、无障碍并完成全量验收

**Files:**
- Create: `lib/shared/ui/adaptive_skeleton_count.dart`
- Modify: `lib/features/projects/project_list_screen.dart`
- Modify: `lib/features/capture/capture_paged_list.dart`
- Modify: `lib/l10n/app_strings.dart`
- Modify: `README.md`
- Test: `test/shared/ui/adaptive_skeleton_count_test.dart`
- Test: `test/features/settings/a11y_test.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Produces: `int adaptiveSkeletonCount({required double viewportHeight, required double itemExtent, int min = 2, int max = 8})`。

- [ ] **Step 1: 写骨架数量和大字体失败测试**

```dart
expect(adaptiveSkeletonCount(viewportHeight: 640, itemExtent: 118), 6);
expect(adaptiveSkeletonCount(viewportHeight: 220, itemExtent: 118), 2);

testWidgets('root pages have no overflow at 360dp and 200 percent text scale', (tester) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2;
  await pumpApp(tester, textScaler: const TextScaler.linear(2));
  expect(tester.takeException(), isNull);
});
```

辅助函数实现固定为向上取整并限制范围：

```dart
int adaptiveSkeletonCount({
  required double viewportHeight,
  required double itemExtent,
  int min = 2,
  int max = 8,
}) {
  if (!viewportHeight.isFinite || viewportHeight <= 0 || !itemExtent.isFinite || itemExtent <= 0) return min;
  return (viewportHeight / itemExtent).ceil().clamp(min, max).toInt();
}
```

- [ ] **Step 2: 运行并确认失败**

Run: `flutter test test/shared/ui/adaptive_skeleton_count_test.dart test/features/settings/a11y_test.dart test/widget_test.dart`

Expected: FAIL，辅助函数不存在或新布局在大字体下暴露溢出。

- [ ] **Step 3: 接入自适应骨架和明确错误文案**

项目与记录列表根据 `LayoutBuilder.maxHeight` 计算骨架数量，真实数据出现时保持同一内容容器 key，避免先显示五条虚假项目后瞬间缩成一条。检查权限、备份、照片处理和列表加载错误，确保均提供原因与重试、设置或保留原图等下一步操作。

README 更新一级导航、筛选、连续拍摄、照片详情和设置分组说明；不修改版本号和发布下载链接。

- [ ] **Step 4: 运行格式化、静态检查和全量测试**

Run: `dart format --output=none --set-exit-if-changed lib test`

Expected: exit 0。

Run: `flutter analyze`

Expected: `No issues found!`

Run: `flutter test`

Expected: 全部 Flutter 测试通过，0 failure。

Run: `cargo fmt --manifest-path rust/Cargo.toml -- --check`

Expected: Rust 格式检查通过。

Run: `cargo test --manifest-path rust/Cargo.toml`

Expected: 全部 Rust 测试通过。

Run: `.\gradlew.bat testDebugUnitTest`

Workdir: `android`

Expected: `BUILD SUCCESSFUL`。

Run: `flutter build apk --debug`

Expected: exit 0，并生成 `build/app/outputs/flutter-apk/app-debug.apk`。

- [ ] **Step 5: 真机验收并提交**

逐项验证：三个一级页面切换、搜索返回、筛选返回、全选/取消全选、连续拍摄、后台状态刷新、成片/原图、Hero 前进/返回、全屏首帧、设置分组、玻璃可读性、大字体和减少动画。

```bash
git add lib/shared/ui/adaptive_skeleton_count.dart lib/features/projects/project_list_screen.dart lib/features/capture/capture_paged_list.dart lib/l10n/app_strings.dart README.md test/shared/ui/adaptive_skeleton_count_test.dart test/features/settings/a11y_test.dart test/widget_test.dart
git commit -m "test: complete UI refresh accessibility checks"
```

---

## 完成定义

- 十个任务按顺序完成，每个任务独立测试并提交；
- 与设计文档的 B1、D1、F1、P2、S1、R1、V2 决策一致；
- 未引入数据库迁移、网络权限或新的在线依赖；
- 全量自动化验证通过，并完成真机视觉与返回逻辑检查；
- 最终 PR 只包含界面重构、必要的只读项目汇总扩展、测试和 README 更新。
