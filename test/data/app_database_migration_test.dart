import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sqlite3/sqlite3.dart';

/// Opens a raw in-memory sqlite database, creates the genuine v2 schema (no
/// `processing_attempts` column on `captures`, no `app_settings` table), seeds
/// one project and one `failed` capture, and sets `PRAGMA user_version = 2`.
///
/// The capture is seeded as `failed` (rather than a terminal success state
/// like `ready`) so that the migrated row remains retryable: a `ready` capture
/// is terminal and cannot be driven through `resetCaptureForRetry`, whereas a
/// `failed` capture can transition back to `captured`.
///
/// Returning a drift [QueryExecutor] over that pre-seeded connection means
/// [AppDatabase.forTesting] will read `user_version = 2` and run the real
/// `onUpgrade` path from v2 up to the current `schemaVersion`.
QueryExecutor openMigratedV2Fixture() {
  final db = sqlite3.openInMemory();

  // Drift stores DateTime as integer unix seconds by default
  // (millisecondsSinceEpoch ~/ 1000).
  final projectCreated =
      DateTime.utc(2026, 7, 16).millisecondsSinceEpoch ~/ 1000;
  final captureCreated =
      DateTime(2026, 7, 16, 9, 30).millisecondsSinceEpoch ~/ 1000;
  final captureCaptured =
      DateTime(2026, 7, 16, 9, 32).millisecondsSinceEpoch ~/ 1000;

  db.execute('''
    CREATE TABLE projects (
      id TEXT NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
      watermark_opacity REAL NOT NULL DEFAULT 0.78,
      watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (id)
    );
  ''');

  // The v2 captures table intentionally lacks `processing_attempts`.
  db.execute('''
    CREATE TABLE captures (
      id TEXT NOT NULL,
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
      PRIMARY KEY (id)
    );
  ''');

  db.execute(
    '''
    INSERT INTO projects (
      id, name, description, watermark_position, watermark_opacity,
      watermark_accent_color_argb, created_at, updated_at
    ) VALUES (?, ?, NULL, ?, ?, ?, ?, ?);
  ''',
    [
      'project-1',
      '东区厂房改造',
      'bottomLeft',
      0.78,
      0xff37c58b,
      projectCreated,
      projectCreated,
    ],
  );

  db.execute(
    '''
    INSERT INTO captures (
      id, project_id, photo_number, work_location, work_content, photographer,
      notes, original_path, published_uri, original_sha256, status,
      failure_reason, created_at, captured_at, latitude, longitude,
      accuracy_meters, address, location_outcome
    ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, NULL, ?, ?, NULL, NULL, NULL, NULL, NULL);
  ''',
    [
      'capture-1',
      'project-1',
      'SM-20260716-001',
      'A 区三层',
      '风管安装检查',
      '张工',
      '/private/capture-1.jpg',
      'content://media/photo/1',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      CaptureStatus.failed.name,
      captureCreated,
      captureCaptured,
    ],
  );

  db.execute('PRAGMA user_version = 2;');

  return NativeDatabase.opened(db, closeUnderlyingOnClose: true);
}

