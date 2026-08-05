# SiteMark 悬浮导航与记录列表精修 Implementation Plan

> **For agentic workers / 给执行 Agent：** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复项目详情返回时照片闪过、一级 Dock 不够悬浮、日期条割裂界面和批量选择挤压记录区域四项体验问题，同时保留现有分页、筛选、批量业务与照片 Hero 行为。

**Architecture:** 新建一个只负责底部悬浮定位的共享布局，让普通一级 Dock 和批量选择 Dock 使用同一套尺寸、安全区与动画规则；全部记录页通过一个短生命周期的 Riverpod 状态只通知根导航隐藏普通 Dock。`CapturePagedList` 继续掌管滚动，通过已构建记录行的实际位置向页面报告当前可见日期；项目详情则使用独立的整页轻位移淡入淡出转场，不再复用共享轴缩放。

**Tech Stack:** Flutter 3 / Dart 3、Material 3、flutter_riverpod 3、go_router、现有 `GlassSurface`、Flutter widget tests；不新增第三方依赖。

## Global Constraints

- 只解决已确认的三组真机界面问题，不修改数据库结构、查询排序、记录字段、批量操作种类和照片 Hero。
- Android 最低版本继续为 Android 12（API 31），本轮不修改版本号。
- 普通 Dock 与选择 Dock 必须互斥，任何时刻底部最多一个悬浮操作面。
- 列表内容可滚动到 Dock 后方，但最后一条必须能完整滚动到 Dock 上方。
- 选择 Dock 在 360dp 宽度和 3 倍字体下不得溢出；四个操作均保留至少 48dp 点击区域、tooltip 和语义名称。
- 精确筛选到某天时日期固定；其他情况下日期只随可见记录变化，不触发查询、刷新或滚动跳转。
- 开启系统“减少动画”时跳过 Dock 与页面转场动画。
- 项目详情返回优化不得改变记录列表到照片详情/全屏查看的 Hero 链路。
- 所有改动使用测试驱动方式完成；每个任务通过自己的定向测试后再提交。

---

## 文件结构与接口锁定

### 新建文件

- `lib/shared/ui/floating_dock_layout.dart`
  - 保存统一几何常量；提供把内容、悬浮 Dock 和可选 FAB 放进同一覆盖层的 `FloatingDockLayout`。
- `lib/navigation/root_chrome_controller.dart`
  - 保存“全部记录是否处于选择模式”的短生命周期 Riverpod 状态；只控制根 Dock 显隐，不持久化、不进入数据库。

### 修改文件

- `lib/navigation/root_navigation_scaffold.dart`
  - 改为 `ConsumerWidget`；把普通 Dock 从 `Scaffold.bottomNavigationBar` 移入 `FloatingDockLayout`，并在全部记录选择模式下隐藏。
- `lib/features/capture/capture_batch_action_bar.dart`
  - 保留原类名和服务调用，去掉 `BottomAppBar` 与可见文字列，改成单行紧凑玻璃 Dock。
- `lib/features/capture/all_captures_screen.dart`
  - 同步根 Dock 状态；在选择模式显示悬浮选择 Dock；筛选右侧显示当前日期；移除列表日期条。
- `lib/features/projects/project_detail_screen.dart`
  - 移除 `bottomNavigationBar`，在页面内容上覆盖同款选择 Dock，并按模式增加列表底部留白。
- `lib/features/capture/capture_paged_list.dart`
  - 取消可视日期头构建器；新增 `ValueChanged<String?>? onVisibleGroupChanged`，根据实际可见记录向上报告分组。
- `lib/navigation/route_transitions.dart`
  - 新增项目详情专用转场 `buildProjectDetailRouteTransition`。
- `lib/app.dart`
  - 新增 `_projectDetailPage` 并只用于 `/projects/:projectId`。
- `lib/l10n/app_strings.dart`
  - 新增当前可见日期的中英文语义文本。
- `README.md`
  - 把“按日期分组”更新为“筛选旁动态日期”，把批量操作说明更新为上下文悬浮 Dock；不修改版本信息。

### 测试文件

- `test/shared/ui/floating_dock_layout_test.dart`（新建）
- `test/navigation/root_navigation_scaffold_test.dart`
- `test/features/capture/capture_search_paging_ui_test.dart`
- `test/features/capture/capture_filter_ui_test.dart`
- `test/features/capture/motion_selection_test.dart`
- `test/features/capture/capture_batch_paged_selection_test.dart`
- `test/navigation/route_transitions_test.dart`
- `test/features/projects/project_list_screen_test.dart`

---

### Task 1: 统一悬浮 Dock 几何并改造根导航

**Files:**
- Create: `lib/shared/ui/floating_dock_layout.dart`
- Create: `lib/navigation/root_chrome_controller.dart`
- Create: `test/shared/ui/floating_dock_layout_test.dart`
- Modify: `lib/navigation/root_navigation_scaffold.dart`
- Modify: `test/navigation/root_navigation_scaffold_test.dart`

**Interfaces:**
- Produces: `const double floatingDockHorizontalInset = 14`
- Produces: `const double floatingDockBottomInset = 12`
- Produces: `const double floatingDockHeight = 80`
- Produces: `const double floatingDockReservedSpace = 112`
- Produces: `FloatingDockLayout({required Widget child, Widget? dock, Widget? floatingActionButton, Key? dockKey})`
- Produces: `allCapturesSelectionModeProvider: NotifierProvider<AllCapturesSelectionModeController, bool>`
- Produces: `AllCapturesSelectionModeController.setActive(bool value)`
- Consumes: `GlassSurface`、`AppMotion.durationOf`、当前 `StatefulNavigationShell`。

