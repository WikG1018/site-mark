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
}
