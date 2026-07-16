# SiteMark Compact Filters and Record Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make project/date filters fit one row, expose original-photo state and file details, and add safe selected-photo export, republish, original cleanup, and full deletion to both record lists and photo details.

**Architecture:** Centralize file inspection and destructive operations in `CaptureMediaService`; UI surfaces only select IDs and render progress/results. Extend the Rust exporter for one cross-project ZIP grouped by project. Reuse one selection controller, compact menu, record card, action bar, and detail metadata model across project and global lists.

**Tech Stack:** Flutter Material 3, Riverpod, Drift schema v4, Dart IO, Pigeon image metadata, Rust ZIP/CSV/JSON exporter, share_plus.

## Global Constraints

- Complete foundation, camera/location, and watermark plans first.
- Project page shows year/month/day in one row; all-records shows project/year/month/day in one row at 360dp.
- Filter changes clear selection. “Select all” selects only the current filtered result.
- `captured` and `rendering` records are not selectable or deletable.
- `ready` records support every action; final `failed` records support original cleanup and full deletion only.
- Cross-project export creates one ZIP with project folders and a root manifest.
- “Clear originals” preserves watermarked files, published images, database rows, photo numbers, and SHA-256 evidence.
- “Delete all” removes original, private rendered file, published MediaStore image, and database row; a failed external deletion keeps the row for retry.
- List states are exactly retained, cleared, and unexpectedly missing.
- Destructive actions require confirmation and are idempotent.

---

## File Map

- Create: `lib/domain/original_photo_state.dart`, `lib/domain/capture_file_info.dart`.
- Create: `lib/workflow/capture_media_service.dart`, `test/workflow/capture_media_service_test.dart`.
- Create: `lib/features/capture/compact_filter_menu.dart`.
- Create: `lib/features/capture/capture_selection_controller.dart`, `test/features/capture/capture_selection_controller_test.dart`.
- Create: `lib/features/capture/capture_batch_action_bar.dart`.
- Modify: `lib/features/capture/capture_date_filter_bar.dart`, `all_captures_screen.dart`, `project_detail_screen.dart`.
- Modify: `lib/features/capture/capture_record_card.dart`, `capture_image_preview.dart`, `capture_detail_screen.dart`.
- Modify: `lib/features/capture/capture_edit_screen.dart`, `lib/workflow/capture_workflow.dart` — block regeneration without a retained original.
- Modify: `lib/platform/platform_services.dart`, `lib/workflow/project_export_service.dart`, `lib/app.dart`, `lib/l10n/app_strings.dart`.
- Modify: `rust/src/api/image_core.rs`, `rust/tests/core_test.rs`, generated FRB Dart.
- Modify: capture filter, export, widget, detail, and workflow tests.

### Task 1: Model Original State and Inspect Both Files

**Files:**
- Create: `lib/domain/original_photo_state.dart`
- Create: `lib/domain/capture_file_info.dart`
- Create: `lib/workflow/capture_media_service.dart`
- Create: `test/workflow/capture_media_service_test.dart`
- Modify: `lib/platform/platform_services.dart`
- Modify: `lib/app.dart`

**Interfaces:**
- Produces: `OriginalPhotoState { retained, cleared, missing }`.
- Produces: `PhotoFileInfo` and `CaptureFileInfo`.
- Produces: `CaptureMediaService.originalState/inspect/clearOriginals/deleteAll/republish`.

- [ ] **Step 1: Write failing original-state and inspection tests**

Add this fixture to the test file:

```dart
CaptureRecord mediaRecord({DateTime? originalDeletedAt}) => CaptureRecord(
  id: 'capture-1',
  projectId: 'project-1',
  photoNumber: 'SM-20260716-001',
  workLocation: 'A 区',
  workContent: '风管检查',
  photographer: '张工',
  originalPath: '/private/original.jpg',
  publishedUri: 'content://media/site-mark/1',
  originalSha256:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  status: CaptureStatus.ready,
  createdAt: DateTime(2026, 7, 16, 9),
  capturedAt: DateTime(2026, 7, 16, 9),
  processingAttempts: 0,
  watermarkLocaleCode: 'zh',
  locationResolution: 'resolved',
  originalDeletedAt: originalDeletedAt,
);
```

