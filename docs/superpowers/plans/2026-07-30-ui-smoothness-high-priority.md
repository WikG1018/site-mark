# UI Smoothness High-Priority Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the two highest-impact smoothness improvements the user requested: unified Skeletonizer loading states for all major lists, and left/right swipe between adjacent photos in the fullscreen viewer.

**Architecture:** 
- Skeletonizer is already a dependency and used on AllCaptures. We mirror the same pattern (Skeletonizer + fixed skeleton widgets that match real card layout) on ProjectList and ProjectDetail capture lists. The existing test that forbids Skeletonizer will be updated to assert the opposite (Skeletonizer present, real Cards absent on first frame).
- Fullscreen swipe requires changing the navigation contract of CaptureFullscreenScreen from a single path to a list + index, then wrapping the existing InteractiveViewer + gesture logic inside a PageView. Horizontal drag is only handed to PageView when scale == 1.0 to avoid conflict with zoom pan.

**Tech Stack:** Flutter 3.44, skeletonizer ^2.1.3, existing AppMotion / MediaQuery.disableAnimations helpers, go_router, Riverpod.

## Global Constraints

- Do not invent a wrong project/capture count in any skeleton (fixed small number of placeholder cards only).
- All new Animated* widgets must use `AppMotion.durationOf(context, ...)`.
- Keep existing reduce-motion short-circuits.
- Prefer small, reviewable commits. Each task ends with a green `flutter analyze` + relevant tests.
- Never force-push or rewrite history of the PR branch.

---

### Task 1: Unified Skeletonizer on ProjectListScreen

**Files:**
- Modify: `lib/features/projects/project_list_screen.dart`
- Modify: `test/features/projects/project_list_screen_test.dart`

**Interfaces:**
- Consumes: existing `Skeletonizer` package and the `_CaptureListSkeleton` pattern already present in AllCaptures.
- Produces: when `!snapshot.hasData`, show a Skeletonizer-wrapped list of 4–6 placeholder project cards instead of `SizedBox.shrink()`.

- [ ] **Step 1: Write / update the failing test**

In `project_list_screen_test.dart`, change the existing test:

```dart
testWidgets('home first frame does not paint fake project rows', (tester) async {
  // ... existing controlled database setup ...
  await tester.pumpWidget(...);

  // NEW expectations:
  expect(find.byType(Skeletonizer), findsOneWidget);
  expect(find.byType(Card), findsNothing); // real cards still forbidden
  // skeleton placeholders may contain grey boxes / bone text but no real project data
  await disposeApp(tester);
});
```

Also add a positive test that after the stream emits, Skeletonizer disappears and real Cards appear.

- [ ] **Step 2: Run the test and confirm it fails for the right reason**

(We cannot run locally; rely on the subsequent CI. Mentally verify the assertion change is correct.)

- [ ] **Step 3: Implement Skeletonizer on ProjectListScreen**

Replace the `if (!snapshot.hasData) return const SizedBox.shrink();` block with:

```dart
if (!snapshot.hasData) {
  return Skeletonizer(
    key: const Key('project-list-skeleton'),
    child: ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => const _ProjectCardSkeleton(),
    ),
  );
}
```

Add a private `_ProjectCardSkeleton` that mirrors the real Card + ListTile layout (CircleAvatar + two text lines) using grey placeholders / fixed strings that Skeletonizer will bone.

Keep the existing `scrollCacheExtent` and `RepaintBoundary` on the real list.

- [ ] **Step 4: Commit**

```
fix(ui): project list shows Skeletonizer while first projects emit
```

---

### Task 2: Skeletonizer on ProjectDetail capture list

**Files:**
- Modify: `lib/features/projects/project_detail_screen.dart`

**Interfaces:**
- When `loadingCaptures == true`, show a Skeletonizer list of capture-card skeletons instead of empty `SliverFillRemaining`.

- [ ] **Step 1: Implement**

In `_projectCaptureList`, replace the `if (loadingCaptures) const SliverFillRemaining(... SizedBox.shrink())` branch with a Sliver that contains a Skeletonizer + fixed number of `_CaptureCardSkeleton` (reuse or copy the one already living in AllCaptures if possible; otherwise duplicate a minimal version).

- [ ] **Step 2: Commit**

```
fix(ui): project detail capture list uses Skeletonizer while loading
```

---

### Task 3: Fullscreen left/right swipe between adjacent photos

**Files:**
- Modify: `lib/features/capture/capture_fullscreen_screen.dart`
- Modify: callers (search for `CaptureFullscreenScreen(` or the route that pushes it — currently from detail image preview)
- Add/Update: `test/features/capture/capture_fullscreen_screen_test.dart`

**Interfaces:**
- Change constructor to:
  ```dart
  const CaptureFullscreenScreen({
    super.key,
    required this.paths,          // List<String> of absolute image paths
    required this.initialIndex,
    this.previewImages,           // optional Map or parallel list of already-decoded previews
  });
  ```
- Internal state holds a `PageController(initialPage: initialIndex)`.
- Each page is the existing InteractiveViewer + drag-to-dismiss + double-tap logic, but vertical-drag-to-dismiss only active when the current page’s scale == 1.0.
- Horizontal drag is owned by PageView only when scale == 1.0; when zoomed, InteractiveViewer keeps pan.

- [ ] **Step 1: Update the navigation call sites**

Find every place that constructs `CaptureFullscreenScreen` (primarily the detail preview). Pass the ordered list of ready capture paths for the current project/filter and the index of the tapped photo.

- [ ] **Step 2: Rewrite CaptureFullscreenScreen body around PageView**

Keep the black Scaffold, chrome AppBar, SystemUiMode, and memory-pressure pop. Replace the single-image GestureDetector tree with:

```dart
PageView.builder(
  controller: _pageController,
  itemCount: widget.paths.length,
  itemBuilder: (context, index) => _FullscreenPage(
    path: widget.paths[index],
    previewImage: ...,
    // pass the same gesture controllers / zoom state carefully so only the current page is interactive
  ),
)
```

Carefully isolate the TransformationController per page or reset on page change to avoid zoom state leaking.

- [ ] **Step 3: Add tests**

- Pump with 3 paths, initialIndex 1.
- Verify PageView exists.
- Simulate horizontal drag and assert the displayed path changes (or that the controller’s page changes).
- Verify vertical drag-to-dismiss still works on the middle page when not zoomed.

- [ ] **Step 4: Commit**

```
feat(ui): fullscreen viewer supports left/right swipe between adjacent captures
```

---

### Task 4: Final verification & PR polish

- [ ] Run (via CI) `flutter analyze` and the affected test files.
- [ ] Update the PR body test-plan checkboxes to reflect the new Skeletonizer and swipe behaviour.
- [ ] Confirm no remaining `Siver*` typos or unresolved `ScrollCacheExtent`.
- [ ] Announce readiness for review / merge.

---

**Self-review notes (plan author):**
- Skeletonizer tasks deliberately keep a fixed small itemCount so we never invent a wrong total.
- Fullscreen swipe is the riskiest task (gesture conflict). The plan isolates it as its own task so it can be reviewed independently.
- All duration usages already go through `AppMotion.durationOf` in the current branch; new code must continue that pattern.
