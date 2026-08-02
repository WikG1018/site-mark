import 'package:drift/drift.dart' show QueryExecutor, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/capture_template_rules.dart';
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

  final tableSql = await database
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE name = 'capture_templates'",
      )
      .getSingle();
  final normalizedTableSql = normalizedSql(tableSql.read<String>('sql'));
  expect(normalizedTableSql, contains('check (length(name) between 1 and 80)'));
  expect(
    normalizedTableSql,
    contains('check (length(name_key) between 1 and 80)'),
  );
  expect(
    normalizedTableSql,
    contains('check (length(work_location) between 1 and 160)'),
  );
  expect(
    normalizedTableSql,
    contains('check (length(work_content) between 1 and 240)'),
  );
  expect(
    normalizedTableSql,
    contains('check (length(photographer) between 1 and 80)'),
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

  group('capture template database interface', () {
    late AppDatabase database;
    late AppDatabase templateDatabase;

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      templateDatabase = database;
      await database.createProject(id: 'project-1', name: '东区厂房改造');
      await database.createProject(id: 'project-2', name: '西区厂房改造');
    });

    tearDown(() => database.close());

    test(
      'reads templates newest-first and scopes names to their project',
      () async {
        final earlier = DateTime(2026, 8, 1, 9);
        final later = earlier.add(const Duration(minutes: 1));
        await _insertTemplate(
          templateDatabase,
          id: 'template-1',
          projectId: 'project-1',
          name: '日常巡检',
          nameKey: '日常巡检',
          updatedAt: earlier,
        );
        await _insertTemplate(
          templateDatabase,
          id: 'template-2',
          projectId: 'project-1',
          name: '专项检查',
          nameKey: '专项检查',
          updatedAt: later,
        );
        await _insertTemplate(
          templateDatabase,
          id: 'template-3',
          projectId: 'project-2',
          name: '日常巡检',
          nameKey: '日常巡检',
          updatedAt: later,
        );

        final templates = await templateDatabase.captureTemplatesForProject(
          'project-1',
        );

        expect(templates.map((template) => template.id), [
          'template-2',
          'template-1',
        ]);
        expect(
          (await templateDatabase.watchCaptureTemplates('project-1').first).map(
            (template) => template.id,
          ),
          ['template-2', 'template-1'],
        );
        expect(await templateDatabase.countCaptureTemplates('project-1'), 2);
      },
    );

    test(
      'rename and delete require both template and project ownership',
      () async {
        final row = await _insertTemplate(
          templateDatabase,
          id: 'template-1',
          projectId: 'project-1',
          name: '日常巡检',
          nameKey: '日常巡检',
        );

        final renamed = await templateDatabase.renameCaptureTemplate(
          id: row.id,
          projectId: 'project-1',
          name: '专项检查',
          nameKey: '专项检查',
          updatedAt: DateTime(2026, 8, 1, 10),
        );
        expect(renamed.name, '专项检查');
        expect(
          await templateDatabase.deleteCaptureTemplate(
            id: row.id,
            projectId: 'project-2',
          ),
          0,
        );
        expect(
          await templateDatabase.deleteCaptureTemplate(
            id: row.id,
            projectId: 'project-1',
          ),
          1,
        );
      },
    );

    test(
      'restored template batches only insert for their owning operation',
      () async {
        await database.createProject(
          id: 'restoring-project',
          name: '恢复中的项目',
          restoreOperationId: 'operation-1',
        );
        final rows = [
          _templateCompanion(
            id: 'restored-template',
            projectId: 'restoring-project',
            name: '恢复模板',
            nameKey: '恢复模板',
          ),
        ];

        await templateDatabase.insertRestoredCaptureTemplates(
          projectId: 'restoring-project',
          restoreOperationId: 'other-operation',
          templates: rows,
        );
        expect(
          await templateDatabase.countCaptureTemplates('restoring-project'),
          0,
        );

        await templateDatabase.insertRestoredCaptureTemplates(
          projectId: 'restoring-project',
          restoreOperationId: 'operation-1',
          templates: rows,
        );
        expect(
          await templateDatabase.countCaptureTemplates('restoring-project'),
          1,
        );
      },
    );

    test(
      'restored template batch rolls back every row on a later conflict',
      () async {
        await database.createProject(
          id: 'restoring-project',
          name: '恢复中的项目',
          restoreOperationId: 'operation-1',
        );
        final first = _templateCompanion(
          id: 'restored-first',
          projectId: 'restoring-project',
          name: '模板一',
          nameKey: 'same-key',
        );
        final conflictingSecond = _templateCompanion(
          id: 'restored-second',
          projectId: 'restoring-project',
          name: '模板二',
          nameKey: 'same-key',
        );

        await expectLater(
          templateDatabase.insertRestoredCaptureTemplates(
            projectId: 'restoring-project',
            restoreOperationId: 'operation-1',
            templates: [first, conflictingSecond],
          ),
          throwsA(isA<Exception>()),
        );

        expect(
          await templateDatabase.countCaptureTemplates('restoring-project'),
          0,
        );
      },
    );

    test('SQLite scalar checks protect direct template writes', () async {
      final emojiName = '\u{1F600}' * captureTemplateNameMaxLength;
      await _insertTemplateBySql(
        database,
        id: 'emoji-template',
        projectId: 'project-1',
        name: emojiName,
        nameKey: emojiName,
      );
      expect(await templateDatabase.countCaptureTemplates('project-1'), 1);

      await expectLater(
        _insertTemplateBySql(
          database,
          id: 'long-name',
          projectId: 'project-1',
          name: 'n' * (captureTemplateNameMaxLength + 1),
          nameKey: 'long-name',
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        _insertTemplateBySql(
          database,
          id: 'long-location',
          projectId: 'project-1',
          name: 'location limit',
          nameKey: 'location limit',
          workLocation: 'l' * (captureTemplateLocationMaxLength + 1),
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        _insertTemplateBySql(
          database,
          id: 'long-content',
          projectId: 'project-1',
          name: 'content limit',
          nameKey: 'content limit',
          workContent: 'c' * (captureTemplateContentMaxLength + 1),
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        _insertTemplateBySql(
          database,
          id: 'long-photographer',
          projectId: 'project-1',
          name: 'photographer limit',
          nameKey: 'photographer limit',
          photographer: 'p' * (captureTemplatePhotographerMaxLength + 1),
        ),
        throwsA(isA<Exception>()),
      );

      final ddl = await database
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'capture_templates'",
          )
          .getSingle();
      final normalized = normalizedSql(ddl.read<String>('sql'));
      expect(normalized, contains('check (length(name) between 1 and 80)'));
      expect(normalized, contains('check (length(name_key) between 1 and 80)'));
      expect(
        normalized,
        contains('check (length(work_location) between 1 and 160)'),
      );
      expect(
        normalized,
        contains('check (length(work_content) between 1 and 240)'),
      );
      expect(
        normalized,
        contains('check (length(photographer) between 1 and 80)'),
      );
    });

    test(
      'restore batch rolls back when a later row exceeds scalar length',
      () async {
        await database.createProject(
          id: 'restoring-length-project',
          name: '恢复长度项目',
          restoreOperationId: 'operation-1',
        );
        await expectLater(
          templateDatabase.insertRestoredCaptureTemplates(
            projectId: 'restoring-length-project',
            restoreOperationId: 'operation-1',
            templates: [
              _templateCompanion(
                id: 'valid-restored-row',
                projectId: 'restoring-length-project',
                name: '有效模板',
                nameKey: '有效模板',
              ),
              _templateCompanion(
                id: 'overlong-restored-row',
                projectId: 'restoring-length-project',
                name: 'n' * (captureTemplateNameMaxLength + 1),
                nameKey: 'too-long-restored-name',
              ),
            ],
          ),
          throwsA(isA<Exception>()),
        );
        expect(
          await templateDatabase.countCaptureTemplates(
            'restoring-length-project',
          ),
          0,
        );
      },
    );

    test(
      'recent suggestions use the latest visible text for each value',
      () async {
        final base = DateTime(2026, 8, 1, 9);
        await _insertCapture(
          database,
          id: 'capture-older',
          projectId: 'project-1',
          workLocation: '  East Zone  ',
          workContent: '旧内容',
          photographer: '张工',
          status: CaptureStatus.ready,
          createdAt: base,
        );
        await _insertCapture(
          database,
          id: 'capture-newer',
          projectId: 'project-1',
          workLocation: 'east zone',
          workContent: '新内容',
          photographer: '李工',
          status: CaptureStatus.failed,
          createdAt: base,
          capturedAt: base.add(const Duration(hours: 1)),
        );
        await _insertCapture(
          database,
          id: 'capture-pending',
          projectId: 'project-1',
          workLocation: '不应出现',
          workContent: '不应出现',
          photographer: '不应出现',
          status: CaptureStatus.pendingCamera,
          createdAt: base.add(const Duration(hours: 2)),
        );
        await _insertCapture(
          database,
          id: 'other-project',
          projectId: 'project-2',
          workLocation: '其他项目',
          workContent: '其他项目',
          photographer: '其他项目',
          status: CaptureStatus.ready,
          createdAt: base.add(const Duration(hours: 3)),
        );

        final suggestions = await templateDatabase.recentCaptureSuggestions(
          projectId: 'project-1',
          field: CaptureSuggestionField.workLocation,
        );

        expect(suggestions, ['east zone']);
      },
    );

    test('recent suggestions validate their limit', () async {
      await expectLater(
        templateDatabase.recentCaptureSuggestions(
          projectId: 'project-1',
          field: CaptureSuggestionField.workLocation,
          limit: 0,
        ),
        throwsArgumentError,
      );
      await expectLater(
        templateDatabase.recentCaptureSuggestions(
          projectId: 'project-1',
          field: CaptureSuggestionField.workLocation,
          limit: 21,
        ),
        throwsArgumentError,
      );
    });

    test(
      'project rename retains its templates and project deletion cascades',
      () async {
        await _insertTemplate(
          templateDatabase,
          id: 'template-1',
          projectId: 'project-1',
          name: '日常巡检',
          nameKey: '日常巡检',
        );

        await database.renameProject(projectId: 'project-1', name: '新项目名称');
        expect(
          (await templateDatabase.captureTemplatesForProject(
            'project-1',
          )).single.name,
          '日常巡检',
        );

        await database.customStatement(
          "DELETE FROM projects WHERE id = 'project-1'",
        );
        expect(await templateDatabase.countCaptureTemplates('project-1'), 0);
      },
    );

    test(
      'recent suggestions cap, trim, tie-break, and map every field',
      () async {
        final timestamp = DateTime(2026, 8, 1, 9);
        for (var index = 0; index < 21; index++) {
          await _insertCapture(
            database,
            id: 'limit-$index',
            projectId: 'project-1',
            workLocation: 'Location $index',
            workContent: 'Content $index',
            photographer: 'Person $index',
            status: CaptureStatus.ready,
            createdAt: timestamp.add(Duration(minutes: index)),
          );
        }
        await _insertCapture(
          database,
          id: 'tie-a',
          projectId: 'project-1',
          workLocation: ' alpha ',
          workContent: '内容 A',
          photographer: '工程师',
          status: CaptureStatus.ready,
          createdAt: timestamp.add(const Duration(hours: 1)),
        );
        await _insertCapture(
          database,
          id: 'tie-z',
          projectId: 'project-1',
          workLocation: 'Alpha',
          workContent: '内容 B',
          photographer: '工程師',
          status: CaptureStatus.ready,
          createdAt: timestamp.add(const Duration(hours: 1)),
        );
        await _insertCapture(
          database,
          id: 'blank-value',
          projectId: 'project-1',
          workLocation: '   ',
          workContent: '   ',
          photographer: '   ',
          status: CaptureStatus.ready,
          createdAt: timestamp.add(const Duration(hours: 2)),
        );
        await _insertCapture(
          database,
          id: 'deleted',
          projectId: 'project-1',
          workLocation: '已删除',
          workContent: '已删除',
          photographer: '已删除',
          status: CaptureStatus.ready,
          createdAt: timestamp.add(const Duration(hours: 3)),
        );
        await database.customStatement(
          "DELETE FROM captures WHERE id = 'deleted'",
        );

        final locations = await templateDatabase.recentCaptureSuggestions(
          projectId: 'project-1',
          field: CaptureSuggestionField.workLocation,
        );
        final content = await templateDatabase.recentCaptureSuggestions(
          projectId: 'project-1',
          field: CaptureSuggestionField.workContent,
          limit: 2,
        );
        final photographers = await templateDatabase.recentCaptureSuggestions(
          projectId: 'project-1',
          field: CaptureSuggestionField.photographer,
          limit: 2,
        );

        expect(locations, hasLength(20));
        expect(locations, contains('Alpha'));
        expect(locations, isNot(contains('alpha')));
        expect(locations, isNot(contains('已删除')));
        expect(locations, everyElement(isNotEmpty));
        expect(content, ['内容 B', '内容 A']);
        expect(photographers, ['工程師', '工程师']);
      },
    );

    test(
      'recent suggestions may return fewer than 20 after 200-row collapse',
      () async {
        final timestamp = DateTime(2026, 8, 1, 9);
        for (var index = 0; index < 200; index++) {
          await _insertCapture(
            database,
            id: 'collapse-$index',
            projectId: 'project-1',
            workLocation: index.isEven ? '  Same Value  ' : 'same value',
            workContent: '内容$index',
            photographer: '张工',
            status: CaptureStatus.ready,
            createdAt: timestamp.add(Duration(minutes: index)),
          );
        }

        final suggestions = await templateDatabase.recentCaptureSuggestions(
          projectId: 'project-1',
          field: CaptureSuggestionField.workLocation,
        );

        expect(suggestions, ['same value']);
        expect(suggestions.length, lessThan(20));
      },
    );
  });
}

