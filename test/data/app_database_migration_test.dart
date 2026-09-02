import 'package:drift/drift.dart' show QueryExecutor, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/nas_sync_database.dart';
import 'package:sitemark/domain/nas_sync.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
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
  db.execute('CREATE INDEX capture_records_status_idx ON captures (status)');
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

/// Opens a raw in-memory sqlite database with the genuine v10 schema (including
/// capture templates, no lifecycle columns), seeds one project, and sets
/// `PRAGMA user_version = 10`.
QueryExecutor openMigratedV10Fixture() {
  final db = buildV10Schema();
  db.execute('PRAGMA user_version = 10;');
  return NativeDatabase.opened(db, closeUnderlyingOnClose: true);
}

/// Opens a raw in-memory sqlite database with the genuine v11 schema: the v10
/// shape plus the project lifecycle columns added by the v10→v11 migration.
/// `PRAGMA user_version = 11`, so [AppDatabase.forTesting] exercises ONLY the
/// v11→v12 upgrade (the superseded-cleanup queue) rather than the whole chain.
QueryExecutor openMigratedV11Fixture() {
  final db = buildV10Schema();
  // Exactly what drift's v10→v11 `addColumn` emitted (ALTER TABLE ADD COLUMN),
  // so this fixture is byte-compatible with a real upgraded v11 database.
  db.execute(
    "ALTER TABLE projects ADD COLUMN lifecycle_status TEXT NOT NULL "
    "DEFAULT 'active' CHECK (lifecycle_status IN "
    "('active', 'completed', 'archived'));",
  );
  db.execute(
    'ALTER TABLE projects ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;',
  );
  db.execute('PRAGMA user_version = 11;');
  return NativeDatabase.opened(db, closeUnderlyingOnClose: true);
}