- [ ] **Step 1: 为覆盖式布局写失败测试**

在 `test/shared/ui/floating_dock_layout_test.dart` 写出完整测试装配，验证内容尺寸不因 Dock 出现而变化、Dock 与屏幕四周有间距、FAB 位于 Dock 上方、减少动画时直接切换：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';

void main() {
  testWidgets('floating dock overlays content without shortening it', (
    tester,
  ) async {
    Future<Size> pump({required bool showDock}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 800)),
            child: Scaffold(
              body: FloatingDockLayout(
                child: const SizedBox.expand(key: Key('page-content')),
                dock: showDock
                    ? const SizedBox(
                        key: Key('test-dock'),
                        height: floatingDockHeight,
                      )
                    : null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(const Key('page-content')));
    }

    final withoutDock = await pump(showDock: false);
    final withDock = await pump(showDock: true);
    expect(withDock, withoutDock);
    expect(tester.getRect(find.byKey(const Key('test-dock'))).left, 14);
    expect(tester.getRect(find.byKey(const Key('test-dock'))).right, 346);
  });

  testWidgets('floating action stays above the dock', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FloatingDockLayout(
            child: SizedBox.expand(),
            dock: SizedBox(key: Key('test-dock'), height: floatingDockHeight),
            floatingActionButton: FloatingActionButton(
              key: Key('test-fab'),
              onPressed: null,
            ),
          ),
        ),
      ),
    );
    final fab = tester.getRect(find.byKey(const Key('test-fab')));
    final dock = tester.getRect(find.byKey(const Key('test-dock')));
    expect(fab.bottom, lessThan(dock.top));
  });
}
```

- [ ] **Step 2: 运行测试并确认缺少组件而失败**

Run: `flutter test test/shared/ui/floating_dock_layout_test.dart`

Expected: FAIL，提示 `floating_dock_layout.dart`、`FloatingDockLayout` 或常量尚不存在。

- [ ] **Step 3: 实现共享悬浮布局**

在 `lib/shared/ui/floating_dock_layout.dart` 实现以下完整公共契约。Dock 动画只作用于覆盖层，绝不能包住 `child`：

```dart
import 'package:flutter/material.dart';
import 'package:sitemark/motion.dart';

const double floatingDockHorizontalInset = 14;
const double floatingDockBottomInset = 12;
const double floatingDockHeight = 80;
const double floatingDockReservedSpace = 112;

class FloatingDockLayout extends StatelessWidget {
  const FloatingDockLayout({
    super.key,
    required this.child,
    this.dock,
    this.floatingActionButton,
    this.dockKey = const Key('floating-dock-slot'),
  });

