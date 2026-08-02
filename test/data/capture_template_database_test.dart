import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

QueryExecutor openV9AndUpgrade() {
  final db = sqlite3.openInMemory();
  db.execute('''
    CREATE TABLE projects (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      restore_operation_id TEXT,
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
      id TEXT NOT NULL PRIMARY KEY,
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
  db.execute('''
    INSERT INTO projects (id, name, created_at, updated_at)
    VALUES ('project-1', '东区厂房改造', 1, 1);
  ''');
  db.execute('''
    INSERT INTO captures (
      id, project_id, work_location, work_content, photographer,
      original_path, status, created_at
    ) VALUES (
      'capture-1', 'project-1', 'A 区三层', '风管安装检查', '张工',
      '/private/capture-1.jpg', 'ready', 1
    );
  ''');
  db.execute('''
    INSERT INTO app_settings (id, updated_at) VALUES ('global', 1);
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
  db.execute(
    'CREATE INDEX capture_records_sort_cursor_idx '
    'ON captures (COALESCE(captured_at, created_at) DESC, id DESC)',
  );
  db.execute(
    'CREATE INDEX capture_records_project_sort_cursor_idx '
    'ON captures (project_id, COALESCE(captured_at, created_at) DESC, id DESC)',
  );
  db.execute('PRAGMA user_version = 9;');
  return NativeDatabase.opened(db, closeUnderlyingOnClose: true);
}

Future<Set<String>> tableColumns(AppDatabase database, String table) async {
  final rows = await database.customSelect('PRAGMA table_info($table)').get();
  return {for (final row in rows) row.read<String>('name')};
}

String normalizedSql(String sql) =>
    sql.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

Future<void> expectCaptureTemplateSchema(AppDatabase database) async {
  expect(await tableColumns(database, 'capture_templates'), {
    'id',
    'project_id',
    'name',
    'name_key',
    'work_location',
    'work_content',
    'photographer',
    'created_at',
    'updated_at',
  });

  final foreignKeys = await database
      .customSelect('PRAGMA foreign_key_list(capture_templates)')
      .get();
  expect(foreignKeys, hasLength(1));
  expect(foreignKeys.single.read<String>('from'), 'project_id');
  expect(foreignKeys.single.read<String>('table'), 'projects');
  expect(foreignKeys.single.read<String>('to'), 'id');
  expect(foreignKeys.single.read<String>('on_delete'), 'CASCADE');

  final indexes = await database.customSelect('''
        SELECT name, sql FROM sqlite_master
        WHERE type = 'index' AND tbl_name = 'capture_templates'
        ORDER BY name
      ''').get();
  final indexSql = {
    for (final row in indexes)
      row.read<String>('name'): row.readNullable<String>('sql'),
  };
  expect(indexSql.keys, contains('capture_templates_project_updated_name_idx'));
  expect(
    normalizedSql(indexSql['capture_templates_project_updated_name_idx']!),
    'create index capture_templates_project_updated_name_idx '
    'on capture_templates (project_id, updated_at desc, name)',
  );
}

void main() {
  test('v9 to v10 preserves existing projects and captures', () async {
    final database = AppDatabase.forTesting(openV9AndUpgrade());
    addTearDown(database.close);

    final project = await database
        .customSelect("SELECT name FROM projects WHERE id = 'project-1'")
        .getSingle();
    final capture = await database
        .customSelect(
          "SELECT work_content FROM captures WHERE id = 'capture-1'",
        )
        .getSingle();
    expect(project.read<String>('name'), '东区厂房改造');
    expect(capture.read<String>('work_content'), '风管安装检查');
    await expectCaptureTemplateSchema(database);
  });

  test(
    'fresh database creates capture templates with cascade and uniqueness',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await database.customStatement('''
      INSERT INTO projects (id, name, created_at, updated_at)
      VALUES ('project-1', '东区厂房改造', 1, 1)
    ''');
      await database.customStatement('''
      INSERT INTO capture_templates (
        id, project_id, name, name_key, work_location, work_content,
        photographer, created_at, updated_at
      ) VALUES (
        'template-1', 'project-1', '日常巡检', '日常巡检', 'A 区', '检查',
        '张工', 1, 1
      )
    ''');
      await expectLater(
        database.customStatement('''
        INSERT INTO capture_templates (
          id, project_id, name, name_key, work_location, work_content,
          photographer, created_at, updated_at
        ) VALUES (
          'template-2', 'project-1', '重复名称', '日常巡检', 'B 区', '复查',
          '李工', 2, 2
        )
      '''),
        throwsA(isA<Exception>()),
      );
      await database.customStatement(
        "DELETE FROM projects WHERE id = 'project-1'",
      );
      final templates = await database
          .customSelect('SELECT id FROM capture_templates')
          .get();
      expect(templates, isEmpty);
      await expectCaptureTemplateSchema(database);
    },
  );
}