/// Opens a raw in-memory sqlite database with the genuine v3 schema (including
/// `processing_attempts` and `app_settings`), seeds one project, one `ready`
/// capture, and one `global` settings row, then sets `PRAGMA user_version = 3`.
///
/// Returning a drift [QueryExecutor] over that pre-seeded connection means
/// [AppDatabase.forTesting] will read `user_version = 3` and run the real
/// `onUpgrade` path from v3 up to the current `schemaVersion`.
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
  db.execute('INSERT INTO projects VALUES (?, ?, NULL, ?, ?, ?, ?, ?)', [
    'project-1',
    '东区厂房改造',
    'bottomLeft',
    0.78,
    0xff37c58b,
    projectCreated,
    projectCreated,
  ]);
  db.execute('INSERT INTO app_settings VALUES (?, ?, ?, ?, ?, ?, ?)', [
    'global',
    'dark',
    'en',
    'bottomRight',
    0.64,
    0xff1565c0,
    projectCreated,
  ]);
  db.execute(
    '''
    INSERT INTO captures (
      id, project_id, photo_number, work_location, work_content, photographer,
      original_path, published_uri, original_sha256, status, created_at,
      captured_at, processing_attempts
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ''',
    [
      'capture-1',
      'project-1',
      'SM-20260716-001',
      'A 区三层',
      '风管安装检查',
      '张工',
      '/private/capture-1.jpg',
      'content://media/photo/1',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      CaptureStatus.ready.name,
      captureCreated,
      captureCreated,
      2,
    ],
  );
  db.execute('PRAGMA user_version = 3;');
  return NativeDatabase.opened(db, closeUnderlyingOnClose: true);
}

/// Opens a raw in-memory sqlite database with the genuine v4 schema (the v3
/// shape plus `watermark_font_scale`, `location_permission_prompt_dismissed`,
/// `watermark_locale_code`, `location_resolution`, and `original_deleted_at`,
/// but without the v5 `use_dynamic_color` and
/// `completion_notifications_enabled` columns on `app_settings`), seeds one
/// project, one `ready` capture, and one `global` settings row, then sets
/// `PRAGMA user_version = 4`.
///
/// Returning a drift [QueryExecutor] over that pre-seeded connection means
/// [AppDatabase.forTesting] will read `user_version = 4` and run the real
/// `onUpgrade(migrator, 4, 5)` path.
QueryExecutor openMigratedV4Fixture() {
  final db = sqlite3.openInMemory();
  final projectCreated =
      DateTime.utc(2026, 7, 16).millisecondsSinceEpoch ~/ 1000;
  final captureCreated =
      DateTime(2026, 7, 16, 9, 30).millisecondsSinceEpoch ~/ 1000;
  final captureCaptured =
      DateTime(2026, 7, 16, 9, 32).millisecondsSinceEpoch ~/ 1000;

  db.execute('''
    CREATE TABLE projects (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
      watermark_opacity REAL NOT NULL DEFAULT 0.78,
      watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      watermark_font_scale REAL NOT NULL DEFAULT 1.0,
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
      default_watermark_font_scale REAL NOT NULL DEFAULT 1.0,
      location_permission_prompt_dismissed INTEGER NOT NULL DEFAULT 0,
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
      processing_attempts INTEGER NOT NULL DEFAULT 0,
      watermark_locale_code TEXT NOT NULL DEFAULT 'zh',
      location_resolution TEXT NOT NULL DEFAULT 'resolved',
      original_deleted_at INTEGER
    );
  ''');
  db.execute('INSERT INTO projects VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?)', [
    'project-1',
    '东区厂房改造',
    'bottomLeft',
    0.78,
    0xff37c58b,
    1.25,
    projectCreated,
    projectCreated,
  ]);
  db.execute('INSERT INTO app_settings VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', [
    'global',
    'dark',
    'en',
    'bottomRight',
    0.64,
    0xff1565c0,
    1.40,
    1,
    projectCreated,
  ]);
  db.execute(
    '''
    INSERT INTO captures (
      id, project_id, photo_number, work_location, work_content, photographer,
      original_path, published_uri, original_sha256, status, created_at,
      captured_at, processing_attempts, watermark_locale_code,
      location_resolution, original_deleted_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ''',
    [
      'capture-1',
      'project-1',
      'SM-20260716-001',
      'A 区三层',
      '风管安装检查',
      '张工',
      '/private/capture-1.jpg',
      'content://media/photo/1',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      CaptureStatus.ready.name,
      captureCreated,
      captureCaptured,
      2,
      'en',
      'resolved',
      captureCaptured,
    ],
  );
  db.execute('PRAGMA user_version = 4;');
  return NativeDatabase.opened(db, closeUnderlyingOnClose: true);
}