In `setUp`, construct an in-memory database, a fake private store exposing `existing`/`deleted`, a fake platform exposing `metadataByPath`, fake rendered paths, and `CaptureMediaService` from those four dependencies. Then add:

```dart
test('original state distinguishes retained cleared and missing', () async {
  files.existing.add('/private/original.jpg');
  expect(await service.originalState(mediaRecord()),
      OriginalPhotoState.retained);

  expect(
    await service.originalState(
      mediaRecord(originalDeletedAt: DateTime(2026, 7, 16)),
    ),
    OriginalPhotoState.cleared,
  );

  files.existing.clear();
  expect(await service.originalState(mediaRecord()),
      OriginalPhotoState.missing);
});

test('inspect reports original and rendered metadata independently', () async {
  files.existing.addAll(['/private/original.jpg', '/rendered/capture-1.jpg']);
  platform.metadataByPath['/private/original.jpg'] = ImageMetadataResult(
    width: 4000, height: 3000, fileSizeBytes: 5_000_000,
    mimeType: 'image/jpeg',
  );
  platform.metadataByPath['/rendered/capture-1.jpg'] = ImageMetadataResult(
    width: 4000, height: 3000, fileSizeBytes: 3_200_000,
    mimeType: 'image/jpeg',
  );

  final info = await service.inspect(mediaRecord());
  expect(info.original?.fileSizeBytes, 5_000_000);
  expect(info.watermarked?.fileSizeBytes, 3_200_000);
  expect(info.originalState, OriginalPhotoState.retained);
});
```

- [ ] **Step 2: Add filesystem queries to the injected private store**

Extend `PrivateFileStore`:

```dart
Future<bool> exists(String path);
Future<void> deleteIfExists(String path);
```

Implement `exists` with `File(path).exists()`. Update every fake with a deterministic set of existing paths.

- [ ] **Step 3: Add domain models**

```dart
enum OriginalPhotoState { retained, cleared, missing }

class PhotoFileInfo {
  const PhotoFileInfo({
    required this.path,
    required this.fileSizeBytes,
    required this.width,
    required this.height,
    required this.mimeType,
  });
  final String path;
  final int fileSizeBytes;
  final int width;
  final int height;
  final String mimeType;
}

class CaptureFileInfo {
  const CaptureFileInfo({
    required this.originalState,
    this.original,
    this.watermarked,
  });
  final OriginalPhotoState originalState;
  final PhotoFileInfo? original;
  final PhotoFileInfo? watermarked;
}
```

- [ ] **Step 4: Implement state and metadata inspection**

```dart
Future<OriginalPhotoState> originalState(CaptureRecord record) async {
  if (record.originalDeletedAt != null) return OriginalPhotoState.cleared;
  return await files.exists(record.originalPath)
      ? OriginalPhotoState.retained
      : OriginalPhotoState.missing;
}

Future<PhotoFileInfo?> _inspectPath(String path) async {
  if (!await files.exists(path)) return null;
  final metadata = await platform.inspectImage(path);
  return PhotoFileInfo(
    path: path,
    fileSizeBytes: metadata.fileSizeBytes,
    width: metadata.width,
    height: metadata.height,
    mimeType: metadata.mimeType,
  );
}
```

`inspect` resolves `outputPaths.renderedPhotoPath(record.id)`, inspects both paths, and returns one `CaptureFileInfo`.

- [ ] **Step 5: Wire provider, run tests, and commit**

```powershell
dart format lib test
flutter test test/workflow/capture_media_service_test.dart test/platform/platform_services_test.dart
flutter analyze
git add lib test
git commit -m "feat: inspect capture files and original state"
```

