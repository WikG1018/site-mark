# 导航、搜索与图片飞行稳定性实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保留记录图片 Hero 飞行效果，同时消除返回闪烁、首页搜索双取消按钮和返回跳过上一页的问题。

**Architecture:** 首页搜索采用单一状态动作和稳定的 AppBar 标题布局；所有用户主动进入下一级页面的动作统一使用 `push`，完成业务操作后才使用 `go`；记录图片的 Hero 被收口到一个稳定飞行组件，飞行时复用同一图片提供者并避开异步淡入层。记录详情路由使用独立的 300ms 横向位移转场，Hero 的图片飞行不再与详情页自身的透明度动画叠加。

**Tech Stack:** Flutter、Material 3、go_router、Riverpod、flutter_test

## Global Constraints

- 保留记录缩略图进入详情、从详情返回缩略图的 Hero 飞行效果。
- 全屏图片查看的缩放、平移和下拉关闭行为不得改变。
- 用户主动进入详情、编辑、表单和设置二级页时使用 `push`；返回使用 `pop`。
- 仅保存成功、删除成功、顶级目的地切换等明确业务落点使用 `go`。
- 编辑页返回只取消本次编辑，不写入数据，并回到刚才的记录详情。
- 搜索状态只显示一个取消动作：有内容时清空内容，无内容时退出搜索。
- 不新增第三方依赖，不修改数据库结构，不改变照片文件格式和存储位置。

---

### Task 1: 首页搜索单按钮与稳定标题

**Files:**
- Modify: `lib/features/projects/project_list_screen.dart`
- Test: `test/features/projects/project_list_screen_test.dart`

**Interfaces:**
- Consumes: `_query`、`_searchController`、`_searchFocus` 和 `_searching`
- Produces: `_handleSearchAction()`；搜索状态中唯一的 `Key('project-search-action')`

- [ ] **Step 1: 写入先失败的搜索行为测试**

在 `test/features/projects/project_list_screen_test.dart` 中替换依赖 `clear-project-search`、`close-project-search` 的断言，并增加以下测试：

```dart
testWidgets('search exposes one action that clears then exits', (tester) async {
  await pumpProjects(tester);
  await tester.tap(find.byKey(const Key('search-projects')));
  await tester.pump();

  expect(find.byKey(const Key('project-search-action')), findsOneWidget);
  expect(find.byIcon(Icons.clear), findsOneWidget);
  expect(find.byIcon(Icons.close), findsNothing);

  await tester.enterText(
    find.byKey(const Key('project-search-field')),
    '东区',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('project-search-action')));
  await tester.pump();

  expect(
    tester
        .widget<TextField>(find.byKey(const Key('project-search-field')))
        .controller!
        .text,
    isEmpty,
  );
  expect(find.byKey(const Key('project-search-field')), findsOneWidget);

  await tester.tap(find.byKey(const Key('project-search-action')));
  await tester.pump();

  expect(find.byKey(const Key('project-search-field')), findsNothing);
  expect(find.byKey(const Key('project-title')), findsOneWidget);
  await disposeApp(tester);
});

testWidgets('search title swap does not use AnimatedSwitcher', (tester) async {
  await pumpProjects(tester);
  final appBar = find.byType(AppBar);
  expect(
    find.descendant(of: appBar, matching: find.byType(AnimatedSwitcher)),
    findsNothing,
  );

  await tester.tap(find.byKey(const Key('search-projects')));
  await tester.pump();
  expect(
    find.descendant(of: appBar, matching: find.byType(AnimatedSwitcher)),
    findsNothing,
  );
  await disposeApp(tester);
});
```

- [ ] **Step 2: 运行搜索测试并确认按预期失败**

Run:

```powershell
flutter test test/features/projects/project_list_screen_test.dart
```

Expected: FAIL，因为 `project-search-action` 尚不存在，且 AppBar 标题中仍存在 `AnimatedSwitcher`。

- [ ] **Step 3: 实现单一搜索动作**

在 `lib/features/projects/project_list_screen.dart` 中加入：