/// Opens a raw in-memory sqlite database with the perf/smoothness branch's
/// v5 schema: the v4 table shapes plus the three capture performance indexes,
/// but WITHOUT the `use_dynamic_color` and `completion_notifications_enabled`
/// columns on `app_settings`. Sets `PRAGMA user_version = 5` so
/// [AppDatabase.forTesting] runs `onUpgrade(migrator, 5, 6)`, which must
/// detect the missing columns via `PRAGMA table_info` and add them before
/// `_ensureGlobalSettingsRow()` inserts the global row.
QueryExecutor openMigratedPerfV5Fixture() {
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
      watermark_font_scale REAL NOT NULL DEFAULT 1.0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
  ''');
  // Intentionally omits use_dynamic_color and completion_notifications_enabled
  // to mirror the perf/smoothness branch's v5 app_settings shape.
  db.execute('''
    CREATE TABLE app_settings (
      id TEXT NOT NULL PRIMARY KEY DEFAULT 'global',
      theme_mode TEXT NOT NULL DEFAULT 'system',
      locale_code TEXT,
      default_watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
      default_watermark_opacity REAL NOT NULL DEFAULT 0.78,
      default_watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      default_watermark_font_scale REAL NOT NULL DEFAULT 1.0,
      location_permission_prompt_dismissed INTEGER NOT NULL DEFAULT 0,
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
      processing_attempts INTEGER NOT NULL DEFAULT 0,
      watermark_locale_code TEXT NOT NULL DEFAULT 'zh',
      location_resolution TEXT NOT NULL DEFAULT 'resolved',
      original_deleted_at INTEGER
    );
  ''');
  // The perf branch's v5 migration created these indexes.
  db.execute(
    'CREATE INDEX capture_records_status_idx ON captures (status)',
  );
  db.execute(
    'CREATE INDEX capture_records_sort_idx '
    'ON captures (COALESCE(captured_at, created_at) DESC)',
  );
  db.execute(
    'CREATE INDEX capture_records_project_sort_idx '
    'ON captures (project_id, COALESCE(captured_at, created_at) DESC)',
  );
  db.execute('INSERT INTO projects VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?)', [
    'project-1',
    '东区厂房改造',
    'bottomLeft',
    0.78,
    0xff37c58b,
    1.0,
    projectCreated,
    projectCreated,
  ]);
  db.execute('INSERT INTO app_settings VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', [
    'global',
    'dark',
    'en',
    'bottomRight',
    0.64,
    0xff1565c0,
    1.0,
    1,
    projectCreated,
  ]);
  db.execute(
    '''
    INSERT INTO captures (
      id, project_id, photo_number, work_location, work_content, photographer,
      original_path, published_uri, original_sha256, status, created_at,
      captured_at, processing_attempts, watermark_locale_code,
      location_resolution
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ''',
    [
      'capture-1',
      'project-1',
      'SM-20260716-001',
      'A 区三层',
      '风管安装检查',
      '张工',
      '/private/capture-1.jpg',
      'content://media/photo/1',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      CaptureStatus.ready.name,
      captureCreated,
      captureCreated,
      2,
      'en',
      'resolved',
    ],
  );
  db.execute('PRAGMA user_version = 5;');
  return NativeDatabase.opened(db, closeUnderlyingOnClose: true);
}

Future<Map<String, String>> captureIndexes(AppDatabase database) async {
  final rows = await database.customSelect('''
        SELECT name, sql
        FROM sqlite_master
        WHERE type = 'index' AND tbl_name = 'captures' AND sql IS NOT NULL
        ORDER BY name
      ''').get();
  return {
    for (final row in rows) row.read<String>('name'): row.read<String>('sql'),
  };
}

String _normalizedSql(String sql) =>
    sql.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

Future<void> expectCaptureIndexes(AppDatabase database) async {
  final indexes = await captureIndexes(database);
  expect(indexes.keys, {
    'capture_records_project_sort_idx',
    'capture_records_sort_idx',
    'capture_records_status_idx',
  });
  expect(
    _normalizedSql(indexes['capture_records_status_idx']!),
    'create index capture_records_status_idx on captures (status)',
  );
  expect(
    _normalizedSql(indexes['capture_records_sort_idx']!),
    'create index capture_records_sort_idx on captures '
    '(coalesce(captured_at, created_at) desc)',
  );
  expect(
    _normalizedSql(indexes['capture_records_project_sort_idx']!),
    'create index capture_records_project_sort_idx on captures '
    '(project_id, coalesce(captured_at, created_at) desc)',
  );
}

void main() {
  test('v2 migration preserves captures and inserts defaults', () async {
    final database = AppDatabase.forTesting(openMigratedV2Fixture());
    addTearDown(database.close);

    final project = await database.projectById('project-1');
    final capture = await database.captureById('capture-1');
    final settings = await database.watchAppSettings().first;

    expect(project?.name, '东区厂房改造');
    expect(capture?.photoNumber, 'SM-20260716-001');
    expect(capture?.processingAttempts, 0);
    expect(settings.themeMode, 'system');
    expect(settings.localeCode, isNull);
    expect(settings.defaultWatermarkPosition, 'bottomLeft');
    expect(settings.defaultWatermarkOpacity, 0.78);
    expect(settings.defaultWatermarkAccentColorArgb, 0xff37c58b);
    expect(settings.useDynamicColor, isFalse);
    expect(settings.completionNotificationsEnabled, isFalse);
  });

  test(
    'v4 to v6 migration preserves rows and creates capture indexes',
    () async {
      final database = AppDatabase.forTesting(openMigratedV4Fixture());
      addTearDown(database.close);

      final project = await database.projectById('project-1');
      final capture = await database.captureById('capture-1');
      final settings = await database.getAppSettings();

      expect(project?.name, '东区厂房改造');
      expect(project?.watermarkFontScale, 1.25);
      expect(capture?.photoNumber, 'SM-20260716-001');
      expect(capture?.originalDeletedAt, DateTime(2026, 7, 16, 9, 32));
      expect(settings.themeMode, 'dark');
      expect(settings.defaultWatermarkFontScale, 1.40);
      expect(settings.locationPermissionPromptDismissed, isTrue);
      await expectCaptureIndexes(database);
    },
  );

  test(
    'v4 to v5 migration preserves rows and adds motion-platform defaults',
    () async {
      final database = AppDatabase.forTesting(openMigratedV4Fixture());
      addTearDown(database.close);

      final project = await database.projectById('project-1');
      final capture = await database.captureById('capture-1');
      final settings = await database.getAppSettings();

      expect(project?.name, '东区厂房改造');
      expect(project?.watermarkFontScale, 1.25);
      expect(settings.themeMode, 'dark');
      expect(settings.localeCode, 'en');
      expect(settings.defaultWatermarkFontScale, 1.40);
      expect(settings.locationPermissionPromptDismissed, isTrue);
      expect(settings.useDynamicColor, isFalse);
      expect(settings.completionNotificationsEnabled, isFalse);
      expect(capture?.photoNumber, 'SM-20260716-001');
      expect(capture?.processingAttempts, 2);
      expect(capture?.watermarkLocaleCode, 'en');

      final updated = await database.updateAppSettings(
        useDynamicColor: true,
        completionNotificationsEnabled: true,
      );
      expect(updated.useDynamicColor, isTrue);
      expect(updated.completionNotificationsEnabled, isTrue);
      expect(updated.themeMode, 'dark');
    },
  );

  test(
    'v4 to v6 migration creates capture performance indexes',
    () async {
      final database = AppDatabase.forTesting(openMigratedV4Fixture());
      addTearDown(database.close);

      // Force the migration to run by reading a row.
      await database.getAppSettings();

      final indexes = await database.customSelect(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'index' AND name LIKE 'capture_records_%_idx'",
      ).get();
      final indexNames = indexes.map((row) => row.read<String>('name')).toSet();
      expect(
        indexNames,
        containsAll(const <String>{
          'capture_records_status_idx',
          'capture_records_sort_idx',
          'capture_records_project_sort_idx',
        }),
      );
    },
  );

  test(
    'perf-branch v5 to v6 migration adds missing dynamic-color columns',
    () async {
      // The perf/smoothness branch shipped a v5 schema with the capture
      // indexes but WITHOUT use_dynamic_color / completion_notifications_enabled
      // on app_settings. Upgrading to v6 must detect the missing columns via
      // PRAGMA table_info and add them, otherwise _ensureGlobalSettingsRow()
      // crashes with "no column named use_dynamic_color".
      final database = AppDatabase.forTesting(openMigratedPerfV5Fixture());
      addTearDown(database.close);

      // Forces onUpgrade(5, 6) + _ensureGlobalSettingsRow() to run.
      final settings = await database.getAppSettings();

      expect(settings.id, 'global');
      expect(settings.themeMode, 'dark');
      expect(settings.useDynamicColor, isFalse);
      expect(settings.completionNotificationsEnabled, isFalse);

      // Existing data is preserved.
      final project = await database.projectById('project-1');
      expect(project?.name, '东区厂房改造');
      final capture = await database.captureById('capture-1');
      expect(capture?.photoNumber, 'SM-20260716-001');

      // The settings row can be updated through the new columns.
      final updated = await database.updateAppSettings(
        useDynamicColor: true,
        completionNotificationsEnabled: true,
      );
      expect(updated.useDynamicColor, isTrue);
      expect(updated.completionNotificationsEnabled, isTrue);

      // Indexes are still present (idempotent re-creation).
      final indexes = await database.customSelect(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'index' AND name LIKE 'capture_records_%_idx'",
      ).get();
      final indexNames = indexes.map((row) => row.read<String>('name')).toSet();
      expect(
        indexNames,
        containsAll(const <String>{
          'capture_records_status_idx',
          'capture_records_sort_idx',
          'capture_records_project_sort_idx',
        }),
      );
    },
  );

  test(
    'v2 to v3 migration allows increments and retries on upgraded rows',
    () async {
      final database = AppDatabase.forTesting(openMigratedV2Fixture());
      addTearDown(database.close);

      final bumped = await database.incrementProcessingAttempts('capture-1');
      expect(bumped.processingAttempts, 1);

      final settings = await database.watchAppSettings().first;
      final updated = await database.updateAppSettings(themeMode: 'light');
      expect(settings.themeMode, 'system');
      expect(updated.themeMode, 'light');

      // A `failed` capture (seeded as such in the fixture) can be retried back
      // to `captured`, preserving evidence and resetting attempts to 0.
      final retried = await database.resetCaptureForRetry('capture-1');
      expect(retried.processingAttempts, 0);
      expect(retried.status, CaptureStatus.captured);
      expect(retried.publishedUri, 'content://media/photo/1');
      expect(
        retried.originalSha256,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
    },
  );

  test(
    'fresh database still inserts default app settings on first open',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final settings = await database.watchAppSettings().first;

      expect(settings.id, 'global');
      expect(settings.themeMode, 'system');
      expect(settings.localeCode, isNull);
      expect(settings.defaultWatermarkPosition, 'bottomLeft');
      expect(settings.defaultWatermarkOpacity, 0.78);
      expect(settings.defaultWatermarkAccentColorArgb, 0xff37c58b);
      expect(settings.useDynamicColor, isFalse);
      expect(settings.completionNotificationsEnabled, isFalse);
    },
  );

  test('fresh database creates all capture indexes', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await expectCaptureIndexes(database);
  });
}