### Task 2: Implement Idempotent Media Actions and Cross-Project Export

**Files:**
- Modify: `lib/workflow/capture_media_service.dart`
- Modify: `test/workflow/capture_media_service_test.dart`
- Modify: `lib/workflow/project_export_service.dart`
- Modify: `test/workflow/project_export_test.dart`
- Modify: `lib/platform/platform_services.dart`
- Modify: `rust/src/api/image_core.rs`, `rust/tests/core_test.rs`
- Regenerate: `lib/src/rust/**`.

**Interfaces:**
- Produces: `CaptureActionResult(succeededIds, skippedIds, failures)`.
- Produces: `ProjectExportService.exportSelection(captureIds, includeOriginals)`.
- Produces: Rust `export_selection(ExportSelectionRequest)`.

- [ ] **Step 1: Write failing cleanup/delete/republish tests**

```dart
test('clear originals preserves record rendered image URI and hash', () async {
  files.existing.add('/private/original.jpg');
  final result = await service.clearOriginals(['capture-1']);
  final row = await database.captureById('capture-1');
  expect(result.succeededIds, ['capture-1']);
  expect(files.deleted, ['/private/original.jpg']);
  expect(row, isNotNull);
  expect(row?.publishedUri, 'content://media/site-mark/1');
  expect(row?.originalSha256, digestA);
  expect(row?.originalDeletedAt, isNotNull);
});

test('delete all keeps the row when published deletion fails', () async {
  platform.deleteError = StateError('MediaStore failure');
  final result = await service.deleteAll(['capture-1']);
  expect(result.failures.keys, ['capture-1']);
  expect(await database.captureById('capture-1'), isNotNull);
});

test('republish updates the actual returned URI', () async {
  files.existing.add('/rendered/capture-1.jpg');
  platform.nextPublishedUri = 'content://media/site-mark/re-saved';
  await service.republish(['capture-1']);
  expect((await database.captureById('capture-1'))?.publishedUri,
      'content://media/site-mark/re-saved');
});
```

- [ ] **Step 2: Add the database URI update used by republish**

Add:

```dart
Future<CaptureRecord> updatePublishedUri(
  String captureId,
  String publishedUri,
) async {
  await (update(captureRecords)..where((row) => row.id.equals(captureId))).write(
    CaptureRecordsCompanion(publishedUri: Value(publishedUri)),
  );
  return captureById(captureId).then((row) => row!);
}
```

Test it preserves status and evidence.

- [ ] **Step 3: Implement media actions with per-ID results**

```dart
class CaptureActionResult {
  const CaptureActionResult({
    required this.succeededIds,
    required this.skippedIds,
    required this.failures,
  });
  final List<String> succeededIds;
  final List<String> skippedIds;
  final Map<String, String> failures;
}
```

Process IDs sequentially. `clearOriginals` permits `ready`/`failed`; retained originals are deleted then marked, already-cleared rows are skipped, unexpectedly missing originals are failures. `republish` accepts only `ready`, requires the rendered file, calls `publishJpeg(path, photoNumber!)`, and persists the returned URI.

`deleteAll` permits `ready`/`failed` and executes this exact order per row:

```dart
if (record.publishedUri != null) {
  await platform.deletePublishedImage(record.publishedUri!);
}
await files.deleteIfExists(record.originalPath);
await files.deleteIfExists(await outputPaths.renderedPhotoPath(record.id));
await database.deleteCapture(record.id);
```

Catch per-record exceptions, preserve the row on failure, and continue with later IDs.

- [ ] **Step 4: Add the cross-project Rust request and failing ZIP test**

Add:

```rust
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExportSelectionProject {
    pub project_id: String,
    pub project_name: String,
    pub photos: Vec<ExportPhotoRecord>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ExportSelectionRequest {
    pub output_zip_path: String,
    pub include_originals: bool,
    pub projects: Vec<ExportSelectionProject>,
}
```

