part of 'app_database.dart';

/// Inserts the default `global` settings row if it does not already exist.
///
/// Uses `INSERT OR IGNORE` semantics so existing settings (including those
/// carried across a v2 -> v3 upgrade) are never overwritten.
Future<void> _ensureGlobalSettingsRow(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.appSettings).insert(
    AppSettingsCompanion.insert(
      id: const Value('global'),
      themeMode: const Value('system'),
      defaultWatermarkPosition: const Value('bottomLeft'),
      defaultWatermarkOpacity: const Value(0.78),
      defaultWatermarkAccentColorArgb: const Value(0xff37c58b),
      defaultWatermarkFontScale: const Value(1.0),
      locationPermissionPromptDismissed: const Value(false),
      useDynamicColor: const Value(false),
      completionNotificationsEnabled: const Value(false),
      appSeedColorArgb: const Value(kDefaultSeedColorArgb),
      updatedAt: now,
    ),
    mode: InsertMode.insertOrIgnore,
  );
}

/// Creates the SQLite indexes that back the capture-list queries.
///
/// All statements use `CREATE INDEX IF NOT EXISTS` so this is safe to call
/// both from `onCreate` (fresh install) and the v6 migration step (upgrade
/// from any prior version), and idempotent for users who already have the
/// indexes from the perf branch.
Future<void> _createCaptureIndexes(AppDatabase db) async {
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS capture_records_status_idx ON captures (status)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS capture_records_sort_idx '
    'ON captures (COALESCE(captured_at, created_at) DESC)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS capture_records_project_sort_idx '
    'ON captures (project_id, COALESCE(captured_at, created_at) DESC)',
  );
}

Future<void> _createCaptureCursorIndexes(AppDatabase db) async {
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS capture_records_sort_cursor_idx '
    'ON captures (COALESCE(captured_at, created_at) DESC, id DESC)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS capture_records_project_sort_cursor_idx '
    'ON captures (project_id, COALESCE(captured_at, created_at) DESC, id DESC)',
  );
}

Future<void> _createCaptureTemplateIndexes(AppDatabase db) async {
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS capture_templates_project_updated_name_idx '
    'ON capture_templates (project_id, updated_at DESC, name)',
  );
}

/// Adds the `use_dynamic_color` and `completion_notifications_enabled`
/// columns to `app_settings` if they are missing.
///
/// This is called from the v6 migration step to converge users who arrive
/// from the perf/smoothness branch's v5 schema (which has the capture
/// indexes but not these two columns). Uses `PRAGMA table_info` so the
/// operation is idempotent and never raises "duplicate column name". The
/// `ALTER TABLE` statements mirror what `migrator.addColumn` would emit,
/// but `migrator` is only in scope inside the `MigrationStrategy` callback,
/// so we issue the DDL directly.
Future<void> _ensureDynamicColorColumns(AppDatabase db) async {
  final columns = await db.customSelect(
    'PRAGMA table_info(app_settings)',
  ).get();
  final columnNames = columns.map((row) => row.read<String>('name')).toSet();
  if (!columnNames.contains('use_dynamic_color')) {
    await db.customStatement(
      'ALTER TABLE app_settings ADD COLUMN use_dynamic_color '
      'INTEGER NOT NULL DEFAULT 0',
    );
  }
  if (!columnNames.contains('completion_notifications_enabled')) {
    await db.customStatement(
      'ALTER TABLE app_settings ADD COLUMN '
      'completion_notifications_enabled INTEGER NOT NULL DEFAULT 0',
    );
  }
}

/// Adds the `app_seed_color_argb` column to `app_settings` if missing.
///
/// Called from the v7 migration step. Uses `PRAGMA table_info` so the
/// operation is idempotent and never raises "duplicate column name".
Future<void> _ensureAppSeedColorColumn(AppDatabase db) async {
  final columns = await db.customSelect(
    'PRAGMA table_info(app_settings)',
  ).get();
  final columnNames = columns.map((row) => row.read<String>('name')).toSet();
  if (!columnNames.contains('app_seed_color_argb')) {
    await db.customStatement(
      'ALTER TABLE app_settings ADD COLUMN app_seed_color_argb '
      'INTEGER NOT NULL DEFAULT $kDefaultSeedColorArgb',
    );
  }
}