  final Widget child;
  final Widget? dock;
  final Widget? floatingActionButton;
  final Key dockKey;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.durationOf(context, AppMotion.medium4);
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: child),
        if (floatingActionButton case final action?)
          Positioned(
            right: 16,
            bottom: bottomSafeArea + floatingDockBottomInset +
                floatingDockHeight + 12,
            child: action,
          ),
        Positioned(
          left: floatingDockHorizontalInset,
          right: floatingDockHorizontalInset,
          bottom: bottomSafeArea + floatingDockBottomInset,
          child: AnimatedSwitcher(
            key: dockKey,
            duration: duration,
            switchInCurve: AppMotion.emphasizedDecelerate,
            switchOutCurve: AppMotion.emphasizedAccelerate,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .12),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: dock ??
                const SizedBox.shrink(key: ValueKey('floating-dock-empty')),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: 写根 Dock 状态和覆盖式导航的失败测试**

在 `test/navigation/root_navigation_scaffold_test.dart` 的现有路由测试中补充：

```dart
testWidgets('root dock is an overlay and selection mode hides only that dock', (
  tester,
) async {
  await runWithRouter(tester, (_) async {
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
      isNull,
    );
    expect(find.byKey(const Key('root-dock')), findsOneWidget);

    container
        .read(allCapturesSelectionModeProvider.notifier)
        .setActive(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('root-dock')), findsNothing);

    container
        .read(allCapturesSelectionModeProvider.notifier)
        .setActive(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('root-dock')), findsOneWidget);
  });
});
```

同时在该测试文件导入 `root_chrome_controller.dart`。

- [ ] **Step 5: 实现短生命周期状态并改造根导航**

`lib/navigation/root_chrome_controller.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

final allCapturesSelectionModeProvider =
    NotifierProvider<AllCapturesSelectionModeController, bool>(
      AllCapturesSelectionModeController.new,
    );

class AllCapturesSelectionModeController extends Notifier<bool> {
  @override
  bool build() => false;

  void setActive(bool value) {
    if (state != value) state = value;
  }
}
```

把 `RootNavigationScaffold` 改为 `ConsumerWidget`，保持原路径判定，但使用如下显隐条件和布局；`NavigationBar` 外仍由 `GlassSurface` 包裹：

```dart
final recordsSelecting = ref.watch(allCapturesSelectionModeProvider);
final hideForSelection = path == '/records' && recordsSelecting;
final dock = showRootNavigation && !hideForSelection
    ? GlassSurface(
        key: const Key('root-dock'),
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: floatingDockHeight,
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
            destinations: [
              NavigationDestination(
                key: const Key('root-destination-projects'),
                icon: const Icon(Icons.domain_outlined),
                label: strings.projects,
              ),
              NavigationDestination(
                key: const Key('root-destination-records'),
                icon: const Icon(Icons.photo_library_outlined),
                label: strings.allRecords,
              ),
              NavigationDestination(
                key: const Key('root-destination-settings'),
                icon: const Icon(Icons.settings_outlined),
                label: strings.settings,
              ),
            ],
          ),
        ),
      )
    : null;

return Scaffold(
  body: FloatingDockLayout(
    child: navigationShell,
    dock: dock,
    floatingActionButton:
        showRootNavigation && navigationShell.currentIndex == 0
        ? FloatingActionButton(
            key: const Key('new-project-fab'),
            onPressed: () => context.push('/projects/new'),
            tooltip: strings.newProject,
            child: const Icon(Icons.add),
          )
        : null,
  ),
);
```

- [ ] **Step 6: 运行定向测试**

Run: `flutter test test/shared/ui/floating_dock_layout_test.dart test/navigation/root_navigation_scaffold_test.dart`

Expected: PASS；既有分支保活、搜索状态和二级页隐藏 Dock 测试仍通过。

- [ ] **Step 7: 提交任务 1**

```bash
git add lib/shared/ui/floating_dock_layout.dart lib/navigation/root_chrome_controller.dart lib/navigation/root_navigation_scaffold.dart test/shared/ui/floating_dock_layout_test.dart test/navigation/root_navigation_scaffold_test.dart
git commit -m "feat: make root navigation truly floating"
```

---

### Task 2: 把批量操作改成同位置的紧凑选择 Dock

**Files:**
- Modify: `lib/features/capture/capture_batch_action_bar.dart`
- Modify: `lib/features/capture/all_captures_screen.dart`
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `test/features/capture/motion_selection_test.dart`
- Modify: `test/features/capture/capture_batch_paged_selection_test.dart`

**Interfaces:**
- Consumes: `FloatingDockLayout`、`floatingDockHeight`、`floatingDockReservedSpace`、`allCapturesSelectionModeProvider`。
- Preserves: `CaptureBatchActionBar` 构造参数与四项业务方法，不改变服务层调用。
- Produces: `CaptureBatchActionBar` 固定高度悬浮表面；选择为 0 时仍显示但禁用操作。

- [ ] **Step 1: 写“只有一个 Dock 且列表不缩短”的失败测试**

在 `test/features/capture/motion_selection_test.dart` 的全部记录测试装配中加入：

```dart
final listHeightBefore = tester.getSize(
  find.byKey(const Key('capture-list-content')),
).height;

await tester.tap(find.byKey(const Key('edit-captures')));
await tester.pumpAndSettle();

expect(find.byKey(const Key('root-dock')), findsNothing);
expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
expect(find.byType(BottomAppBar), findsNothing);
expect(
  tester.getSize(find.byKey(const Key('capture-list-content'))).height,
  listHeightBefore,
);
expect(find.text('已选 0 张'), findsOneWidget);
```

为项目详情补充以下断言：

```dart
final projectListHeight = tester.getSize(
  find.byKey(const Key('project-capture-list-content')),
).height;
await tester.tap(find.byKey(const Key('edit-captures')));
await tester.pumpAndSettle();
final projectScaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
expect(projectScaffold.bottomNavigationBar, isNull);
expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
expect(
  tester.getSize(
    find.byKey(const Key('project-capture-list-content')),
  ).height,
  projectListHeight,
);
```

- [ ] **Step 2: 写窄屏和 3 倍字体失败测试**

在 `test/features/capture/motion_selection_test.dart` 单独挂载 `CaptureBatchActionBar`：

```dart
await tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh'),
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(360, 800),
        textScaler: TextScaler.linear(3),
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: CaptureBatchActionBar(
            controller: controller,
            mediaService: media,
            exportService: export,
            shareService: share,
          ),
        ),
      ),
    ),
  ),
);
expect(tester.takeException(), isNull);
expect(
  tester.getSize(find.byKey(const Key('batch-action-bar'))).height,
  floatingDockHeight,
);
expect(find.byTooltip('导出所选'), findsOneWidget);
expect(find.byTooltip('保存到相册'), findsOneWidget);
expect(find.byTooltip('清理原图'), findsOneWidget);
expect(find.byTooltip('全部删除'), findsOneWidget);
```

- [ ] **Step 3: 运行测试并确认旧底栏行为失败**

Run: `flutter test test/features/capture/motion_selection_test.dart test/features/capture/capture_batch_paged_selection_test.dart`

Expected: FAIL；旧实现仍使用 104/136 高的 `BottomAppBar`，且空选择不显示工具栏。

- [ ] **Step 4: 将批量栏改成固定高度玻璃 Dock**

保留 `_export`、`_republish`、`_clearOriginals`、`_deleteAll` 和确认/撤销逻辑，只替换 `build` 与按钮呈现。核心结构必须为单行，忙碌状态用左侧计数区显示进度，不增加高度：

```dart
return GlassSurface(
  key: const Key('batch-action-bar'),
  borderRadius: BorderRadius.circular(24),
  child: SizedBox(
    height: floatingDockHeight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: _busy
                ? _CompactProgress(
                    exporting: _exporting,
                    completed: _completed,
                    total: _total,
                  )
                : Text(
                    strings.selectedCount(ids.length),
                    key: const Key('batch-selected-count'),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          const VerticalDivider(indent: 16, endIndent: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  icon: Icons.archive_outlined,
                  label: strings.exportSelection,
                  enabled: !empty && ready && !_busy,
                  onPressed: _export,
                ),
                _ActionButton(
                  icon: Icons.save_outlined,
                  label: strings.saveToGallery,
                  enabled: !empty && ready && !_busy,
                  onPressed: _republish,
                ),
                _ActionButton(
                  icon: Icons.cleaning_services_outlined,
                  label: strings.clearOriginals,
                  enabled: !empty && !_busy,
                  onPressed: _clearOriginals,
                ),
                _ActionButton(
                  icon: Icons.delete_outline,
                  label: strings.deleteAll,
                  enabled: !empty && !_busy,
                  errorAction: true,
                  onPressed: _deleteAll,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
```

`_ActionButton` 只显示 `IconButton`，用 `tooltip: label`、`constraints: const BoxConstraints.tightFor(width: 48, height: 48)`；`errorAction` 时从 `Theme.of(context).colorScheme.error` 取前景色。`_CompactProgress` 使用 2dp `LinearProgressIndicator` 和单行 `actionProgress`/`exportSelection`，文字必须 `maxLines: 1`、`overflow: TextOverflow.ellipsis`。

- [ ] **Step 5: 在两个页面改为覆盖式选择 Dock**

在 `AllCapturesScreen`：

1. `_onSelectionChanged` 最后调用：

```dart
ref
    .read(allCapturesSelectionModeProvider.notifier)
    .setActive(_selectionController.editing);
```

2. `dispose` 前设回 `false`。
3. 移除 `Scaffold.bottomNavigationBar`。
4. 用 `FloatingDockLayout` 包裹原 `StreamBuilder`，选择模式即显示 `CaptureBatchActionBar`，包括已选 0 张的状态。
5. 给列表传入 `padding: const EdgeInsets.fromLTRB(16, 4, 16, floatingDockReservedSpace)`。

```dart
body: FloatingDockLayout(
  child: recordsBody,
  dock: editing
      ? CaptureBatchActionBar(
          key: const Key('batch-bar'),
          controller: _selectionController,
          mediaService: ref.watch(captureMediaServiceProvider),
          exportService: ref.watch(projectExportServiceProvider),
          shareService: ref.watch(shareFileServiceProvider),
        )
      : null,
),
```

在 `ProjectDetailScreen` 做同样替换，但无需更新根状态；非选择模式保留拍摄 FAB，选择模式隐藏拍摄 FAB。项目记录列表的底部 padding 在选择模式下使用 `floatingDockReservedSpace`，非选择模式沿用现有 96。

- [ ] **Step 6: 保留失败选择与既有成功退出规则**

在现有失败服务测试中加入以下精确断言，锁定导出/保存失败后保留选择；现有清理原图成功、删除成功、5 秒撤销和删除 ID 快照测试保持原断言不删：

```dart
expect(controller.editing, isTrue);
expect(controller.selectedIds, contains('capture-0'));
expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
```

- [ ] **Step 7: 运行定向测试**

Run: `flutter test test/features/capture/motion_selection_test.dart test/features/capture/capture_batch_paged_selection_test.dart test/navigation/root_navigation_scaffold_test.dart`

Expected: PASS；系统返回先退出选择、全选/取消全选、失败保留选择、删除快照和清理原图撤销测试均不回归。

- [ ] **Step 8: 提交任务 2**

```bash
git add lib/features/capture/capture_batch_action_bar.dart lib/features/capture/all_captures_screen.dart lib/features/projects/project_detail_screen.dart test/features/capture/motion_selection_test.dart test/features/capture/capture_batch_paged_selection_test.dart test/navigation/root_navigation_scaffold_test.dart
git commit -m "feat: replace batch bottom bar with selection dock"
```

---

### Task 3: 用当前可见日期标签替代全宽吸顶日期条

**Files:**
- Modify: `lib/features/capture/capture_paged_list.dart`
- Modify: `lib/features/capture/all_captures_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Modify: `test/features/capture/capture_search_paging_ui_test.dart`
- Modify: `test/features/capture/capture_filter_ui_test.dart`

**Interfaces:**
- Produces: `CapturePagedList.onVisibleGroupChanged: ValueChanged<String?>?`
- Preserves: `CapturePagedList.groupKey: String Function(CaptureSummary)?`
- Removes: `CapturePagedGroupHeaderBuilder` 和 `groupHeaderBuilder` 参数。
- Produces: `AppStrings.currentVisibleDate(String date)`。
- Consumes: 已有 `_captureDateKey`，日期格式保持 `yyyy-MM-dd`。

- [ ] **Step 1: 写列表可见分组回调的失败测试**

修改 `test/features/capture/capture_search_paging_ui_test.dart` 的 `_pagedHarness`，把旧 `groupHeaderBuilder` 参数替换成可注入回调。新增三天、固定 64 高记录的测试：

```dart
testWidgets('grouped list reports the topmost visible date while scrolling', (
  tester,
) async {
  final source = _FakeCaptureQuerySource(
    firstPage: _page([
      _summary(0, capturedAt: DateTime(2026, 8, 4, 12)),
      _summary(1, capturedAt: DateTime(2026, 8, 4, 11)),
      _summary(2, capturedAt: DateTime(2026, 8, 3, 12)),
      _summary(3, capturedAt: DateTime(2026, 8, 3, 11)),
      _summary(4, capturedAt: DateTime(2026, 8, 2, 12)),
    ], hasMore: false),
  );
  final controller = CapturePagerController(source, pageSize: 50);
  final reported = <String?>[];

  await tester.pumpWidget(
    _pagedHarness(
      controller,
      source,
      grouped: true,
      onVisibleGroupChanged: reported.add,
      size: const Size(360, 320),
    ),
  );
  await _pumpUntil(tester, () => reported.isNotEmpty);
  expect(reported.last, '2026-08-04');

  await tester.drag(
    find.byType(CustomScrollView),
    const Offset(0, -180),
  );
  await tester.pumpAndSettle();
  expect(reported.last, '2026-08-03');
  expect(find.byType(SliverPersistentHeader), findsNothing);
});
```

再加空列表回调一次 `null`、分页追加同日期不重复回调、查询切换后重新从顶部报告的测试。

- [ ] **Step 2: 运行测试并确认接口不存在而失败**

Run: `flutter test test/features/capture/capture_search_paging_ui_test.dart`

Expected: FAIL，提示 `onVisibleGroupChanged` 不存在，且旧实现仍渲染 `SliverPersistentHeader`。

- [ ] **Step 3: 实现基于可见记录行的分组报告**

在 `CapturePagedList` 增加：

```dart
final ValueChanged<String?>? onVisibleGroupChanged;

final GlobalKey _viewportKey = GlobalKey();
final Map<String, GlobalKey> _rowKeys = <String, GlobalKey>{};
bool _visibleGroupReportScheduled = false;
String? _lastReportedGroup;
```

构造断言改为：

```dart
assert(
  groupKey != null || onVisibleGroupChanged == null,
  'onVisibleGroupChanged requires groupKey',
),
```

给 `CustomScrollView` 设置 `key: _viewportKey`。`_onScroll` 在更新 `atTop` 后调用 `_scheduleVisibleGroupReport()`；分页状态改变、首次内容绘制和查询改变也调用它。实现必须只在帧后读取布局，并只在值改变时通知：

```dart
void _scheduleVisibleGroupReport() {
  if (_visibleGroupReportScheduled || widget.groupKey == null) return;
  _visibleGroupReportScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _visibleGroupReportScheduled = false;
    if (mounted) _reportVisibleGroup();
  });
}