CaptureTemplatesCompanion _templateCompanion({
  required String id,
  required String projectId,
  required String name,
  required String nameKey,
  DateTime? updatedAt,
}) {
  final timestamp = updatedAt ?? DateTime(2026, 8, 1, 9);
  return CaptureTemplatesCompanion.insert(
    id: id,
    projectId: projectId,
    name: name,
    nameKey: nameKey,
    workLocation: 'A 区',
    workContent: '检查',
    photographer: '张工',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Future<CaptureTemplate> _insertTemplate(
  AppDatabase database, {
  required String id,
  required String projectId,
  required String name,
  required String nameKey,
  DateTime? updatedAt,
}) {
  return database.insertCaptureTemplate(
    _templateCompanion(
      id: id,
      projectId: projectId,
      name: name,
      nameKey: nameKey,
      updatedAt: updatedAt,
    ),
  );
}

Future<void> _insertCapture(
  AppDatabase database, {
  required String id,
  required String projectId,
  required String workLocation,
  required String workContent,
  required String photographer,
  required CaptureStatus status,
  required DateTime createdAt,
  DateTime? capturedAt,
}) {
  return database
      .into(database.captureRecords)
      .insert(
        CaptureRecordsCompanion.insert(
          id: id,
          projectId: projectId,
          workLocation: workLocation,
          workContent: workContent,
          photographer: photographer,
          originalPath: '/private/$id.jpg',
          status: status,
          createdAt: createdAt,
          capturedAt: Value(capturedAt),
        ),
      );
}

Future<void> _insertTemplateBySql(
  AppDatabase database, {
  required String id,
  required String projectId,
  required String name,
  required String nameKey,
  String workLocation = 'A 区',
  String workContent = '检查',
  String photographer = '张工',
}) {
  return database.customStatement('''
    INSERT INTO capture_templates (
      id, project_id, name, name_key, work_location, work_content,
      photographer, created_at, updated_at
    ) VALUES (
      '$id', '$projectId', '$name', '$nameKey', '$workLocation',
      '$workContent', '$photographer', 1, 1
    )
  ''');
}