```dart
void _handleSearchAction() {
  if (_query.isNotEmpty) {
    _searchController.clear();
    setState(() => _query = '');
    _searchFocus.requestFocus();
    return;
  }
  _closeSearch();
}
```

将 AppBar 的 `title` 改为不带交叉淡入的稳定布局：

```dart
title: SizedBox(
  height: kToolbarHeight,
  child: Align(
    alignment: Alignment.centerLeft,
    child: _searching
        ? TextField(
            key: const Key('project-search-field'),
            controller: _searchController,
            focusNode: _searchFocus,
            decoration: InputDecoration(
              hintText: strings.searchProjectsHint,
              border: InputBorder.none,
            ),
            onChanged: (value) => setState(() => _query = value),
          )
        : Text(strings.appName, key: const Key('project-title')),
  ),
),
```

将搜索状态中的两个按钮替换为一个：

```dart
if (_searching)
  IconButton(
    key: const Key('project-search-action'),
    onPressed: _handleSearchAction,
    tooltip: _query.isNotEmpty ? strings.clear : strings.cancel,
    icon: Icon(_query.isNotEmpty ? Icons.clear : Icons.close),
  )
else ...[
  // 保留现有搜索、全部记录、设置按钮。
]
```

- [ ] **Step 4: 运行搜索测试并确认通过**

Run:

```powershell
flutter test test/features/projects/project_list_screen_test.dart
```

Expected: PASS，搜索状态始终只有一个动作，先清空再退出，标题布局中没有 `AnimatedSwitcher`。

- [ ] **Step 5: 提交搜索修复**

```powershell
git add lib/features/projects/project_list_screen.dart test/features/projects/project_list_screen_test.dart
git commit -m "fix: simplify project search interaction"
```

---

### Task 2: 统一导航历史与返回语义

**Files:**
- Modify: `lib/features/projects/project_list_screen.dart`
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `lib/features/settings/global_settings_screen.dart`
- Modify: `lib/features/capture/capture_detail_screen.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: go_router 的 `BuildContext.push(String)`、`BuildContext.go(String)` 和 Navigator 的默认 `pop`
- Produces: 项目、拍摄表单、项目设置、记录详情、记录编辑和设置二级页的可逆导航历史

- [ ] **Step 1: 写入先失败的导航历史测试**

在 `test/widget_test.dart` 中复用现有 `pumpAppWithRecords`、`seedReadyCapture` 和生产 `MyApp` 路由，加入：

```dart
testWidgets('project details pop back to the project list', (tester) async {
  await pumpAppWithRecords(tester);

  await tester.tap(find.text('东区厂房改造'));
  await tester.pumpAndSettle();
  expect(find.text('拍摄记录'), findsOneWidget);

  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('search-projects')), findsOneWidget);
  expect(find.text('东区厂房改造'), findsOneWidget);
  await disposeApp(tester);
});

testWidgets('capture form pop returns to its project', (tester) async {
  await pumpAppWithRecords(tester);
  await tester.tap(find.text('东区厂房改造'));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('capture-fab')));
  await tester.pumpAndSettle();
  expect(find.text('新拍摄'), findsOneWidget);

  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  expect(find.text('拍摄记录'), findsOneWidget);
  expect(find.text('东区厂房改造'), findsOneWidget);
  await disposeApp(tester);
});

testWidgets('record edit cancellation preserves the records origin', (
  tester,
) async {
  await pumpAppWithRecords(tester);
  await tester.tap(find.byIcon(Icons.photo_library_outlined));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('project-filter')), findsOneWidget);

  await tester.tap(find.byType(CaptureRecordCard));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('edit-work-location')),
    '不应保存的新位置',
  );

  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  expect(find.text('A 区三层'), findsWidgets);
  final capture = await database.captureById('seed-capture');
  expect(capture?.workLocation, 'A 区三层');

  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('project-filter')), findsOneWidget);
  await disposeApp(tester);
});