void _reportVisibleGroup() {
  final callback = widget.onVisibleGroupChanged;
  final groupKey = widget.groupKey;
  if (callback == null || groupKey == null) return;
  final rows = widget.controller.state.rows;
  if (rows.isEmpty) {
    _emitVisibleGroup(null);
    return;
  }
  final viewport = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
  if (viewport == null || !viewport.attached) return;
  final viewportTop = viewport.localToGlobal(Offset.zero).dy;
  final candidates = <({double top, CaptureSummary row})>[];
  for (final row in rows) {
    final box = _rowKeys[row.capture.id]?.currentContext?.findRenderObject()
        as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) continue;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top + box.size.height > viewportTop + .5) {
      candidates.add((top: top, row: row));
    }
  }
  if (candidates.isEmpty) return;
  candidates.sort((a, b) => a.top.compareTo(b.top));
  _emitVisibleGroup(groupKey(candidates.first.row));
}

void _emitVisibleGroup(String? value) {
  if (_lastReportedGroup == value) return;
  _lastReportedGroup = value;
  widget.onVisibleGroupChanged?.call(value);
}
```

`_buildRow` 用记录 ID 保持 GlobalKey 稳定：

```dart
final summary = state.rows[index];
final rowKey = _rowKeys.putIfAbsent(summary.capture.id, GlobalKey.new);
return KeyedSubtree(
  key: rowKey,
  child: widget.itemBuilder(context, summary, state.rows),
);
```

每次分页状态改变后，只保留当前 `state.rows` 中的 key；查询身份改变时把 `_lastReportedGroup` 设回 `null`。不要在回调里 `setState` 或调用 pager。

- [ ] **Step 4: 移除可视日期条但保留跨日间距**

删除 `_CaptureGroupHeaderDelegate`、`_groupHeaderExtent` 和所有 `SliverPersistentHeader`。仍按连续 `groupKey` 构造 `_CaptureRowGroup`，每组只渲染 `SliverList.separated`；组与组之间 12dp，首组使用顶部 padding，末组使用底部 padding：

```dart
sliver: SliverList.separated(
  itemCount: groups[groupIndex].length,
  separatorBuilder: (_, _) => const SizedBox(height: 10),
  itemBuilder: (context, localIndex) => _buildRow(
    context,
    state,
    groups[groupIndex].startIndex + localIndex,
  ),
),
```

- [ ] **Step 5: 写筛选右侧日期标签的失败测试**

在 `test/features/capture/capture_filter_ui_test.dart` 把旧 `capture-date-*` 断言替换为：

```dart
expect(find.byKey(const Key('visible-capture-date')), findsOneWidget);
expect(find.text('2026-08-04'), findsOneWidget);
expect(find.byType(SliverPersistentHeader), findsNothing);