The failing test exports two projects and asserts these entries:

```rust
assert!(archive.by_name("projects/project-a/photos/SM-20260716-001.jpg").is_ok());
assert!(archive.by_name("projects/project-b/photos/SM-20260716-002.jpg").is_ok());
assert!(archive.by_name("records.csv").is_ok());
assert!(archive.by_name("manifest.json").is_ok());
```

- [ ] **Step 5: Implement one ZIP grouped by project**

Validate project IDs with the existing ASCII-safe component helper. For each project/photo, write watermarked and optional original entries below `projects/<project-id>/`. Write one root BOM CSV with a `project_name` column and one root manifest containing every project and photo. Reject an empty project list and an empty total photo list.

Expose `exportSelection` on `ImagePipeline`, map it in `RustImagePipeline`, and add `SelectionExportPaths.selectionZipPath()` returning `exports/sitemark-selection-<UTC milliseconds>.zip`.

- [ ] **Step 6: Implement `ProjectExportService.exportSelection`**

Load `capturesByIds`, reject any non-`ready` row, group by project ID, preserve each group’s capture-time order, omit originals whose `originalDeletedAt` is non-null, and fail an `includeOriginals: true` request when any selected original is unavailable. Build `ExportSelectionRequest`, call `images.exportSelection`, and return the result.

- [ ] **Step 7: Run Rust/Dart tests and commit**

```powershell
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo clippy --manifest-path rust/Cargo.toml -- -D warnings
cargo test --manifest-path rust/Cargo.toml
dart run build_runner build --delete-conflicting-outputs
dart format lib test
flutter test test/workflow/capture_media_service_test.dart test/workflow/project_export_test.dart
flutter analyze
git add rust lib test
git commit -m "feat: add selected capture media actions"
```

### Task 3: Build Compact One-Row Filters and Shared Selection State

**Files:**
- Create: `lib/features/capture/compact_filter_menu.dart`
- Create: `lib/features/capture/capture_selection_controller.dart`
- Create: `test/features/capture/capture_selection_controller_test.dart`
- Modify: `lib/features/capture/capture_date_filter_bar.dart`
- Modify: `test/features/capture/capture_filter_ui_test.dart`

**Interfaces:**
- Produces: `CompactFilterMenu<T>`.
- Produces: `CaptureSelectionController.enter/exit/toggle/selectAll/clearForFilterChange`.

- [ ] **Step 1: Write failing 360dp layout tests**

Set the test surface and assert the three date controls share one top coordinate and no exception occurs:

```dart
import 'dart:math' show max, min;

await tester.binding.setSurfaceSize(const Size(360, 800));
addTearDown(() => tester.binding.setSurfaceSize(null));
await tester.pumpWidget(filterHarnessLive(filter));
await tester.pumpAndSettle();
final tops = [
  tester.getTopLeft(find.byKey(const Key('filter-year'))).dy,
  tester.getTopLeft(find.byKey(const Key('filter-month'))).dy,
  tester.getTopLeft(find.byKey(const Key('filter-day'))).dy,
];
expect(tops.reduce(max) - tops.reduce(min), lessThan(1));
expect(tester.takeException(), isNull);
```

Add the same assertion for project/year/month/day on `AllCapturesScreen`.

- [ ] **Step 2: Implement a compact 48dp menu control**

```dart
class CompactFilterMenu<T> extends StatelessWidget {
  const CompactFilterMenu({
    super.key,
    required this.label,
    required this.entries,
    required this.onSelected,
    this.enabled = true,
  });
  final String label;
  final List<(T, String)> entries;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      for (final entry in entries)
        MenuItemButton(
          onPressed: () => onSelected(entry.$1),
          child: Text(entry.$2),
        ),
    ],
    builder: (context, controller, _) => SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: enabled ? controller.open : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
        ),
        child: Row(children: [
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const Icon(Icons.arrow_drop_down, size: 18),
        ]),
      ),
    ),
  );
}
```