/// Opens a raw in-memory sqlite database with the genuine v12 schema: the
/// v11 shape plus the v12 superseded-cleanup queue WITHOUT the v13 retry
/// columns, with one seeded pending task. `PRAGMA user_version = 12`, so
/// [AppDatabase.forTesting] exercises ONLY the v12→v13 upgrade (the retry
/// budget columns) rather than the whole chain.
QueryExecutor openMigratedV12Fixture() {
  final db = sqlite3.openInMemory();
  final projectCreated =
      DateTime.utc(2026, 8, 3).millisecondsSinceEpoch ~/ 1000;

  // The v11 table shapes (projects with lifecycle columns + full v10 set).
  // Inline rather than reusing buildV10Schema so the seeded cleanup task can
  // share the fixture's timestamps.
  db.execute('''
    CREATE TABLE projects (
      id TEXT NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      restore_operation_id TEXT,
      watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
      watermark_opacity REAL NOT NULL DEFAULT 0.78,
      watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      watermark_font_scale REAL NOT NULL DEFAULT 1.0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      lifecycle_status TEXT NOT NULL DEFAULT 'active',
      is_pinned INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (id)
    );
  ''');
  db.execute('''
    CREATE TABLE app_settings (
      id TEXT NOT NULL,
      theme_mode TEXT NOT NULL DEFAULT 'system',
      locale_code TEXT,
      default_watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
      default_watermark_opacity REAL NOT NULL DEFAULT 0.78,
      default_watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      default_watermark_font_scale REAL NOT NULL DEFAULT 1.0,
      location_permission_prompt_dismissed INTEGER NOT NULL DEFAULT 0,
      use_dynamic_color INTEGER NOT NULL DEFAULT 0,
      completion_notifications_enabled INTEGER NOT NULL DEFAULT 0,
      app_seed_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (id)
    );
  ''');
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
      processing_attempts INTEGER NOT NULL DEFAULT 0,
      watermark_locale_code TEXT NOT NULL DEFAULT 'zh',
      location_resolution TEXT NOT NULL DEFAULT 'resolved',
      original_deleted_at INTEGER,
      PRIMARY KEY (id)
    );
  ''');
  db.execute('''
    CREATE TABLE capture_templates (
      id TEXT NOT NULL,
      project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      name_key TEXT NOT NULL,
      work_location TEXT NOT NULL,
      work_content TEXT NOT NULL,
      photographer TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (id),
      UNIQUE (project_id, name_key)
    );
  ''');
  // Exactly the v12 queue shape: no retry_count / last_attempt_at / stalled_at.
  db.execute('''
    CREATE TABLE capture_media_cleanups (
      published_uri TEXT NOT NULL,
      capture_id TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (published_uri)
    );
  ''');
  db.execute(
    "INSERT INTO projects (id, name, created_at, updated_at) "
    "VALUES ('existing', '既有项目', $projectCreated, $projectCreated);",
  );
  db.execute(
    "INSERT INTO app_settings (id, updated_at) VALUES ('global', $projectCreated);",
  );
  // One pending cleanup task from a real v12 install.
  db.execute(
    "INSERT INTO capture_media_cleanups (published_uri, capture_id, created_at) "
    "VALUES ('content://media/site-mark/1', 'capture-1', $projectCreated);",
  );
  db.execute('PRAGMA user_version = 12;');
  return NativeDatabase.opened(db, closeUnderlyingOnClose: true);
}

/// Builds the v10 table shapes and seed rows WITHOUT stamping a user version.
Database buildV10Schema() {
  final db = sqlite3.openInMemory();
  final projectCreated =
      DateTime.utc(2026, 8, 3).millisecondsSinceEpoch ~/ 1000;

  db.execute('''
    CREATE TABLE projects (
      id TEXT NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      restore_operation_id TEXT,
      watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
      watermark_opacity REAL NOT NULL DEFAULT 0.78,
      watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      watermark_font_scale REAL NOT NULL DEFAULT 1.0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (id)
    );
  ''');
  db.execute('''
    CREATE TABLE app_settings (
      id TEXT NOT NULL,
      theme_mode TEXT NOT NULL DEFAULT 'system',
      locale_code TEXT,
      default_watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
      default_watermark_opacity REAL NOT NULL DEFAULT 0.78,
      default_watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      default_watermark_font_scale REAL NOT NULL DEFAULT 1.0,
      location_permission_prompt_dismissed INTEGER NOT NULL DEFAULT 0,
      use_dynamic_color INTEGER NOT NULL DEFAULT 0,
      completion_notifications_enabled INTEGER NOT NULL DEFAULT 0,
      app_seed_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (id)
    );
  ''');
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
      processing_attempts INTEGER NOT NULL DEFAULT 0,
      watermark_locale_code TEXT NOT NULL DEFAULT 'zh',
      location_resolution TEXT NOT NULL DEFAULT 'resolved',
      original_deleted_at INTEGER,
      PRIMARY KEY (id)
    );
  ''');
  db.execute('''
    CREATE TABLE capture_templates (
      id TEXT NOT NULL,
      project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      name_key TEXT NOT NULL,
      work_location TEXT NOT NULL,
      work_content TEXT NOT NULL,
      photographer TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (id),
      UNIQUE (project_id, name_key)
    );
  ''');
  db.execute(
    "INSERT INTO projects (id, name, created_at, updated_at) "
    "VALUES ('existing', '既有项目', $projectCreated, $projectCreated);",
  );
  db.execute(
    "INSERT INTO app_settings (id, updated_at) VALUES ('global', $projectCreated);",
  );
  // A genuine capture row so migrations that walk captures (and the v12
  // superseded-cleanup queue) can be driven with a REAL capture ID —
  // passing the project ID where a capture ID is expected crashes on the
  // `row!` null assertion.
  db.execute('''
    INSERT INTO captures (
      id, project_id, photo_number, work_location, work_content, photographer,
      original_path, published_uri, status, created_at
    ) VALUES (
      'capture-1', 'existing', 'SM-20260803-001', 'A 区三层', '风管安装检查',
      '张工', '/private/capture-1.jpg', 'content://media/site-mark/1',
      'ready', $projectCreated
    );
  ''');
  return db;
}