final filterRect = tester.getRect(find.byKey(const Key('filter-sheet-trigger')));
final dateRect = tester.getRect(find.byKey(const Key('visible-capture-date')));
expect(dateRect.left, greaterThan(filterRect.right));
expect((dateRect.center.dy - filterRect.center.dy).abs(), lessThan(2));
```

再添加三项测试，核心断言分别为：

```dart
// 精确日筛选优先于滚动回报。
await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
await tester.pumpAndSettle();
await tester.tap(find.byKey(const Key('filter-year-2026')));
await tester.pump();
await tester.tap(find.byKey(const Key('filter-month-8')));
await tester.pump();
await tester.tap(find.byKey(const Key('filter-day-3')));
await tester.pump();
await tester.tap(find.byKey(const Key('filter-apply')));
await tester.pumpAndSettle();
expect(find.text('2026-08-03'), findsOneWidget);

// 空结果不留下过期日期。
final emptyDatabase = AppDatabase.forTesting(NativeDatabase.memory());
addTearDown(emptyDatabase.close);
await emptyDatabase.createProject(id: 'empty-project', name: '空项目');
await tester.pumpWidget(pumpAllCaptures(emptyDatabase));
await tester.pumpAndSettle();
expect(find.byKey(const Key('visible-capture-date')), findsNothing);