Replace the `Wrap` and 140px `DropdownMenu`s with one `Row` of three `Expanded` children. On all-records, place project `Expanded` beside `Expanded(flex: 3, child: CaptureDateFilterBar(padding: EdgeInsets.zero))`.

- [ ] **Step 3: Write and implement selection-controller tests**

```dart
test('filter change clears hidden selections', () {
  final controller = CaptureSelectionController()..enter();
  controller.toggle('a');
  controller.toggle('b');
  controller.clearForFilterChange();
  expect(controller.selectedIds, isEmpty);
  expect(controller.editing, isTrue);
});

test('select all replaces selection with visible eligible IDs', () {
  final controller = CaptureSelectionController()..enter();
  controller.selectAll(['a', 'c']);
  expect(controller.selectedIds, {'a', 'c'});
});
```

The controller extends `ChangeNotifier`; `exit()` clears IDs, `toggle()` adds/removes one ID, and `selectedIds` exposes an unmodifiable set.

- [ ] **Step 4: Run focused tests and commit**

```powershell
dart format lib test
flutter test test/features/capture/capture_filter_ui_test.dart test/features/capture/capture_selection_controller_test.dart
flutter analyze
git add lib/features/capture test/features/capture
git commit -m "feat: add compact filters and selection state"
```

### Task 4: Add Edit Mode and Batch Action UI to Both Lists

**Files:**
- Create: `lib/features/capture/capture_batch_action_bar.dart`
- Modify: `lib/features/capture/capture_record_card.dart`
- Modify: `lib/features/capture/all_captures_screen.dart`
- Modify: `lib/features/projects/project_detail_screen.dart`
- Modify: `lib/l10n/app_strings.dart`
- Modify: `test/widget_test.dart`, `test/features/capture/capture_filter_ui_test.dart`.

**Interfaces:**
- Consumes: `CaptureSelectionController`, `CaptureMediaService`, `ProjectExportService`.
- Produces: identical edit/select/action behavior on project and global lists.

- [ ] **Step 1: Write failing list-edit tests**

Test both screens for:

```dart
await tester.tap(find.byKey(const Key('edit-captures')));
await tester.pumpAndSettle();
expect(find.byType(Checkbox), findsWidgets);
await tester.tap(find.byKey(const Key('select-all-captures')));
expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
```

Change a date/project filter and assert selected count returns to zero. At 360dp assert four batch action destinations do not overflow.

- [ ] **Step 2: Extend the shared record card**

Add optional parameters:

```dart
final bool selectionMode;
final bool selected;
final bool selectable;
final ValueChanged<bool>? onSelectedChanged;
```

When `selectionMode`, prepend a `Checkbox`; card taps toggle selection instead of navigating. Disabled busy rows show a disabled checkbox. Add a `FutureBuilder<OriginalPhotoState>` below metadata and localize the three status labels.

- [ ] **Step 3: Implement the four-action bottom bar**

Use a `BottomAppBar` keyed `batch-action-bar` with four equal `Expanded` `IconButton.filledTonal`/labels: export, save to gallery, clear originals, delete all. Disable export/republish unless every selected row is `ready`; disable every action for an empty selection.

Each action shows a count-aware confirmation where required, executes sequential service work, shows progress `completed/total`, then reports success/skipped/failed counts in a Snackbar or dialog.

- [ ] **Step 4: Integrate project and all-records screens**

Each state owns/disposes a `CaptureSelectionController`. Add AppBar edit/done and select-all actions. Feed only current filtered selectable IDs to `selectAll`. Call `clearForFilterChange()` in every project/year/month/day change callback.

For export, call `exportSelection`, then `ShareFileService.shareFile(result.outputZipPath)`. The all-records path may contain multiple projects; it still produces one ZIP.

