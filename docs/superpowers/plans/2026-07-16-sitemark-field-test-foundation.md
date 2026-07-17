# SiteMark Field-Test Data Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the persisted model to schema v4 and provide the shared APIs required by the camera, watermark, original-photo management, and permission-prompt work.

**Architecture:** Perform one schema migration before any feature plan so later work never reuses or rebases schema version 4. Keep user intent (`originalDeletedAt`, prompt dismissal), capture snapshots (`watermarkLocaleCode`), and coordination state (`locationResolution`) in Drift; continue deriving unexpected file loss from the filesystem.

**Tech Stack:** Flutter 3.41/Dart 3.12, Drift 2.34.2, sqlite3 test fixtures, build_runner.

## Global Constraints

- Execute this plan first, then camera/location, watermark, record management, and home/search plans in that order.
- Schema version 4 is created exactly once in this plan; later plans must not bump it.
- Existing projects, captures, photo numbers, hashes, published URIs, settings, and processing attempts must survive migration.
- Existing captures migrate with `watermarkLocaleCode = 'zh'` and `locationResolution = 'resolved'`.
- New capture rows start with `locationResolution = 'pending'` unless a caller explicitly supplies another value.
- Font scale range is 0.80–1.60 and default is 1.00.
- Do not edit `lib/data/app_database.g.dart` by hand; regenerate it.
- Keep the application offline: no account, cloud, ads, analytics, or network permission.

---

## File Map

- Modify: `lib/data/app_database.dart` — schema v4 columns, migration, validation, and shared data methods.
- Regenerate: `lib/data/app_database.g.dart` — Drift data classes and companions.
- Modify: `test/data/app_database_migration_test.dart` — real v3 fixture and v3→v4 preservation/default assertions.
- Modify: `test/data/app_database_test.dart` — font, locale, location-resolution, prompt-dismissal, original-cleanup, and ID-query behavior.

### Task 1: Add and Prove the Schema v4 Migration

**Files:**
- Modify: `test/data/app_database_migration_test.dart`
- Modify: `lib/data/app_database.dart`
- Regenerate: `lib/data/app_database.g.dart`

**Interfaces:**
- Produces: `Project.watermarkFontScale: double`
- Produces: `AppSetting.defaultWatermarkFontScale: double`
- Produces: `AppSetting.locationPermissionPromptDismissed: bool`
- Produces: `CaptureRecord.watermarkLocaleCode: String`
- Produces: `CaptureRecord.locationResolution: String`
- Produces: `CaptureRecord.originalDeletedAt: DateTime?`

- [ ] **Step 1: Add the real v3 migration fixture and failing assertions**

Add this fixture beside `openMigratedV2Fixture()`; keep the existing v2 tests intact:

```dart
QueryExecutor openMigratedV3Fixture() {
  final db = sqlite3.openInMemory();
  final projectCreated =
      DateTime.utc(2026, 7, 16).millisecondsSinceEpoch ~/ 1000;
  final captureCreated =
      DateTime(2026, 7, 16, 9, 30).millisecondsSinceEpoch ~/ 1000;

  db.execute('''
    CREATE TABLE projects (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
      watermark_opacity REAL NOT NULL DEFAULT 0.78,
      watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE app_settings (
      id TEXT NOT NULL PRIMARY KEY DEFAULT 'global',
      theme_mode TEXT NOT NULL DEFAULT 'system',
      locale_code TEXT,
      default_watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
      default_watermark_opacity REAL NOT NULL DEFAULT 0.78,
      default_watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      updated_at INTEGER NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE captures (
      id TEXT NOT NULL PRIMARY KEY,
      project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
      photo_number TEXT,
      work_location TEXT NOT NULL,
      work_content TEXT NOT NULL,
      photographer TEXT NOT NULL,
      notes TEXT,
      original_path TEXT NOT NULL,
      published_uri TEXT,
      original_sha256 TEXT,
      status TEXT NOT NULL,
      failure_reason TEXT,
      created_at INTEGER NOT NULL,
      captured_at INTEGER,
      latitude REAL,
      longitude REAL,
      accuracy_meters REAL,
      address TEXT,
      location_outcome TEXT,
      processing_attempts INTEGER NOT NULL DEFAULT 0
    );
  ''');
  db.execute(
    'INSERT INTO projects VALUES (?, ?, NULL, ?, ?, ?, ?, ?)',
    ['project-1', '东区厂房改造', 'bottomLeft', 0.78, 0xff37c58b,
      projectCreated, projectCreated],
  );
  db.execute(
    'INSERT INTO app_settings VALUES (?, ?, ?, ?, ?, ?, ?)',
    ['global', 'dark', 'en', 'bottomRight', 0.64, 0xff1565c0,
      projectCreated],
  );
  db.execute('''
    INSERT INTO captures (
      id, project_id, photo_number, work_location, work_content, photographer,
      original_path, published_uri, original_sha256, status, created_at,
      captured_at, processing_attempts
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ''', [
    'capture-1', 'project-1', 'SM-20260716-001', 'A 区三层', '风管安装检查',
    '张工', '/private/capture-1.jpg', 'content://media/photo/1',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    CaptureStatus.ready.name, captureCreated, captureCreated, 2,
  ]);
  db.execute('PRAGMA user_version = 3;');
  return NativeDatabase.opened(db, closeUnderlyingOnClose: true);
}
```