testWidgets('settings subsection pop returns to settings menu', (tester) async {
  await pumpAppWithRecords(tester);
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();

  await tester.tap(find.text('外观'));
  await tester.pumpAndSettle();
  expect(find.text('跟随系统'), findsOneWidget);

  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  expect(find.text('新建项目水印默认值'), findsOneWidget);
  await disposeApp(tester);
});
```

- [ ] **Step 2: 运行导航测试并确认按预期失败**

Run:

```powershell
flutter test test/widget_test.dart
```

Expected: 至少项目详情、拍摄表单、记录编辑或设置二级页的返回路径失败，因为入口仍使用 `context.go(...)`。

- [ ] **Step 3: 把用户主动进入下一级页面的入口改为 push**

进行以下精确替换：

```dart
// lib/features/projects/project_list_screen.dart
onTap: () => context.push('/projects/${project.id}'),
onPressed: () => context.push('/projects/new'),

// lib/features/projects/project_detail_screen.dart
onPressed: () => context.push('/projects/${project.id}/settings'),
onPressed: () => context.push('/projects/${widget.projectId}/capture'),

// lib/features/settings/global_settings_screen.dart
onTap: () => context.push(route),

// lib/features/capture/capture_detail_screen.dart
onPressed: () => context.push(
  '/projects/$_projectId/captures/$_captureId/edit',
),
```

保留下列完成或顶级切换路径的 `go`：

- 首页进入 `/records` 和 `/settings`；
- 项目创建成功返回 `/`；
- 编辑保存成功进入对应记录详情；
- 删除整条记录成功进入对应项目；
- 储存页进入顶级 `/records` 管理页面。

- [ ] **Step 4: 运行导航测试并确认通过**

Run:

```powershell
flutter test test/widget_test.dart
```

Expected: PASS，四条路径均只返回刚才所在页面，取消编辑不会写入数据库。

- [ ] **Step 5: 运行现有路由和设置测试**

Run:

```powershell
flutter test test/features/capture/motion_selection_test.dart test/features/settings/global_settings_screen_test.dart test/widget_test.dart
```

Expected: PASS；已有“全部记录 → 详情 → 返回全部记录”行为保持不变。

- [ ] **Step 6: 提交导航修复**

```powershell
git add lib/features/projects/project_list_screen.dart lib/features/projects/project_detail_screen.dart lib/features/settings/global_settings_screen.dart lib/features/capture/capture_detail_screen.dart test/widget_test.dart
git commit -m "fix: preserve immediate navigation history"
```

---

### Task 3: 稳定 Hero 图片飞行并消除返回闪烁

**Files:**
- Create: `lib/features/capture/capture_photo_hero.dart`
- Modify: `lib/features/capture/capture_image_preview.dart`
- Modify: `lib/features/capture/capture_record_card.dart`
- Modify: `lib/features/capture/capture_detail_screen.dart`
- Modify: `lib/app.dart`
- Test: `test/features/capture/capture_record_card_test.dart`
- Test: `test/features/capture/capture_detail_screen_test.dart`
- Create: `test/features/capture/capture_photo_hero_test.dart`

**Interfaces:**
- Consumes: `captureId`、已解析的实际图片 `path`、列表/详情的 `BoxFit` 和现有预览 `child`
- Produces: `CapturePhotoHero`、`heroTag` 参数，以及只包含横向位移的 `_captureDetailPage`

- [ ] **Step 1: 写入先失败的稳定 Hero 测试**

创建 `test/features/capture/capture_photo_hero_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/capture/capture_photo_hero.dart';