- [ ] **Step 5: Run widget tests and commit**

```powershell
dart format lib test
flutter test test/features/capture/capture_filter_ui_test.dart test/widget_test.dart
flutter analyze
git add lib test
git commit -m "feat: add capture list edit mode"
```

### Task 5: Show File Details and Both Delete Actions in Photo Detail

**Files:**
- Modify: `lib/features/capture/capture_image_preview.dart`
- Modify: `lib/features/capture/capture_detail_screen.dart`
- Modify: `lib/features/capture/capture_edit_screen.dart`
- Modify: `lib/workflow/capture_workflow.dart`
- Modify: `lib/l10n/app_strings.dart`
- Create: `test/features/capture/capture_detail_screen_test.dart`

**Interfaces:**
- Consumes: `CaptureMediaService.inspect/clearOriginals/deleteAll`.
- Produces: explicit watermarked/original preview and metadata/actions.

- [ ] **Step 1: Write failing detail tests**

Add this complete harness to the new test file (the fake platform implements unrelated methods as no-op/test failures):

```dart
late AppDatabase database;
late _DetailFiles files;
late _DetailPlatform platform;
late _DetailPaths paths;
late CaptureMediaService media;

Future<void> pumpReadyDetail(
  WidgetTester tester, {
  required bool originalExists,
}) async {
  database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  await database.createProject(id: 'project-1', name: '东区厂房改造');
  final pending = await database.createPendingCapture(
    id: 'capture-1',
    projectId: 'project-1',
    originalPath: '/private/original.jpg',
    workLocation: 'A 区',
    workContent: '风管检查',
    photographer: '张工',
    watermarkLocaleCode: 'zh',
    locationResolution: 'resolved',
  );
  await database.markCaptured(
    captureId: pending.id,
    capturedAt: DateTime(2026, 7, 16, 9),
  );
  await database.markRendering(
    captureId: pending.id,
    originalSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
  await database.markReady(
    captureId: pending.id,
    publishedUri: 'content://media/site-mark/1',
  );

  files = _DetailFiles();
  if (originalExists) files.existing.add('/private/original.jpg');
  files.existing.add('/rendered/capture-1.jpg');
  platform = _DetailPlatform()
    ..metadataByPath['/private/original.jpg'] = ImageMetadataResult(
      width: 4000, height: 3000, fileSizeBytes: 5_000_000,
      mimeType: 'image/jpeg',
    )
    ..metadataByPath['/rendered/capture-1.jpg'] = ImageMetadataResult(
      width: 4000, height: 3000, fileSizeBytes: 3_200_000,
      mimeType: 'image/jpeg',
    );
  paths = _DetailPaths();
  media = CaptureMediaService(
    database: database,
    platform: platform,
    outputPaths: paths,
    files: files,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        captureOutputPathsProvider.overrideWithValue(paths),
        captureMediaServiceProvider.overrideWithValue(media),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const CaptureDetailScreen(
          projectId: 'project-1',
          captureId: 'capture-1',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _DetailFiles implements PrivateFileStore {
  final Set<String> existing = {};
  @override
  Future<bool> exists(String path) async => existing.contains(path);
  @override
  Future<void> deleteIfExists(String path) async => existing.remove(path);
}

class _DetailPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _DetailPlatform implements PlatformServices {
  final Map<String, ImageMetadataResult> metadataByPath = {};
  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      metadataByPath[path]!;
  @override
  Future<void> deletePublishedImage(String contentUri) async {}
  @override
  Future<String> publishJpeg(String sourcePath, String displayName) async =>
      'content://media/site-mark/1';
  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      LocationPermissionState.denied;
  @override
  Future<LocationPermissionState> requestLocationPermission() async =>
      LocationPermissionState.denied;
  @override
  Future<void> openApplicationSettings() async {}
  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async =>
      LocationResult(outcome: LocationOutcome.permissionDenied);
  @override
  Future<String> createCameraTarget(String captureId) =>
      throw UnsupportedError('camera not used');
  @override
  Future<CameraCaptureResult> launchCamera(String captureId) =>
      throw UnsupportedError('camera not used');
  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;
  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}
}
```

