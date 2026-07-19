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
/// [AppDatabase.forTesting] will read `user_version = 2`, see the target
/// `schemaVersion` of `3`, and run the real `onUpgrade(migrator, 2, 3)` path.
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
/// [AppDatabase.forTesting] will read `user_version = 3`, see the target
/// `schemaVersion` of `4`, and run the real `onUpgrade(migrator, 3, 4)` path.
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

/// Opens a raw in-memory sqlite database with the genuine v4 schema, seeds
/// project, capture, and settings values, then sets `PRAGMA user_version = 4`.
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
  db.execute(
    '''
    INSERT INTO projects VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?)
  ''',
    [
      'project-1',
      '东区厂房改造',
      'bottomRight',
      0.64,
      0xff1565c0,
      1.25,
      projectCreated,
      projectCreated,
    ],
  );
  db.execute(
    '''
    INSERT INTO app_settings VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ''',
    [
      'global',
      'dark',
      'en',
      'bottomRight',
      0.64,
      0xff1565c0,
      1.25,
      1,
      projectCreated,
    ],
  );
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

void main() {
  test('v2 to v3 migration preserves captures and inserts defaults', () async {
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
  });

  test(
    'v3 to v4 migration preserves rows and adds field-test defaults',
    () async {
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
    },
  );

  test(
    'v4 to v5 migration preserves rows and creates capture indexes',
    () async {
      final database = AppDatabase.forTesting(openMigratedV4Fixture());
      addTearDown(database.close);

      final project = await database.projectById('project-1');
      final capture = await database.captureById('capture-1');
      final settings = await database.getAppSettings();
      final indexes = await captureIndexes(database);

      expect(project?.name, '东区厂房改造');
      expect(project?.watermarkFontScale, 1.25);
      expect(capture?.photoNumber, 'SM-20260716-001');
      expect(capture?.originalDeletedAt, DateTime(2026, 7, 16, 9, 32));
      expect(settings.themeMode, 'dark');
      expect(settings.defaultWatermarkFontScale, 1.25);
      expect(settings.locationPermissionPromptDismissed, isTrue);
      expect(indexes.keys, {
        'capture_records_project_sort_idx',
        'capture_records_sort_idx',
        'capture_records_status_idx',
      });
      expect(indexes['capture_records_status_idx'], contains('(status)'));
      expect(
        indexes['capture_records_sort_idx'],
        contains('COALESCE(captured_at, created_at) DESC'),
      );
      expect(
        indexes['capture_records_project_sort_idx'],
        contains('project_id, COALESCE(captured_at, created_at) DESC'),
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
    },
  );

  test('fresh database creates all capture indexes', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final indexes = await captureIndexes(database);

    expect(indexes.keys, {
      'capture_records_project_sort_idx',
      'capture_records_sort_idx',
      'capture_records_status_idx',
    });
  });
}