void main() {
  late Directory tempDirectory;
  late String photoPath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('sitemark-hero-');
    final file = File('${tempDirectory.path}/photo.png');
    await file.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    photoPath = file.path;
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  Future<void> pumpHeroPair(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                key: const Key('open-hero-detail'),
                onTap: () => Navigator.of(context).push(
                  PageRouteBuilder<void>(
                    transitionDuration: const Duration(milliseconds: 300),
                    reverseTransitionDuration:
                        const Duration(milliseconds: 300),
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        Scaffold(
                          appBar: AppBar(),
                          body: Center(
                            child: SizedBox(
                              width: 320,
                              height: 240,
                              child: CapturePhotoHero(
                                tag: 'capture-photo-test',
                                path: photoPath,
                                child: Image.file(
                                  File(photoPath),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
                child: SizedBox(
                  key: const Key('record-thumbnail'),
                  width: 96,
                  height: 96,
                  child: CapturePhotoHero(
                    tag: 'capture-photo-test',
                    path: photoPath,
                    child: Image.file(File(photoPath), fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hero flight uses a gapless stable image without frame fade', (
    tester,
  ) async {
    await pumpHeroPair(tester);
    await tester.tap(find.byKey(const Key('open-hero-detail')));
    await tester.pump(const Duration(milliseconds: 150));

    final flight = find.byKey(const Key('capture-photo-hero-flight'));
    expect(flight, findsOneWidget);
    final images = tester.widgetList<Image>(
      find.descendant(of: flight, matching: find.byType(Image)),
    );
    expect(images, isNotEmpty);
    expect(images.every((image) => image.gaplessPlayback), isTrue);
    expect(
      find.descendant(of: flight, matching: find.byType(AnimatedOpacity)),
      findsNothing,
    );
    expect(
      find.descendant(of: flight, matching: find.byType(AnimatedSwitcher)),
      findsNothing,
    );
  });

  testWidgets('hero remains in overlay until reverse flight completes', (
    tester,
  ) async {
    await pumpHeroPair(tester);
    await tester.tap(find.byKey(const Key('open-hero-detail')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(const Key('capture-photo-hero-flight')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('record-thumbnail')), findsOneWidget);
  });
}
```

同步更新现有测试：

```dart
// capture_record_card_test.dart
expect(find.byType(CapturePhotoHero), findsOneWidget);

// capture_detail_screen_test.dart
expect(find.byType(CapturePhotoHero), findsOneWidget);
```

- [ ] **Step 2: 运行 Hero 测试并确认按预期失败**

Run:

```powershell
flutter test test/features/capture/capture_photo_hero_test.dart test/features/capture/capture_record_card_test.dart test/features/capture/capture_detail_screen_test.dart
```

Expected: FAIL，因为 `CapturePhotoHero`、稳定飞行层和 `heroTag` 参数尚不存在。

- [ ] **Step 3: 创建稳定 Hero 组件**

创建 `lib/features/capture/capture_photo_hero.dart`，公开以下接口：

```dart
import 'dart:io';

import 'package:flutter/material.dart';

class CapturePhotoHero extends StatelessWidget {
  const CapturePhotoHero({
    super.key,
    required this.tag,
    required this.path,
    required this.child,
  });

  final String tag;
  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      placeholderBuilder: (context, size, child) =>
          SizedBox.fromSize(size: size, child: child),
      flightShuttleBuilder: (
        flightContext,
        animation,
        direction,
        fromHeroContext,
        toHeroContext,
      ) {
        final provider = ResizeImage.resizeIfNeeded(
          2048,
          null,
          FileImage(File(path)),
        );
        final progress = animation;
        return KeyedSubtree(
          key: const Key('capture-photo-hero-flight'),
          child: AnimatedBuilder(
            animation: progress,
            builder: (context, _) {
              final value = progress.value.clamp(0.0, 1.0);
              return Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: 1 - value,
                    child: Image(
                      image: provider,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  Opacity(
                    opacity: value,
                    child: Image(
                      image: provider,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
      child: child,
    );
  }
}
```

列表到详情时由 cover 平滑过渡为 contain；返回时使用反向进度，由 contain 回到 cover。两层 `Image` 共享同一 `ImageProvider`，飞行过程不使用 `frameBuilder`、`AnimatedOpacity` 或异步解析。

- [ ] **Step 4: 把 Hero 放到已解析图片内部**

在 `CaptureImagePreview` 增加：

```dart
final String? heroTag;
```

构造函数增加 `this.heroTag`。在 `_image(...)` 已拿到实际 `path` 后，把现有内容包装为：

```dart
Widget preview = KeyedSubtree(key: Key(key), child: content);
if (widget.heroTag != null) {
  preview = CapturePhotoHero(
    tag: widget.heroTag!,
    path: path,
    child: preview,
  );
}
```

缩略图分支返回 `preview`；详情分支继续在 `GestureDetector` 中使用同一个 `preview`。这样 Hero 两端都使用已经解析出的实际水印图片路径。

在 `CaptureRecordCard` 中：

```dart
CaptureImagePreview(
  capture: capture,
  outputPaths: ref.watch(captureOutputPathsProvider),
  thumbnail: true,
  fileExists: _previewFileExists,
  heroTag: capture.status == CaptureStatus.ready
      ? 'capture-photo-${capture.id}'
      : null,
)
```

删除卡片外层原有 `Hero`。

在 `CaptureDetailScreen` 中向 `CaptureImagePreview` 传入同样的 `heroTag`，并删除详情预览外层原有 `Hero`。

- [ ] **Step 5: 为记录详情使用无透明度叠加的横向路由**

在 `lib/app.dart` 新增：

```dart
CustomTransitionPage<void> _captureDetailPage(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: AppMotion.medium2,
    reverseTransitionDuration: AppMotion.medium2,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.emphasizedDecelerate,
        reverseCurve: AppMotion.emphasizedAccelerate,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
    child: child,
  );
}
```

仅将 `projects/:projectId/captures/:captureId` 的 `pageBuilder` 从 `_sharedAxisPage` 改为 `_captureDetailPage`。编辑页和其他设置页面继续使用现有 Shared Axis。

- [ ] **Step 6: 运行 Hero 和详情测试并确认通过**

Run:

```powershell
flutter test test/features/capture/capture_photo_hero_test.dart test/features/capture/capture_record_card_test.dart test/features/capture/capture_detail_screen_test.dart test/features/capture/capture_image_preview_test.dart
```

Expected: PASS；push 和 pop 中间帧始终存在稳定飞行图片，飞行层没有帧淡入组件。

- [ ] **Step 7: 提交 Hero 修复**

```powershell
git add lib/app.dart lib/features/capture/capture_photo_hero.dart lib/features/capture/capture_image_preview.dart lib/features/capture/capture_record_card.dart lib/features/capture/capture_detail_screen.dart test/features/capture/capture_photo_hero_test.dart test/features/capture/capture_record_card_test.dart test/features/capture/capture_detail_screen_test.dart
git commit -m "fix: stabilize capture hero return flight"
```

---

### Task 4: 全量回归验证

**Files:**
- Verify only: repository-wide Flutter, Rust and Android checks

**Interfaces:**
- Consumes: Tasks 1–3 的全部提交
- Produces: 可供真机验证和提交 PR 的干净分支

- [ ] **Step 1: 检查格式与静态分析**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
git diff --check
```

Expected: 三条命令均退出码 0，无格式、分析或空白错误。

- [ ] **Step 2: 运行全部 Flutter 测试**

Run:

```powershell
flutter test
```

Expected: 全部测试通过，无失败和未处理异常。

- [ ] **Step 3: 运行 Rust 与 Android 单元测试**

Run:

```powershell
cargo test --manifest-path rust/Cargo.toml
./android/gradlew -p android :sitemark_system_api:testDebugUnitTest
```

Expected: Rust 与 Android 测试全部通过。

- [ ] **Step 4: 构建调试 APK**

Run:

```powershell
flutter build apk --debug
```

Expected: 生成 `build/app/outputs/flutter-apk/app-debug.apk`。

- [ ] **Step 5: 真机验收路径**

按以下顺序验证：

1. 首页点击搜索，输入内容；右侧只有一个按钮，第一次清空、第二次退出，标题不跳动。
2. 首页进入项目后返回，回到首页。
3. 项目进入拍摄表单后返回，回到该项目。
4. 记录详情进入编辑，修改但不保存，点击返回；回到详情且数据库内容未变化。
5. 项目记录和全部记录各打开同一张 ready 图片，再返回；Hero 飞回对应缩略图且无闪白。
6. 从详情点击图片进入全屏，验证双击缩放、捏合和平移、下拉关闭保持正常。

- [ ] **Step 6: 检查工作区与提交记录**

Run:

```powershell
git status --short
git log --oneline -5
```

Expected: 除执行前已存在且不属于本任务的未跟踪文件外，没有未提交的任务改动；最近提交依次包含搜索、导航和 Hero 修复。
