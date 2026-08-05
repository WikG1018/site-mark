# SiteMark 导航动效与批量操作栏修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 根治“全部记录 → 项目 → 项目详情 → 返回”时的照片列表串帧，并增加根页面左右滑动、Dock 玻璃滑块和无框批量操作项。

**Architecture:** 项目详情回到项目分支自己的 Navigator，避免根级转场暴露其他分支。根分支容器使用保活的 `Offstage` 子树，只在 Dock 切换期间绘制来源页与目标页；Dock 使用单一移动玻璃指示器。批量操作业务逻辑保持不变，只替换操作项的视觉表面。

**Tech Stack:** Flutter 3.44、Dart 3.12、go_router、Riverpod、flutter_test

## Global Constraints

- 不增加手指横向拖动切页。
- 根页面的搜索、筛选、滚动位置和加载状态必须保留。
- 页面滑动与 Dock 指示器使用 `AppMotion.rootSwitch`，并尊重 `MediaQuery.disableAnimations`。
- Dock 指示器不得增加第二层 `BackdropFilter`。
- 批量操作的导出、保存、清理、删除、确认、撤销和进度逻辑不得改变。
- 本计划不修改版本号、不打标签、不发布版本。

---

## 文件结构

- `lib/app.dart`：调整项目详情所属 Navigator。
- `lib/navigation/root_navigation_scaffold.dart`：根分支保活、左右转场和非参与分支隔离。
- `lib/navigation/root_navigation_dock.dart`：单一玻璃滑块及选中颜色动画。
- `lib/features/capture/capture_batch_action_bar.dart`：透明无框操作项。
- `test/navigation/root_navigation_scaffold_test.dart`：真实 Dock 路径、逐帧 Offstage 和页面方向测试。
- `test/navigation/root_navigation_dock_test.dart`：玻璃滑块移动和减少动画测试。
- `test/features/capture/motion_selection_test.dart`：批量操作栏视觉契约测试。

---

### Task 1: 将项目详情隔离到项目分支 Navigator

**Files:**
- Modify: `lib/app.dart:474-490`
- Modify: `test/navigation/root_navigation_scaffold_test.dart`

**Interfaces:**
- Consumes: `rootNavigatorKey`、`routerProvider`、`ProjectDetailScreen`
- Produces: 项目详情由项目分支 Navigator 承载，根 Dock 仍按 URI 隐藏

- [ ] **Step 1: 写出失败的导航层级测试**

在 `test/navigation/root_navigation_scaffold_test.dart` 使用真实 Dock 点击路径，断言项目详情不属于根 Navigator：

```dart
testWidgets(
  'project detail stays inside the projects branch navigator',
  (tester) async {
    await runWithRouter(tester, (_) async {
      await tester.tap(find.byKey(const Key('root-destination-records')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('root-destination-projects')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-card-project-1')));
      await tester.pumpAndSettle();

      final detailContext = tester.element(find.byType(ProjectDetailScreen));
      expect(
        Navigator.of(detailContext),
        isNot(same(rootNavigatorKey.currentState)),
      );
    });
  },
);
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run:

```powershell
flutter test test/navigation/root_navigation_scaffold_test.dart --plain-name "project detail stays inside the projects branch navigator"
```

Expected: FAIL，因为 `ProjectDetailScreen` 当前仍使用 `rootNavigatorKey`。

- [ ] **Step 3: 实施最小导航层级修复**

在 `lib/app.dart` 的 `projects/:projectId` 路由上移除 `parentNavigatorKey: rootNavigatorKey`，保留 `_projectDetailPage` 及所有现有子路由。

- [ ] **Step 4: 再次运行目标测试并确认通过**

Run:

```powershell
flutter test test/navigation/root_navigation_scaffold_test.dart --plain-name "project detail stays inside the projects branch navigator"
```

Expected: PASS，项目详情的最近 Navigator 不再是 `rootNavigatorKey.currentState`。

- [ ] **Step 5: 提交导航层级修复**

```powershell
git add lib/app.dart test/navigation/root_navigation_scaffold_test.dart
git commit -m "fix: isolate project detail navigation"
```

---

### Task 2: 根页面保活左右滑动且隔离非参与分支

**Files:**
- Modify: `lib/navigation/root_navigation_scaffold.dart:75-107`
- Modify: `test/navigation/root_navigation_scaffold_test.dart`

**Interfaces:**
- Consumes: `currentIndex: int`、`children: List<Widget>`、`AppMotion.rootSwitch`
- Produces: `RootBranchContainer`，保留所有子树状态，只绘制当前页及切换中的来源页

- [ ] **Step 1: 增加方向、结束隔离和减少动画失败测试**

先增加真实返回路径测试：`全部记录 → 项目 → 项目详情 → 返回`，在返回动画开始、中间和结束帧均通过 `AllCapturesScreen` 的 `Offstage` 祖先断言照片列表未绘制。

```dart
void expectRecordsBranchOffstage(WidgetTester tester) {
  final records = find.byType(AllCapturesScreen, skipOffstage: false);
  expect(records, findsOneWidget);
  final offstage = tester.widgetList<Offstage>(
    find.ancestor(
      of: records,
      matching: find.byType(Offstage, skipOffstage: false),
    ),
  );
  expect(offstage.any((widget) => widget.offstage), isTrue);
}
```

再增加正向 `0 → 1` 与反向 `2 → 0` 测试。半程时读取来源页与目标页的 `FractionalTranslation.translation.dx`：正向来源小于 0、目标大于 0；反向符号相反。动画结束后，来源页祖先 `Offstage.offstage` 必须为 true。减少动画模式下一次 `pump()` 后只有目标页非 Offstage。

```dart
Finder branchTranslation(String key) => find.ancestor(
  of: find.byKey(Key(key), skipOffstage: false),
  matching: find.byType(FractionalTranslation, skipOffstage: false),
);