// 仅年/月筛选不固定到某天，仍接受滚动回报。
await tester.pumpWidget(pumpAllCaptures(database));
await tester.pumpAndSettle();
await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
await tester.pumpAndSettle();
await tester.tap(find.byKey(const Key('filter-year-2026')));
await tester.pump();
await tester.tap(find.byKey(const Key('filter-month-8')));
await tester.pump();
await tester.tap(find.byKey(const Key('filter-apply')));
await tester.pumpAndSettle();
await tester.drag(find.byType(CustomScrollView), const Offset(0, -240));
await tester.pumpAndSettle();
expect(find.text('2026-08-03'), findsOneWidget);
```

- [ ] **Step 6: 在全部记录页显示动态日期**

新增状态和格式化 getter：

```dart
String? _visibleDateKey;

String? get _exactFilteredDateKey {
  final year = _filter.year;
  final month = _filter.month;
  final day = _filter.day;
  if (year == null || month == null || day == null) return null;
  String two(int value) => value.toString().padLeft(2, '0');
  return '$year-${two(month)}-${two(day)}';
}

void _onVisibleDateChanged(String? value) {
  if (_visibleDateKey == value || !mounted) return;
  setState(() => _visibleDateKey = value);
}
```

把 `CapturePagedList` 参数改为：

```dart
groupKey: _captureDateKey,
onVisibleGroupChanged: _onVisibleDateChanged,
```

删除 `_buildDateHeader`。在 `_filterBar` 的 `Row` 中，筛选按钮后用 `Expanded` 容纳现有 active chips，最右显示 `_exactFilteredDateKey ?? _visibleDateKey`：

```dart
if (dateKey != null) ...[
  const SizedBox(width: 8),
  Semantics(
    label: strings.currentVisibleDate(dateKey),
    child: Text(
      dateKey,
      key: const Key('visible-capture-date'),
      maxLines: 1,
      overflow: TextOverflow.fade,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
],
```

当查询切换时先将 `_visibleDateKey = null`，等待列表回报新日期；这只改变页面显示状态，不触发 `_startQuery()`。

在 `AppStrings` 增加：

```dart
String currentVisibleDate(String date) =>
    _english ? 'Current visible date: $date' : '当前可见日期：$date';
```

- [ ] **Step 7: 运行日期与筛选测试**

Run: `flutter test test/features/capture/capture_search_paging_ui_test.dart test/features/capture/capture_filter_ui_test.dart`

Expected: PASS；滚动跨天更新、精确日固定、空列表隐藏、分页连续性、筛选级联和加载更多均通过。

- [ ] **Step 8: 提交任务 3**

```bash
git add lib/features/capture/capture_paged_list.dart lib/features/capture/all_captures_screen.dart lib/l10n/app_strings.dart test/features/capture/capture_search_paging_ui_test.dart test/features/capture/capture_filter_ui_test.dart
git commit -m "feat: show visible date beside capture filters"
```

---

### Task 4: 为项目详情增加稳定的轻量返回转场

**Files:**
- Modify: `lib/navigation/route_transitions.dart`
- Modify: `lib/app.dart`
- Modify: `test/navigation/route_transitions_test.dart`
- Modify: `test/features/projects/project_list_screen_test.dart`

**Interfaces:**
- Produces: `buildProjectDetailRouteTransition({required BuildContext context, required Animation<double> animation, required Widget child})`
- Produces: `_projectDetailPage(GoRouterState state, Widget child)`。
- Preserves: `_captureDetailPage`、`buildCaptureDetailRouteTransition` 和照片 Hero tag。
- Removes: 已不再需要的 `shouldFreezeProjectCaptureList` 及其“imperative photo push”单元测试；新项目详情转场不读取 `secondaryAnimation`，被照片页覆盖时天然保持最终绘制状态。

- [ ] **Step 1: 写项目详情转场失败测试**

在 `test/navigation/route_transitions_test.dart` 新增：

```dart
testWidgets('project detail uses clipped slide and fade without shared axis', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => buildProjectDetailRouteTransition(
          context: context,
          animation: const AlwaysStoppedAnimation(.5),
          child: const SizedBox(key: Key('project-detail-content')),
        ),
      ),
    ),
  );

  expect(find.byType(ClipRect), findsWidgets);
  expect(find.byType(SlideTransition), findsOneWidget);
  expect(find.byType(FadeTransition), findsOneWidget);
  expect(find.byType(SharedAxisTransition), findsNothing);
  expect(find.byType(ScaleTransition), findsNothing);
});