```dart
testWidgets('detail shows both file sizes and original toggle', (tester) async {
  await pumpReadyDetail(tester, originalExists: true);
  expect(find.text('4.8 MB'), findsOneWidget);
  expect(find.text('3.1 MB'), findsOneWidget);
  expect(find.byKey(const Key('show-original')), findsOneWidget);
  expect(find.byKey(const Key('delete-original')), findsOneWidget);
  expect(find.byKey(const Key('delete-all')), findsOneWidget);
});

testWidgets('deleting original keeps detail and disables original preview', (tester) async {
  await pumpReadyDetail(tester, originalExists: true);
  await tester.tap(find.byKey(const Key('delete-original')));
  await tester.tap(find.widgetWithText(FilledButton, '删除原图'));
  await tester.pumpAndSettle();
  expect(find.text('原图已清理'), findsOneWidget);
  expect(find.byKey(const Key('show-original')), findsNothing);
  expect(find.byIcon(Icons.edit_outlined), findsNothing);
  expect(await database.captureById('capture-1'), isNotNull);
});
```

Add a workflow test that marks `originalDeletedAt`, calls `regenerateCapture`, and expects `StateError('Original photo is not available')` without enqueueing.

- [ ] **Step 2: Add explicit preview source support**

Add:

```dart
enum CapturePreviewSource { bestAvailable, watermarked, original }
```

`CaptureImagePreview` accepts `source`, resolves only the requested path for explicit modes, and keeps the current fallback behavior for `bestAvailable`. An unavailable explicit original displays the original-state placeholder; it must not silently show the watermarked image under the “Original” tab.

- [ ] **Step 3: Convert detail to stateful source/metadata UI**

Use a segmented control keyed `show-watermarked`/`show-original` when the original is retained. Display file size with a binary formatter, resolution as `width × height`, MIME/format, published status, capture fields, coordinates, and SHA-256.

```dart
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}
```

- [ ] **Step 4: Add separate destructive actions**

“Delete original” calls `clearOriginals([captureId])`, refreshes metadata, and stays on detail. “Delete all” calls `deleteAll([captureId])`; only after success navigate back to `/projects/$projectId`. Both dialogs name exactly what remains or is removed. Disable both while status is `captured`/`rendering`; hide delete-original and edit/regenerate after cleanup.

In `CaptureWorkflow.regenerateCapture`, enforce the same rule before updating fields:

```dart
if (record.originalDeletedAt != null ||
    !await _fileStore.exists(record.originalPath)) {
  throw StateError('Original photo is not available');
}
```

Use the already injected private file store; do not rely only on a widget-level check.

- [ ] **Step 5: Run detail tests and commit**

```powershell
dart format lib test
flutter test test/features/capture/capture_detail_screen_test.dart test/features/capture/capture_image_preview_test.dart test/workflow/capture_workflow_test.dart test/widget_test.dart
flutter analyze
git add lib test
git commit -m "feat: add original file detail management"
```

### Task 6: Record-Management Verification Gate

**Files:**
- Verify only.

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: verified list, ZIP, media, and detail behavior.

- [ ] **Step 1: Run all generated and automated checks**

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter analyze
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo clippy --manifest-path rust/Cargo.toml -- -D warnings
cargo test --manifest-path rust/Cargo.toml
git diff --check
```

Expected: all checks PASS.

- [ ] **Step 2: Run device acceptance cases**

At 360dp-equivalent width, verify both filter rows remain single-line. Select photos from one and multiple projects, export one grouped ZIP, republish, clear originals, and full-delete. Confirm card badges update, detail displays size/resolution, cleared originals cannot be viewed/regenerated, and failed deletion leaves a retryable record.