/// Opens the v8 table shapes and index set, then lets the current database
/// implementation run the real v8 upgrade path.
QueryExecutor openV8AndUpgrade() {
  final db = sqlite3.openInMemory();
  db.execute('''
    CREATE TABLE projects (
      id TEXT NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      restore_operation_id TEXT,
      watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
      watermark_opacity REAL NOT NULL DEFAULT 0.78,
      watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      watermark_font_scale REAL NOT NULL DEFAULT 1.0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (id)
    );
  ''');
  db.execute('''
    CREATE TABLE app_settings (
      id TEXT NOT NULL,
      theme_mode TEXT NOT NULL DEFAULT 'system',
      locale_code TEXT,
      default_watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
      default_watermark_opacity REAL NOT NULL DEFAULT 0.78,
      default_watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      default_watermark_font_scale REAL NOT NULL DEFAULT 1.0,
      location_permission_prompt_dismissed INTEGER NOT NULL DEFAULT 0,
      use_dynamic_color INTEGER NOT NULL DEFAULT 0,
      completion_notifications_enabled INTEGER NOT NULL DEFAULT 0,
      app_seed_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (id)
    );
  ''');
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
      processing_attempts INTEGER NOT NULL DEFAULT 0,
      watermark_locale_code TEXT NOT NULL DEFAULT 'zh',
      location_resolution TEXT NOT NULL DEFAULT 'resolved',
      original_deleted_at INTEGER,
      PRIMARY KEY (id)
    );
  ''');
  db.execute('CREATE INDEX capture_records_status_idx ON captures (status)');
  db.execute(
    'CREATE INDEX capture_records_sort_idx '
    'ON captures (COALESCE(captured_at, created_at) DESC)',
  );
  db.execute(
    'CREATE INDEX capture_records_project_sort_idx '
    'ON captures (project_id, COALESCE(captured_at, created_at) DESC)',
  );
  db.execute('PRAGMA user_version = 8;');
  return NativeDatabase.opened(db, closeUnderlyingOnClose: true);
}

Future<Map<String, String>> indexSql(
  AppDatabase database,
  String pattern,
) async {
  final rows = await database
      .customSelect(
        'SELECT name, sql FROM sqlite_master '
        'WHERE type = \'index\' AND name LIKE ? AND sql IS NOT NULL '
        'ORDER BY name',
        variables: [Variable.withString(pattern)],
      )
      .get();
  return {
    for (final row in rows) row.read<String>('name'): row.read<String>('sql'),
  };
}

String normalizedSql(String sql) =>
    sql.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

Future<void> expectCaptureIndexes(AppDatabase database) async {
  final indexes = await captureIndexes(database);
  expect(indexes.keys, {
    'capture_records_project_sort_idx',
    'capture_records_project_sort_cursor_idx',
    'capture_records_sort_idx',
    'capture_records_sort_cursor_idx',
    'capture_records_status_idx',
  });
  expect(
    normalizedSql(indexes['capture_records_status_idx']!),
    'create index capture_records_status_idx on captures (status)',
  );
  expect(
    normalizedSql(indexes['capture_records_sort_idx']!),
    'create index capture_records_sort_idx on captures '
    '(coalesce(captured_at, created_at) desc)',
  );
  expect(
    normalizedSql(indexes['capture_records_project_sort_idx']!),
    'create index capture_records_project_sort_idx on captures '
    '(project_id, coalesce(captured_at, created_at) desc)',
  );
  expect(
    normalizedSql(indexes['capture_records_sort_cursor_idx']!),
    'create index capture_records_sort_cursor_idx on captures '
    '(coalesce(captured_at, created_at) desc, id desc)',
  );
  expect(
    normalizedSql(indexes['capture_records_project_sort_cursor_idx']!),
    'create index capture_records_project_sort_cursor_idx on captures '
    '(project_id, coalesce(captured_at, created_at) desc, id desc)',
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

  test('v4 to v6 migration creates capture performance indexes', () async {
    final database = AppDatabase.forTesting(openMigratedV4Fixture());
    addTearDown(database.close);

    // Force the migration to run by reading a row.
    await database.getAppSettings();

    final indexes = await database
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'index' AND name LIKE 'capture_records_%_idx'",
        )
        .get();
    final indexNames = indexes.map((row) => row.read<String>('name')).toSet();
    expect(
      indexNames,
      containsAll(const <String>{
        'capture_records_status_idx',
        'capture_records_sort_idx',
        'capture_records_project_sort_idx',
      }),
    );
  });

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
      final indexes = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'index' AND name LIKE 'capture_records_%_idx'",
          )
          .get();
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

  test('v8 to v9 creates stable cursor indexes', () async {
    final database = AppDatabase.forTesting(openV8AndUpgrade());
    addTearDown(database.close);

    final indexes = await indexSql(database, 'capture_records_%_cursor_idx');
    expect(
      indexes.keys,
      containsAll({
        'capture_records_sort_cursor_idx',
        'capture_records_project_sort_cursor_idx',
      }),
    );
    expect(
      normalizedSql(indexes['capture_records_sort_cursor_idx']!),
      contains('coalesce(captured_at, created_at) desc, id desc'),
    );
  });

  test('v10 to v11 migration adds lifecycle defaults', () async {
    final database = AppDatabase.forTesting(openMigratedV10Fixture());
    addTearDown(database.close);

    expect(database.schemaVersion, 14);
    final project = await database.projectById('existing');
    expect(project!.lifecycleStatus, ProjectLifecycleStatus.active);
    expect(project.isPinned, isFalse);
  });

  test('v11 to v12 migration creates the superseded cleanup queue', () async {
    final database = AppDatabase.forTesting(openMigratedV11Fixture());
    addTearDown(database.close);

    expect(database.schemaVersion, 14);
    // The v11 lifecycle columns survive the v11→v12-only upgrade path.
    final project = await database.projectById('existing');
    expect(project!.lifecycleStatus, ProjectLifecycleStatus.active);
    expect(project.isPinned, isFalse);

    // The queue table exists and one row per stale URI is enforced by the
    // URI primary key: re-enqueueing the same URI updates it in place.
    // Uses the fixture's REAL capture row — a missing row crashes on the
    // `row!` null assertion inside updatePublishedUri.
    await database.updatePublishedUri(
      'capture-1',
      'content://media/site-mark/2',
      expectedPreviousUri: 'content://media/site-mark/1',
      supersededUris: [
        'content://media/site-mark/1',
        'content://media/site-mark/1',
      ],
    );
    final tasks = await database.pendingSupersededCleanups();
    expect(tasks, hasLength(1));
    expect(tasks.single.publishedUri, 'content://media/site-mark/1');
    expect(tasks.single.captureId, 'capture-1');

    await database.completeSupersededCleanup('content://media/site-mark/1');
    expect(await database.pendingSupersededCleanups(), isEmpty);
  });

  test('v12 to v13 migration adds the cleanup retry budget', () async {
    final database = AppDatabase.forTesting(openMigratedV12Fixture());
    addTearDown(database.close);

    expect(database.schemaVersion, 14);

    // The seeded v12 task survives with a FULL budget: retry count 0 and
    // not stalled, so automatic processing keeps serving it.
    final pending = await database.pendingSupersededCleanups();
    expect(pending, hasLength(1));
    expect(pending.single.publishedUri, 'content://media/site-mark/1');
    expect(pending.single.captureId, 'capture-1');
    expect(pending.single.retryCount, 0);
    expect(pending.single.lastAttemptAt, isNull);
    expect(pending.single.stalledAt, isNull);

    // The new columns are live: a recorded failure bumps the count and
    // stamps the attempt without stalling (budget not yet exhausted).
    final updated = await database.recordSupersededCleanupFailure(
      'content://media/site-mark/1',
      maxRetries: 5,
    );
    expect(updated?.retryCount, 1);
    expect(updated?.lastAttemptAt, isNotNull);
    expect(updated?.stalledAt, isNull);
    expect(await database.stalledSupersededCleanups(), isEmpty);
  });

  test('v12 to v14 migration creates the NAS sync tables', () async {
    final database = AppDatabase.forTesting(openMigratedV12Fixture());
    addTearDown(database.close);

    expect(database.schemaVersion, 14);

    // Pre-existing data survives the two-step upgrade.
    expect(
      (await database.projectById('existing'))!.lifecycleStatus,
      ProjectLifecycleStatus.active,
    );

    // Both NAS tables start empty — existing captures are only enqueued
    // once the user enables sync, via the catch-up scan.
    final config = await database.nasSyncConfig();
    expect(config, isNotNull);
    expect(config.enabled, isFalse);
    expect(config.protocol, 'webdav');
    expect(config.wifiOnly, isTrue);
    expect(config.knownSftpFingerprint, isNull);
    expect(await database.allNasUploadStates(), isEmpty);

    // The upload bookkeeping is live: seed one ready capture (the fixture
    // has none) and enqueue it as pending.
    final seededAt = DateTime.utc(2026, 8, 3).millisecondsSinceEpoch ~/ 1000;
    await database.customStatement(
      "INSERT INTO captures (id, project_id, work_location, work_content, "
      "photographer, original_path, status, created_at) VALUES "
      "('capture-nas', 'existing', '部位', '内容', '张三', '/tmp/o.jpg', "
      "'ready', ?)",
      [seededAt],
    );
    await database.upsertNasUploadPending('capture-nas');
    final states = await database.allNasUploadStates();
    expect(states.single.captureId, 'capture-nas');
    expect(states.single.status, NasUploadStatus.pending);
    expect(states.single.attempts, 0);
  });

  test(
    'v10 migration rejects lifecycle values outside the stable enum',
    () async {
      final database = AppDatabase.forTesting(openMigratedV10Fixture());
      addTearDown(database.close);

      await expectLater(
        database.customStatement(
          "UPDATE projects SET lifecycle_status = 'deleted' WHERE id = 'existing'",
        ),
        throwsA(isA<SqliteException>()),
      );

      final project = await database.projectById('existing');
      expect(project?.lifecycleStatus, ProjectLifecycleStatus.active);
    },
  );

  test('fresh database defaults new projects to active unpinned', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    expect(database.schemaVersion, 14);
    final project = await database.createProject(id: 'fresh', name: '新项目');
    expect(project.lifecycleStatus, ProjectLifecycleStatus.active);
    expect(project.isPinned, isFalse);
  });

  test('v6 to v7 migration adds app_seed_color_argb column', () async {
    // Open a genuine v6 schema (with use_dynamic_color and
    // completion_notifications_enabled already present), then bump
    // user_version to 6 and reopen via AppDatabase.forTesting so onUpgrade
    // runs the v7 branch and adds app_seed_color_argb.
    final db = sqlite3.openInMemory();

    // Create a complete v6 app_settings row so _ensureGlobalSettingsRow()
    // does not need to insert anything (we want to verify the ALTER TABLE
    // path, not the insert path).
    db.execute('''
      CREATE TABLE app_settings (
        id TEXT NOT NULL,
        theme_mode TEXT NOT NULL DEFAULT 'system',
        locale_code TEXT,
        default_watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
        default_watermark_opacity REAL NOT NULL DEFAULT 0.78,
        default_watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
        default_watermark_font_scale REAL NOT NULL DEFAULT 1.0,
        location_permission_prompt_dismissed INTEGER NOT NULL DEFAULT 0,
        use_dynamic_color INTEGER NOT NULL DEFAULT 0,
        completion_notifications_enabled INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (id)
      );
    ''');
    db.execute(
      "INSERT INTO app_settings (id, theme_mode, updated_at) VALUES ('global', 'dark', 0);",
    );
    // Minimal projects + captures tables so onCreate doesn't fail.
    db.execute('''
      CREATE TABLE projects (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
        watermark_opacity REAL NOT NULL DEFAULT 0.78,
        watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
        watermark_font_scale REAL NOT NULL DEFAULT 1.0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (id)
      );
    ''');
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
        processing_attempts INTEGER NOT NULL DEFAULT 0,
        watermark_locale_code TEXT NOT NULL DEFAULT 'zh',
        location_resolution TEXT NOT NULL DEFAULT 'resolved',
        original_deleted_at INTEGER,
        PRIMARY KEY (id)
      );
    ''');
    db.execute('PRAGMA user_version = 6;');

    final database = AppDatabase.forTesting(
      NativeDatabase.opened(db, closeUnderlyingOnClose: true),
    );
    addTearDown(database.close);

    final settings = await database.getAppSettings();
    expect(settings.id, 'global');
    expect(settings.appSeedColorArgb, 0xff37c58b);

    final updated = await database.updateAppSettings(
      appSeedColorArgb: 0xff1565c0,
    );
    expect(updated.appSeedColorArgb, 0xff1565c0);
  });

  test(
    'v7 to v8 migration adds nullable restore ownership without claiming existing projects',
    () async {
      final db = sqlite3.openInMemory();
      db.execute('''
        CREATE TABLE projects (
          id TEXT NOT NULL,
          name TEXT NOT NULL,
          description TEXT,
          watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
          watermark_opacity REAL NOT NULL DEFAULT 0.78,
          watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
          watermark_font_scale REAL NOT NULL DEFAULT 1.0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (id)
        );
      ''');
      db.execute('''
        CREATE TABLE app_settings (
          id TEXT NOT NULL,
          theme_mode TEXT NOT NULL DEFAULT 'system',
          locale_code TEXT,
          default_watermark_position TEXT NOT NULL DEFAULT 'bottomLeft',
          default_watermark_opacity REAL NOT NULL DEFAULT 0.78,
          default_watermark_accent_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
          default_watermark_font_scale REAL NOT NULL DEFAULT 1.0,
          location_permission_prompt_dismissed INTEGER NOT NULL DEFAULT 0,
          use_dynamic_color INTEGER NOT NULL DEFAULT 0,
          completion_notifications_enabled INTEGER NOT NULL DEFAULT 0,
          app_seed_color_argb INTEGER NOT NULL DEFAULT 0xff37c58b,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (id)
        );
      ''');
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
          processing_attempts INTEGER NOT NULL DEFAULT 0,
          watermark_locale_code TEXT NOT NULL DEFAULT 'zh',
          location_resolution TEXT NOT NULL DEFAULT 'resolved',
          original_deleted_at INTEGER,
          PRIMARY KEY (id)
        );
      ''');
      db.execute(
        "INSERT INTO projects (id, name, created_at, updated_at) "
        "VALUES ('existing', '既有项目', 0, 0);",
      );
      db.execute(
        "INSERT INTO app_settings (id, updated_at) VALUES ('global', 0);",
      );
      db.execute('PRAGMA user_version = 7;');

      final database = AppDatabase.forTesting(
        NativeDatabase.opened(db, closeUnderlyingOnClose: true),
      );
      addTearDown(database.close);

      final existing = await database.projectById('existing');
      expect(existing?.restoreOperationId, isNull);

      final restored = await database.createProject(
        id: 'restored',
        name: '恢复项目',
        restoreOperationId: 'operation-1',
      );
      expect(restored.restoreOperationId, 'operation-1');
      expect(
        await database.projectHasRestoreOwnership(
          projectId: 'restored',
          operationId: 'operation-1',
        ),
        isTrue,
      );
      await database.clearProjectRestoreOwnership(
        projectId: 'restored',
        operationId: 'other-operation',
      );
      expect(
        (await database.projectById('restored'))?.restoreOperationId,
        'operation-1',
      );
      await database.clearProjectRestoreOwnership(
        projectId: 'restored',
        operationId: 'operation-1',
      );
      expect(
        (await database.projectById('restored'))?.restoreOperationId,
        isNull,
      );
    },
  );
}