Add this test:

```dart
test('v3 to v4 migration preserves rows and adds field-test defaults', () async {
  final database = AppDatabase.forTesting(openMigratedV3Fixture());
  addTearDown(database.close);

  final project = await database.projectById('project-1');
  final capture = await database.captureById('capture-1');
  final settings = await database.getAppSettings();

  expect(project?.name, '东区厂房改造');
  expect(project?.watermarkFontScale, 1.0);
  expect(settings.themeMode, 'dark');
  expect(settings.localeCode, 'en');
  expect(settings.defaultWatermarkFontScale, 1.0);
  expect(settings.locationPermissionPromptDismissed, isFalse);
  expect(capture?.photoNumber, 'SM-20260716-001');
  expect(capture?.processingAttempts, 2);
  expect(capture?.watermarkLocaleCode, 'zh');
  expect(capture?.locationResolution, 'resolved');
  expect(capture?.originalDeletedAt, isNull);
});
```

- [ ] **Step 2: Run the migration test and verify it fails**

Run:

```powershell
flutter test test/data/app_database_migration_test.dart --plain-name "v3 to v4 migration"
```

Expected: FAIL because schema version 3 has no new generated fields.

- [ ] **Step 3: Add the v4 table columns and migration**

Add these columns to their Drift tables:

```dart
// Projects
RealColumn get watermarkFontScale => real().withDefault(const Constant(1.0))();

// AppSettings
RealColumn get defaultWatermarkFontScale =>
    real().withDefault(const Constant(1.0))();
BoolColumn get locationPermissionPromptDismissed =>
    boolean().withDefault(const Constant(false))();

// CaptureRecords
TextColumn get watermarkLocaleCode =>
    text().withDefault(const Constant('zh'))();
TextColumn get locationResolution =>
    text().withDefault(const Constant('resolved'))();
DateTimeColumn get originalDeletedAt => dateTime().nullable()();
```

Set `schemaVersion => 4`, then append this block after the existing `from < 3` block:

```dart
if (from < 4) {
  await migrator.addColumn(projects, projects.watermarkFontScale);
  await migrator.addColumn(
    appSettings,
    appSettings.defaultWatermarkFontScale,
  );
  await migrator.addColumn(
    appSettings,
    appSettings.locationPermissionPromptDismissed,
  );
  await migrator.addColumn(
    captureRecords,
    captureRecords.watermarkLocaleCode,
  );
  await migrator.addColumn(
    captureRecords,
    captureRecords.locationResolution,
  );
  await migrator.addColumn(
    captureRecords,
    captureRecords.originalDeletedAt,
  );
}
```

Remove the existing `_ensureGlobalSettingsRow()` call from inside `if (from < 3)`. After both migration blocks, call it once:

```dart
if (from < 3) {
  await migrator.createTable(appSettings);
  await migrator.addColumn(
    captureRecords,
    captureRecords.processingAttempts,
  );
}
if (from < 4) {
  // six addColumn calls shown above
}
await _ensureGlobalSettingsRow();
```

This order is mandatory for a direct v2→v4 upgrade: the settings insert must not reference v4 columns before those columns exist.

Add both new app-setting defaults to `_ensureGlobalSettingsRow()`:

```dart
defaultWatermarkFontScale: const Value(1.0),
locationPermissionPromptDismissed: const Value(false),
```