testWidgets('reduce motion returns project detail child directly', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) => buildProjectDetailRouteTransition(
            context: context,
            animation: const AlwaysStoppedAnimation(.5),
            child: const SizedBox(key: Key('project-detail-content')),
          ),
        ),
      ),
    ),
  );
  expect(find.byType(SlideTransition), findsNothing);
  expect(find.byKey(const Key('project-detail-content')), findsOneWidget);
});
```

- [ ] **Step 2: 运行测试并确认函数缺失而失败**

Run: `flutter test test/navigation/route_transitions_test.dart`

Expected: FAIL，提示 `buildProjectDetailRouteTransition` 未定义。

- [ ] **Step 3: 实现项目详情专用转场**

在 `route_transitions.dart` 增加：

```dart
Widget buildProjectDetailRouteTransition({
  required BuildContext context,
  required Animation<double> animation,
  required Widget child,
}) {
  if (MediaQuery.disableAnimationsOf(context)) return child;
  final curved = CurvedAnimation(
    parent: animation,
    curve: AppMotion.emphasizedDecelerate,
    reverseCurve: AppMotion.emphasizedAccelerate,
  );
  return ClipRect(
    child: FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.045, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    ),
  );
}
```

完整淡入淡出确保返回时项目详情连续消失，底层项目首页平稳显现；`ClipRect` 防止退出页内容横向绘制到屏幕外形成“一排照片闪过”。

- [ ] **Step 4: 在路由中只替换项目详情页**

在 `app.dart` 增加：

```dart
CustomTransitionPage<void> _projectDetailPage(
  GoRouterState state,
  Widget child,
) => CustomTransitionPage<void>(
  key: state.pageKey,
  transitionDuration: AppMotion.medium2,
  reverseTransitionDuration: AppMotion.medium2,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      buildProjectDetailRouteTransition(
        context: context,
        animation: animation,
        child: child,
      ),
  child: child,
);
```

只把 `/projects/:projectId` 的 `pageBuilder` 从 `_sharedAxisPage` 改为 `_projectDetailPage`。项目设置、拍摄表单、记录详情和编辑页保持原转场。删除 `shouldFreezeProjectCaptureList` 和对应的 imperative-push 测试；`buildSharedAxisRouteTransition` / `buildFadeThroughRouteTransition` 的通用 `freezeSecondary` 参数及既有测试保留，不在本轮扩大清理范围。

- [ ] **Step 5: 增加返回中间帧稳定性回归测试**

在 `test/features/projects/project_list_screen_test.dart` 使用现有数据库/路由装配：

1. 项目卡片准备三张最近照片；
2. 记录项目卡片和三个缩略图的 Element；
3. 进入项目详情并返回，只 pump 一半 `AppMotion.pageTransition`；
4. 断言项目卡片仍是同一个 Element，`project-list-skeleton` 不出现，`project-thumbnail-placeholder-capture-1/2/3` 均不出现；
5. 完成动画后再次断言三个缩略图存在且没有测试异常。

核心断言：

```dart
final cardElementBefore = tester.element(
  find.byKey(const Key('project-card-project-1')),
);
router.pop();
await tester.pump(
  Duration(milliseconds: AppMotion.pageTransition.inMilliseconds ~/ 2),
);
expect(find.byKey(const Key('project-list-skeleton')), findsNothing);
expect(
  find.byKey(const Key('project-thumbnail-placeholder-capture-1')),
  findsNothing,
);
expect(
  find.byKey(const Key('project-thumbnail-placeholder-capture-2')),
  findsNothing,
);
expect(
  find.byKey(const Key('project-thumbnail-placeholder-capture-3')),
  findsNothing,
);
expect(
  identical(
    tester.element(find.byKey(const Key('project-card-project-1'))),
    cardElementBefore,
  ),
  isTrue,
);
await tester.pumpAndSettle();
expect(tester.takeException(), isNull);
```

项目卡片的生产 key 已由 `ProjectListScreen` 定义为 `Key('project-card-${summary.project.id}')`，本测试固定使用 `const Key('project-card-project-1')`，不得为了测试新增重复业务 key。

- [ ] **Step 6: 运行转场与项目列表测试**

Run: `flutter test test/navigation/route_transitions_test.dart test/features/projects/project_list_screen_test.dart`

Expected: PASS；项目详情使用新转场，照片详情原有连续淡出/冻结列表测试仍通过。

- [ ] **Step 7: 提交任务 4**

```bash
git add lib/navigation/route_transitions.dart lib/app.dart test/navigation/route_transitions_test.dart test/features/projects/project_list_screen_test.dart
git commit -m "fix: stabilize project detail return transition"
```

---

### Task 5: 集成回归、可访问性和文档收尾

**Files:**
- Modify: `README.md`
- Modify: `test/features/capture/capture_filter_ui_test.dart`
- Modify: `test/features/capture/motion_selection_test.dart`
- Modify: `test/navigation/back_navigation_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4 的最终接口。
- Produces: 三项真机问题的端到端回归覆盖与准确 README 描述。

- [ ] **Step 1: 增加最后一条记录不被 Dock 遮挡的测试**

在 `capture_filter_ui_test.dart` 用 360×640 视口加载足够记录，滚动到底后比较最后卡片和选择 Dock/根 Dock：

```dart
await tester.dragUntilVisible(
  find.byKey(const Key('capture-card-capture-last')),
  find.byType(CustomScrollView),
  const Offset(0, -240),
);
final lastCard = tester.getRect(find.byKey(const ValueKey('capture-last')));
final dock = tester.getRect(find.byKey(const Key('root-dock')));
expect(lastCard.bottom, lessThanOrEqualTo(dock.top));
```