final from = tester.widget<FractionalTranslation>(
  branchTranslation('indexed-branch-0'),
);
final to = tester.widget<FractionalTranslation>(
  branchTranslation('indexed-branch-1'),
);
expect(from.translation.dx, lessThan(0));
expect(to.translation.dx, greaterThan(0));
```

- [ ] **Step 2: 运行新增测试并确认失败**

```powershell
flutter test test/navigation/root_navigation_scaffold_test.dart
```

Expected: FAIL，因为当前 `IndexedStack` 没有方向位移，也没有显式 `Offstage` 包装。

- [ ] **Step 3: 将 `RootBranchContainer` 改为受控的保活转场容器**

将其改为 `StatefulWidget`，用 `AnimationController` 保存 `_fromIndex` 和 `_currentIndex`。`didUpdateWidget` 在索引变化时记录来源与目标；减少动画时把控制器直接置为 1，否则从 0 播放。

在 `AnimatedBuilder` 中使用 `Stack + Offstage` 保活所有分支：
- 动画期间只有来源页与目标页 `offstage == false`。
- 动画结束后只有目标页可见。
- 目标页位移从 `direction * 0.08` 到 0。
- 来源页位移从 0 到 `-direction * 0.04`。
- 只有目标页启用 `TickerMode`、点击和语义。
- 外层使用 `ClipRect`，防止页面越界绘制。

- [ ] **Step 4: 运行根导航测试并确认全部通过**

```powershell
flutter test test/navigation/root_navigation_scaffold_test.dart
```

Expected: PASS，包括真实返回路径的开始、中间和结束帧均保持“全部记录”分支 Offstage。

- [ ] **Step 5: 提交根页面转场**

```powershell
git add lib/navigation/root_navigation_scaffold.dart test/navigation/root_navigation_scaffold_test.dart
git commit -m "feat: slide preserved root branches"
```

---

### Task 3: Dock 单一玻璃滑块跟随移动

**Files:**
- Modify: `lib/navigation/root_navigation_dock.dart`
- Create: `test/navigation/root_navigation_dock_test.dart`

**Interfaces:**
- Consumes: `selectedIndex: int`、`onDestinationSelected: ValueChanged<int>`
- Produces: key 为 `root-dock-glass-indicator` 的唯一移动指示器

- [ ] **Step 1: 写出玻璃滑块失败测试**

```dart
testWidgets('dock uses one glass indicator that moves with selection', (
  tester,
) async {
  var selected = 0;
  await tester.pumpWidget(buildDock(selected, (value) => selected = value));
  expect(find.byKey(const Key('root-dock-glass-indicator')), findsOneWidget);
  expect(
    find.byKey(const Key('root-destination-projects-selected-surface')),
    findsNothing,
  );

  final before = tester.getCenter(
    find.byKey(const Key('root-dock-glass-indicator')),
  );
  await tester.tap(find.byKey(const Key('root-destination-records')));
  await tester.pumpWidget(buildDock(selected, (value) => selected = value));
  await tester.pump(AppMotion.rootSwitch ~/ 2);
  final during = tester.getCenter(
    find.byKey(const Key('root-dock-glass-indicator')),
  );
  expect(during.dx, greaterThan(before.dx));
});
```

另断言 `RootNavigationDock` 子树中没有 `BackdropFilter`，并验证减少动画时滑块一次 `pump()` 即到目标中心。

- [ ] **Step 2: 运行测试并确认失败**

```powershell
flutter test test/navigation/root_navigation_dock_test.dart
```

Expected: FAIL，因为当前选中背景属于各按钮自己的 `AnimatedContainer`。

- [ ] **Step 3: 实现单一移动玻璃指示器**

用 `Stack + AnimatedAlign + FractionallySizedBox(widthFactor: 1 / 3)` 将一个 `DecoratedBox` 放在按钮 Row 后方。对齐值使用 `Alignment(-1 + selectedIndex.toDouble(), 0)`，时长使用 `AppMotion.durationOf(context, AppMotion.rootSwitch)`。装饰使用约 32% 的 surface 高光、12% 的 onSurface 细边框和轻阴影，不使用 `BackdropFilter`。

删除 `_RootDestinationButton` 内部选中背景，只保留透明 `Material`、`InkWell`、居中图标文字和前景颜色动画。

- [ ] **Step 4: 运行 Dock 与根导航测试**

```powershell
flutter test test/navigation/root_navigation_dock_test.dart test/navigation/root_navigation_scaffold_test.dart
```

Expected: PASS；滑块唯一、方向正确、无嵌套模糊、无障碍标签仍存在。

- [ ] **Step 5: 提交 Dock 玻璃滑块**

```powershell
git add lib/navigation/root_navigation_dock.dart test/navigation/root_navigation_dock_test.dart test/navigation/root_navigation_scaffold_test.dart
git commit -m "feat: slide the root dock glass indicator"
```

---

### Task 4: 恢复无框玻璃批量操作栏

**Files:**
- Modify: `lib/features/capture/capture_batch_action_bar.dart:333-516`
- Modify: `test/features/capture/motion_selection_test.dart`

**Interfaces:**
- Consumes: 现有 `_ActionButton` 参数与四个业务回调
- Produces: `batch-action-<name>-surface` 透明操作表面

- [ ] **Step 1: 增加透明表面失败测试**

```dart
for (final name in ['export', 'gallery', 'originals', 'delete']) {
  final surface = tester.widget<Material>(
    find.byKey(Key('batch-action-$name-surface')),
  );
  expect(surface.color, Colors.transparent);
}
expect(find.text('导出所选'), findsOneWidget);
expect(find.text('保存到相册'), findsOneWidget);
expect(find.text('清理原图'), findsOneWidget);
expect(find.text('全部删除'), findsOneWidget);
```

- [ ] **Step 2: 运行测试并确认失败**

```powershell
flutter test test/features/capture/motion_selection_test.dart
```

Expected: FAIL，因为现有四个操作项使用独立填充色，且尚无稳定表面 key。

- [ ] **Step 3: 将四个操作项改为透明无框**

为 `_ActionButton` 增加 `actionKey`，四个调用分别传入 `export`、`gallery`、`originals`、`delete`。按钮主体使用：

```dart
Material(
  key: Key('batch-action-$actionKey-surface'),
  color: Colors.transparent,
  child: InkWell(
    onTap: enabled ? onPressed : null,
    borderRadius: BorderRadius.circular(12),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21, color: foreground),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, textAlign: TextAlign.center),
        ],
      ),
    ),
  ),
)
```

正常前景使用 `onSurfaceVariant`，删除使用 `error`，禁用使用 `onSurface` 的 38% 透明度。移除所有单项背景色计算，保留 Tooltip、Semantics 和现有业务回调。

- [ ] **Step 4: 运行批量操作相关测试**

```powershell
flutter test test/features/capture/motion_selection_test.dart test/features/capture/capture_batch_paged_selection_test.dart
```

Expected: PASS；四项文字可见、表面透明、原有点击与选择行为不变。

- [ ] **Step 5: 提交操作栏视觉修复**

```powershell
git add lib/features/capture/capture_batch_action_bar.dart test/features/capture/motion_selection_test.dart
git commit -m "fix: restore transparent batch actions"
```

---

### Task 5: 完整验证与 PR 准备

**Files:**
- Verify: Tasks 1-4 的全部变更
- Modify: 仅允许修正验证发现且属于本次范围的问题

**Interfaces:**
- Consumes: Tasks 1-4 的提交
- Produces: 可审查、可合并但未发布的修复分支

- [ ] **Step 1: 格式化并检查差异**

```powershell
dart format lib/app.dart lib/navigation/root_navigation_scaffold.dart lib/navigation/root_navigation_dock.dart lib/features/capture/capture_batch_action_bar.dart test/navigation/root_navigation_scaffold_test.dart test/navigation/root_navigation_dock_test.dart test/features/capture/motion_selection_test.dart
git diff --check
```

Expected: 没有格式或空白错误。

- [ ] **Step 2: 运行全部 Flutter 检查**

```powershell
flutter analyze
flutter test
```

Expected: `No issues found`，全部测试通过，数量不少于基线 886。

- [ ] **Step 3: 运行原生与构建检查**

```powershell
cargo fmt --manifest-path rust/Cargo.toml --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
./android/gradlew -p android :sitemark_system_api:testDebugUnitTest
flutter build apk --debug
```

Expected: Rust、Android 单测和调试 APK 构建全部成功。

- [ ] **Step 4: 审查最终差异与仓库状态**

```powershell
git status --short
git diff main...HEAD --stat
git log --oneline main..HEAD
```

Expected: 只包含设计、计划、导航、Dock、批量操作栏及对应测试；没有版本号或发布文件变更。

- [ ] **Step 5: 推送并创建 PR**

推送 `fix/v1-navigation-polish`，创建以 `main` 为基线的 PR。PR 正文必须列出真实复现路径、三项视觉行为、完整验证结果，并明确“不包含版本发布”。