- [ ] **Step 4: Regenerate Drift and pass migration tests**

Run:

```powershell
dart run build_runner build --delete-conflicting-outputs
dart format lib/data/app_database.dart test/data/app_database_migration_test.dart
flutter test test/data/app_database_migration_test.dart
```

Expected: all migration tests PASS and only deterministic Drift output changes.

- [ ] **Step 5: Commit the schema migration**

```powershell
git add lib/data/app_database.dart lib/data/app_database.g.dart test/data/app_database_migration_test.dart
git commit -m "feat: add field-test schema foundation"
```

### Task 2: Add Shared v4 Data APIs and Validation

**Files:**
- Modify: `test/data/app_database_test.dart`
- Modify: `lib/data/app_database.dart`
- Regenerate: `lib/data/app_database.g.dart`

**Interfaces:**
- Produces: `createProject(..., double? watermarkFontScale)`
- Produces: `updateProjectWatermarkSettings(..., required double fontScale)`
- Produces: `updateAppSettings(..., double? defaultWatermarkFontScale, bool? locationPermissionPromptDismissed)`
- Produces: `createPendingCapture(..., required String watermarkLocaleCode, String locationResolution = 'pending')`
- Produces: `resolveCaptureLocation(...) -> Future<CaptureRecord>`
- Produces: `markOriginalDeleted(...) -> Future<CaptureRecord>`
- Produces: `capturesByIds(Iterable<String>) -> Future<List<CaptureRecord>>`

- [ ] **Step 1: Write failing database behavior tests**

Append these tests:

```dart
test('persists constrained project and default font scales', () async {
  final project = await database.createProject(
    id: 'project',
    name: '车间改造',
    watermarkFontScale: 1.25,
  );
  expect(project.watermarkFontScale, 1.25);

  final updated = await database.updateProjectWatermarkSettings(
    projectId: 'project',
    position: 'bottomLeft',
    opacity: 0.78,
    accentColorArgb: 0xff37c58b,
    fontScale: 1.60,
  );
  expect(updated.watermarkFontScale, 1.60);
  expect(
    () => database.updateProjectWatermarkSettings(
      projectId: 'project',
      position: 'bottomLeft',
      opacity: 0.78,
      accentColorArgb: 0xff37c58b,
      fontScale: 1.61,
    ),
    throwsArgumentError,
  );

  final settings = await database.updateAppSettings(
    defaultWatermarkFontScale: 0.80,
    locationPermissionPromptDismissed: true,
  );
  expect(settings.defaultWatermarkFontScale, 0.80);
  expect(settings.locationPermissionPromptDismissed, isTrue);
});

test('resolves location and distinguishes intentional original cleanup', () async {
  await database.createProject(id: 'project', name: '车间改造');
  final pending = await database.createPendingCapture(
    id: 'capture-1',
    projectId: 'project',
    originalPath: '/private/capture-1.jpg',
    workLocation: 'A 区',
    workContent: '风管',
    photographer: '张工',
    watermarkLocaleCode: 'en',
  );
  expect(pending.watermarkLocaleCode, 'en');
  expect(pending.locationResolution, 'pending');

  final located = await database.resolveCaptureLocation(
    captureId: pending.id,
    resolution: 'resolved',
    outcome: 'precise',
    latitude: 24.513,
    longitude: 117.6471,
    accuracyMeters: 8,
  );
  expect(located.locationResolution, 'resolved');
  expect(located.latitude, 24.513);

  final deletedAt = DateTime(2026, 7, 16, 12);
  final cleaned = await database.markOriginalDeleted(
    pending.id,
    deletedAt: deletedAt,
  );
  expect(cleaned.originalDeletedAt, deletedAt);
  expect(cleaned.originalSha256, pending.originalSha256);

  final rows = await database.capturesByIds(['capture-1', 'missing']);
  expect(rows.map((row) => row.id), ['capture-1']);
});
```

- [ ] **Step 2: Run the tests and verify the new APIs are missing**

```powershell
flutter test test/data/app_database_test.dart --plain-name "font scales"
flutter test test/data/app_database_test.dart --plain-name "resolves location"
```

Expected: FAIL at compile time for the new parameters and methods.

- [ ] **Step 3: Implement validated create/update methods**

Add `watermarkFontScale` to `createProject`, pass it through `ProjectsCompanion.insert`, and add `fontScale` to `updateProjectWatermarkSettings`. Validate both project and global values through one helper:

```dart
double _validatedFontScale(double value) {
  if (value < 0.80 || value > 1.60) {
    throw ArgumentError.value(value, 'fontScale');
  }
  return value;
}
```

Extend `updateAppSettings` with:

```dart
double? defaultWatermarkFontScale,
bool? locationPermissionPromptDismissed,
```

and companion fields:

```dart
defaultWatermarkFontScale: defaultWatermarkFontScale == null
    ? const Value.absent()
    : Value(_validatedFontScale(defaultWatermarkFontScale)),
locationPermissionPromptDismissed: locationPermissionPromptDismissed == null
    ? const Value.absent()
    : Value(locationPermissionPromptDismissed),
```

- [ ] **Step 4: Implement capture snapshot, location, cleanup, and ID methods**

Make `watermarkLocaleCode` required in `createPendingCapture`, validate it, and explicitly write `locationResolution`:

```dart
if (!{'zh', 'en'}.contains(watermarkLocaleCode)) {
  throw ArgumentError.value(watermarkLocaleCode, 'watermarkLocaleCode');
}
if (!{'pending', 'resolved', 'unavailable'}.contains(locationResolution)) {
  throw ArgumentError.value(locationResolution, 'locationResolution');
}
```

Add these methods:

```dart
Future<CaptureRecord> resolveCaptureLocation({
  required String captureId,
  required String resolution,
  required String outcome,
  double? latitude,
  double? longitude,
  double? accuracyMeters,
  String? address,
}) async {
  if (!{'resolved', 'unavailable'}.contains(resolution)) {
    throw ArgumentError.value(resolution, 'resolution');
  }
  await (update(captureRecords)..where((row) => row.id.equals(captureId))).write(
    CaptureRecordsCompanion(
      locationResolution: Value(resolution),
      locationOutcome: Value(outcome),
      latitude: Value(latitude),
      longitude: Value(longitude),
      accuracyMeters: Value(accuracyMeters),
      address: Value(address),
    ),
  );
  return captureById(captureId).then((row) => row!);
}

Future<CaptureRecord> markOriginalDeleted(
  String captureId, {
  DateTime? deletedAt,
}) async {
  await (update(captureRecords)..where((row) => row.id.equals(captureId))).write(
    CaptureRecordsCompanion(
      originalDeletedAt: Value(deletedAt ?? DateTime.now()),
    ),
  );
  return captureById(captureId).then((row) => row!);
}

Future<List<CaptureRecord>> capturesByIds(Iterable<String> captureIds) {
  final ids = captureIds.toSet().toList(growable: false);
  if (ids.isEmpty) return Future.value(const []);
  return (select(captureRecords)
        ..where((row) => row.id.isIn(ids))
        ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
      .get();
}
```

- [ ] **Step 5: Update existing call sites with explicit compatibility values**

Until the watermark plan supplies the resolved UI locale, update every current `createPendingCapture` call in production and tests with:

```dart
watermarkLocaleCode: 'zh',
```

Update every `updateProjectWatermarkSettings` call with the current stored scale, and update project creation from global defaults to pass `settings.defaultWatermarkFontScale`.

- [ ] **Step 6: Regenerate and run the focused suite**

```powershell
dart run build_runner build --delete-conflicting-outputs
dart format lib test
flutter test test/data/app_database_test.dart test/data/app_database_migration_test.dart
flutter analyze
```

Expected: tests PASS and analysis reports no issues.

- [ ] **Step 7: Commit the shared data APIs**

```powershell
git add lib/data test/data lib/features/projects/project_form_screen.dart
git commit -m "feat: add field-test data APIs"
```

### Task 3: Foundation Verification Gate

**Files:**
- Verify only; modify files only if formatting or generated output is stale.

**Interfaces:**
- Consumes: all schema v4 fields and methods from Tasks 1–2.
- Produces: a clean, compiling base for the four feature plans.

- [ ] **Step 1: Verify generated files and repository cleanliness**

```powershell
dart run build_runner build --delete-conflicting-outputs
git diff --check
git status --short
```

Expected: no uncommitted generated Drift diff and no whitespace errors.

- [ ] **Step 2: Run the full Flutter baseline**

```powershell
flutter test
flutter analyze
```

Expected: all tests PASS and analysis reports no issues before feature work begins.