选择模式再重复一次，目标改为 `batch-action-bar`。若生产卡片使用 `ValueKey(id)`，断言同样使用该现有 key。

- [ ] **Step 2: 增加语义与返回顺序测试**

在 `motion_selection_test.dart` 使用 `tester.ensureSemantics()`，确认四个图标按钮均能通过 tooltip/语义名称找到；在 `back_navigation_test.dart` 验证：

```dart
await tester.tap(find.byKey(const Key('edit-captures')));
await tester.pumpAndSettle();
await tester.binding.handlePopRoute();
await tester.pumpAndSettle();
expect(find.byKey(const Key('batch-action-bar')), findsNothing);
expect(find.byType(AllCapturesScreen), findsOneWidget);
expect(find.byKey(const Key('root-dock')), findsOneWidget);
```

再验证搜索、筛选仍按既有 LIFO 顺序处理，不能因为根 Dock 状态新增一次页面返回。

- [ ] **Step 3: 运行集成测试并修正发现的精确回归**

Run: `flutter test test/features/capture/capture_filter_ui_test.dart test/features/capture/motion_selection_test.dart test/navigation/back_navigation_test.dart test/navigation/root_navigation_scaffold_test.dart`

Expected: PASS；无 overflow、无重复 Dock、返回顺序不变。

- [ ] **Step 4: 更新 README 的现状描述**

只改“从早期版本累计完成的改进”表格中的三处，保持版本号与下载链接不动：

```markdown
| 一级导航 | “项目 / 全部记录 / 设置”通过真正覆盖在内容上方的悬浮 Dock 切换，并分别保留列表、搜索和筛选状态；进入详情等二级页面后 Dock 隐藏 |
| 记录 | 缩略图列表在筛选右侧显示当前可见日期；详情支持“成片 / 原图”和“现场记录 / 文件信息”切换，点击照片可进入相邻照片全屏浏览；支持编辑、删除和再次保存 |
| 批量操作 | 多选时以同位置的紧凑悬浮 Dock 替换一级导航，可按当前筛选结果全选/取消全选、导出、再次保存、清理原图和删除整条记录 |
```

- [ ] **Step 5: 运行格式与全量 Flutter 门禁**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Expected: `dart format` exit 0；`flutter analyze` 输出 `No issues found!`；全部 Flutter 测试通过。

- [ ] **Step 6: 运行 Rust、Android 和 APK 门禁**

Run:

```bash
cargo fmt --manifest-path rust_builder/cargokit/build_tool/Cargo.toml --check
cargo clippy --manifest-path rust_builder/cargokit/build_tool/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust_builder/cargokit/build_tool/Cargo.toml
cd android && ./gradlew testDebugUnitTest && cd ..
flutter build apk --debug
```

Expected: Rust fmt/clippy/tests 全通过；Android `BUILD SUCCESSFUL`；debug APK 生成在 `build/app/outputs/flutter-apk/app-debug.apk`。

- [ ] **Step 7: 真机人工验收清单**

在小米 15 上逐项检查并把结果写进 PR 描述：

1. 项目首页在列表顶部、中段、末尾分别进入项目详情再返回，动画开始/中间/结束均无照片横排闪过、骨架屏或占位图。
2. 项目、全部记录、设置三页的 Dock 四周均能看到页面背景，无贯穿屏幕的底色或分割线。
3. 全部记录跨越至少两个日期滚动，筛选右侧日期准确变化；精确筛选某天后固定不变。
4. 进入选择模式前后，可见记录区域高度基本不变，底部只有一块 Dock；已选 0、1、10 张都无跳高。
5. 四个批量操作、全选/取消全选、顶部完成和系统返回行为正确。
6. 滚到列表末尾，最后一张卡片可以完整停在 Dock 上方。
7. 系统开启“移除动画”后，Dock 和项目返回不出现位移/淡入，但功能正常。

- [ ] **Step 8: 检查改动边界并提交收尾**

Run:

```bash
git diff --check
git status --short
git diff --stat origin/main...HEAD
```

Expected: 无空白错误；没有数据库迁移、版本号、Rust 业务逻辑、Android 平台桥接和照片 Hero 文件的意外改动。

```bash
git add README.md test/features/capture/capture_filter_ui_test.dart test/features/capture/motion_selection_test.dart test/navigation/back_navigation_test.dart
git commit -m "docs: document floating record controls"
```

---

## 最终验收门槛

- [ ] 普通 Dock 不再位于任何 `Scaffold.bottomNavigationBar`。
- [ ] 全部记录和项目详情的选择 Dock 不再位于 `Scaffold.bottomNavigationBar`。
- [ ] 普通 Dock 与选择 Dock 从未同时出现。
- [ ] 选择模式已选 0 张时仍有稳定的上下文 Dock，操作按钮禁用。
- [ ] 选择忙碌状态高度不变，不增加第二行大面板。
- [ ] 日期条与 `SliverPersistentHeader` 从记录列表移除。
- [ ] 可见日期回调只在分组变化时通知，不发起查询或滚动。
- [ ] 精确日期筛选优先于滚动回报。
- [ ] 项目详情只使用专用 Clip + Slide + Fade 转场，无 Scale/SharedAxis。
- [ ] 照片详情 Hero 路由和 tag 未改动。
- [ ] 360dp / 3 倍字体、减少动画、系统返回、列表末项避让均有自动化覆盖。
- [ ] Flutter、Rust、Android 和 debug APK 全部门禁通过。
