import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/capture_status.dart';

void main() {
  late AppDatabase database;
  late CaptureQueryRepository repository;

  setUpAll(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = CaptureQueryRepository(database);

    for (final project in const [
      ('bulk', 'Bulk Site'),
      ('special', 'Special Site'),
      ('dates', 'Date Site'),
      ('other-dates', 'Other Date Site'),
      ('selection', 'Selection Site'),
      ('adjacent', 'Adjacent Site'),
    ]) {
      await database.createProject(id: project.$1, name: project.$2);
    }

    final base = DateTime(2026, 1, 1);
    await database.batch((batch) {
      for (var index = 0; index < 10000; index++) {
        final matches = index < 120;
        batch.insert(
          database.captureRecords,
          CaptureRecordsCompanion.insert(
            id: 'bulk-${index.toString().padLeft(5, '0')}',
            projectId: 'bulk',
            workLocation: matches ? '21栋 ${index + 1}层' : '普通施工区',
            workContent: '安装检查',
            photographer: 'Builder',
            notes: Value(matches ? '完成 100% 验收' : '普通记录'),
            originalPath: '/private/bulk-$index.jpg',
            status: CaptureStatus.ready,
            createdAt: base.add(Duration(seconds: index)),
            capturedAt: Value(base.add(Duration(seconds: index))),
          ),
        );
      }
    });

    Future<void> insert({
      required String id,
      String projectId = 'special',
      String workLocation = '施工区',
      String workContent = '安装检查',
      String photographer = 'Builder',
      String? notes,
      String? photoNumber,
      String? address,
      required CaptureStatus status,
      required DateTime time,
    }) async {
      await database
          .into(database.captureRecords)
          .insert(
            CaptureRecordsCompanion.insert(
              id: id,
              projectId: projectId,
              photoNumber: Value(photoNumber),
              workLocation: workLocation,
              workContent: workContent,
              photographer: photographer,
              notes: Value(notes),
              originalPath: '/private/$id.jpg',
              status: status,
              createdAt: time,
              capturedAt: Value(time),
              address: Value(address),
            ),
          );
    }

    final specialTime = DateTime(2026, 6, 1, 12);
    await insert(
      id: 'literal-percent',
      notes: 'literal 100% marker',
      status: CaptureStatus.ready,
      time: specialTime,
    );
    await insert(
      id: 'percent-wildcard-decoy',
      notes: 'literal 100X marker',
      status: CaptureStatus.ready,
      time: specialTime.subtract(const Duration(seconds: 1)),
    );
    await insert(
      id: 'literal-underscore',
      workContent: 'literal A_B marker',
      status: CaptureStatus.ready,
      time: specialTime.subtract(const Duration(seconds: 2)),
    );
    await insert(
      id: 'underscore-wildcard-decoy',
      workContent: 'literal AXB marker',
      status: CaptureStatus.ready,
      time: specialTime.subtract(const Duration(seconds: 3)),
    );
    await insert(
      id: 'literal-backslash',
      address: r'pipe\zone literal',
      status: CaptureStatus.ready,
      time: specialTime.subtract(const Duration(seconds: 4)),
    );
    await insert(
      id: 'backslash-decoy',
      address: 'pipeXzone literal',
      status: CaptureStatus.ready,
      time: specialTime.subtract(const Duration(seconds: 5)),
    );
    await insert(
      id: 'ascii-case',
      photographer: 'ALICE Builder',
      status: CaptureStatus.ready,
      time: specialTime.subtract(const Duration(seconds: 6)),
    );
    await insert(
      id: 'or-location',
      workLocation: 'shared-or-token',
      status: CaptureStatus.ready,
      time: specialTime.subtract(const Duration(seconds: 7)),
    );
    await insert(
      id: 'or-photo-number',
      photoNumber: 'shared-or-token',
      status: CaptureStatus.ready,
      time: specialTime.subtract(const Duration(seconds: 8)),
    );
    await insert(
      id: 'and-cross-fields',
      workLocation: 'first-and-token',
      notes: 'second-and-token',
      status: CaptureStatus.ready,
      time: specialTime.subtract(const Duration(seconds: 9)),
    );
    await insert(
      id: 'and-decoy',
      workLocation: 'first-and-token',
      status: CaptureStatus.ready,
      time: specialTime.subtract(const Duration(seconds: 10)),
    );

    for (final id in const ['tie-a', 'tie-c', 'tie-b']) {
      await insert(
        id: id,
        notes: 'tie-order-token',
        status: CaptureStatus.ready,
        time: DateTime(2026, 6, 2, 12),
      );
    }

    await insert(
      id: 'date-2025-12-31',
      projectId: 'dates',
      notes: 'date-token',
      status: CaptureStatus.ready,
      time: DateTime(2025, 12, 31, 23),
    );
    await insert(
      id: 'date-2026-07-15',
      projectId: 'dates',
      notes: 'date-token',
      status: CaptureStatus.ready,
      time: DateTime(2026, 7, 15, 9),
    );
    await insert(
      id: 'date-2026-07-16',
      projectId: 'dates',
      notes: 'date-token',
      status: CaptureStatus.failed,
      time: DateTime(2026, 7, 16, 9),
    );
    await insert(
      id: 'date-2026-08-01',
      projectId: 'dates',
      notes: 'date-token',
      status: CaptureStatus.ready,
      time: DateTime(2026, 8, 1, 9),
    );
    await insert(
      id: 'date-other-project',
      projectId: 'other-dates',
      notes: 'date-token',
      status: CaptureStatus.ready,
      time: DateTime(2024, 1, 1, 9),
    );

    await insert(
      id: 'selection-ready',
      projectId: 'selection',
      notes: 'selection-token only-ready-token',
      status: CaptureStatus.ready,
      time: DateTime(2026, 7, 1, 10),
    );
    await insert(
      id: 'selection-failed',
      projectId: 'selection',
      notes: 'selection-token',
      status: CaptureStatus.failed,
      time: DateTime(2026, 7, 1, 9),
    );
    await insert(
      id: 'selection-rendering',
      projectId: 'selection',
      notes: 'selection-token',
      status: CaptureStatus.rendering,
      time: DateTime(2026, 7, 1, 8),
    );
    await insert(
      id: 'selection-pending',
      projectId: 'selection',
      notes: 'selection-token',
      status: CaptureStatus.pendingCamera,
      time: DateTime(2026, 7, 1, 7),
    );

    for (var index = 1; index <= 5; index++) {
      await insert(
        id: 'adj-$index',
        projectId: 'adjacent',
        notes: 'adjacent-token',
        status: CaptureStatus.ready,
        time: DateTime(2026, 7, 2, 12, index),
      );
    }
  });

  tearDownAll(() async {
    await database.close();
  });

  test('paginates 10k rows with AND terms and no duplicate IDs', () async {
    const query = CaptureListQuery(searchText: r'21栋 100%');

    final first = await repository.loadPage(query);
    expect(first.rows, hasLength(50));
    expect(first.hasMore, isTrue);
    expect(first.nextCursor, isNotNull);
    expect(
      first.rows.every(
        (row) =>
            row.capture.workLocation.contains('21栋') &&
            row.capture.notes!.contains('100%'),
      ),
      isTrue,
    );

    final second = await repository.loadPage(query, after: first.nextCursor);
    expect(second.rows, hasLength(50));
    expect(
      second.rows
          .map((row) => row.capture.id)
          .toSet()
          .intersection(first.rows.map((row) => row.capture.id).toSet()),
      isEmpty,
    );
  });

  test('treats percent underscore and backslash as LIKE literals', () async {
    final percent = await repository.loadPage(
      const CaptureListQuery(searchText: 'literal 100%'),
    );
    expect(percent.rows.map((row) => row.capture.id), ['literal-percent']);

    final underscore = await repository.loadPage(
      const CaptureListQuery(searchText: 'literal A_B'),
    );
    expect(underscore.rows.map((row) => row.capture.id), [
      'literal-underscore',
    ]);

    final backslash = await repository.loadPage(
      const CaptureListQuery(searchText: r'pipe\zone'),
    );
    expect(backslash.rows.map((row) => row.capture.id), ['literal-backslash']);
  });

  test('search is ASCII case-insensitive', () async {
    final page = await repository.loadPage(
      const CaptureListQuery(searchText: 'alice builder'),
    );
    expect(page.rows.map((row) => row.capture.id), ['ascii-case']);
  });

  test('ORs fields within a term and ANDs separate terms', () async {
    final orPage = await repository.loadPage(
      const CaptureListQuery(searchText: 'shared-or-token'),
    );
    expect(orPage.rows.map((row) => row.capture.id).toSet(), {
      'or-location',
      'or-photo-number',
    });

    final andPage = await repository.loadPage(
      const CaptureListQuery(searchText: 'first-and-token second-and-token'),
    );
    expect(andPage.rows.map((row) => row.capture.id), ['and-cross-fields']);
  });

  test(
    'orders equal timestamps by descending ID and cursors through ties',
    () async {
      const query = CaptureListQuery(searchText: 'tie-order-token');
      final first = await repository.loadPage(query, limit: 2);
      final second = await repository.loadPage(
        query,
        after: first.nextCursor,
        limit: 2,
      );

      expect(first.rows.map((row) => row.capture.id), ['tie-c', 'tie-b']);
      expect(second.rows.map((row) => row.capture.id), ['tie-a']);
    },
  );

  test('caps every public page at 50 rows', () async {
    final page = await repository.loadPage(
      const CaptureListQuery(searchText: '21栋'),
      limit: 500,
    );
    expect(page.rows, hasLength(50));
  });

  test(
    'combines project and half-open year month day filters and counts',
    () async {
      expect(
        await repository.count(
          const CaptureListQuery(
            filter: CaptureFilter(projectId: 'dates', year: 2026),
            searchText: 'date-token',
          ),
        ),
        3,
      );
      expect(
        await repository.count(
          const CaptureListQuery(
            filter: CaptureFilter(projectId: 'dates', year: 2026, month: 7),
            searchText: 'date-token',
          ),
        ),
        2,
      );
      final day = await repository.loadPage(
        const CaptureListQuery(
          filter: CaptureFilter(
            projectId: 'dates',
            year: 2026,
            month: 7,
            day: 16,
          ),
          searchText: 'date-token',
        ),
      );
      expect(day.rows.map((row) => row.capture.id), ['date-2026-07-16']);
    },
  );

  test(
    'loads cascading distinct date options for project and search',
    () async {
      final years = await repository.loadDateOptions(
        const CaptureListQuery(
          filter: CaptureFilter(projectId: 'dates'),
          searchText: 'date-token',
        ),
      );
      expect(years.years, [2025, 2026]);
      expect(years.months, isEmpty);
      expect(years.days, isEmpty);

      final months = await repository.loadDateOptions(
        const CaptureListQuery(
          filter: CaptureFilter(projectId: 'dates', year: 2026),
          searchText: 'date-token',
        ),
      );
      expect(months.years, [2025, 2026]);
      expect(months.months, [7, 8]);
      expect(months.days, isEmpty);

      final days = await repository.loadDateOptions(
        const CaptureListQuery(
          filter: CaptureFilter(projectId: 'dates', year: 2026, month: 7),
          searchText: 'date-token',
        ),
      );
      expect(days.years, [2025, 2026]);
      expect(days.months, [7, 8]);
      expect(days.days, [15, 16]);
    },
  );

  test('loads and inspects only ready or failed selectable rows', () async {
    const query = CaptureListQuery(
      filter: CaptureFilter(projectId: 'selection'),
      searchText: 'selection-token',
    );
    final selectable = await repository.loadSelectable(query);
    expect(selectable.ids, {'selection-ready', 'selection-failed'});
    expect(selectable.allReady, isFalse);

    final onlyReady = await repository.loadSelectable(
      const CaptureListQuery(
        filter: CaptureFilter(projectId: 'selection'),
        searchText: 'only-ready-token',
      ),
    );
    expect(onlyReady.ids, {'selection-ready'});
    expect(onlyReady.allReady, isTrue);

    final inspected = await repository.inspectSelection({
      'selection-ready',
      'selection-failed',
      'selection-rendering',
      'missing',
    });
    expect(inspected.ids, {'selection-ready', 'selection-failed'});
    expect(inspected.allReady, isFalse);
  });

  test(
    'loads the nearest newer and older adjacent rows in list order',
    () async {
      const query = CaptureListQuery(
        filter: CaptureFilter(projectId: 'adjacent'),
        searchText: 'adjacent-token',
      );
      final cursor = (sortTime: DateTime(2026, 7, 2, 12, 3), id: 'adj-3');

      final newer = await repository.loadAdjacent(
        query,
        cursor,
        newer: true,
        limit: 2,
      );
      final older = await repository.loadAdjacent(
        query,
        cursor,
        newer: false,
        limit: 2,
      );

      expect(newer.map((row) => row.capture.id), ['adj-5', 'adj-4']);
      expect(older.map((row) => row.capture.id), ['adj-2', 'adj-1']);
    },
  );

  test(
    'watches the newest matching cursor and selected status changes',
    () async {
      const query = CaptureListQuery(
        filter: CaptureFilter(projectId: 'adjacent'),
        searchText: 'adjacent-token',
      );
      final cursors = StreamIterator(repository.watchNewestCursor(query));
      addTearDown(cursors.cancel);
      expect(await cursors.moveNext(), isTrue);
      expect(cursors.current?.id, 'adj-5');

      await database
          .into(database.captureRecords)
          .insert(
            CaptureRecordsCompanion.insert(
              id: 'adj-6',
              projectId: 'adjacent',
              workLocation: '施工区',
              workContent: '安装检查',
              photographer: 'Builder',
              notes: const Value('adjacent-token'),
              originalPath: '/private/adj-6.jpg',
              status: CaptureStatus.rendering,
              createdAt: DateTime(2026, 7, 2, 12, 6),
              capturedAt: Value(DateTime(2026, 7, 2, 12, 6)),
            ),
          );
      expect(await cursors.moveNext(), isTrue);
      expect(cursors.current?.id, 'adj-6');

      final selected = StreamIterator(repository.watchByIds({'adj-6'}));
      addTearDown(selected.cancel);
      expect(await selected.moveNext(), isTrue);
      expect(selected.current.single.capture.status, CaptureStatus.rendering);
      await database.markReady(
        captureId: 'adj-6',
        publishedUri: 'content://media/adj-6',
      );
      expect(await selected.moveNext(), isTrue);
      expect(selected.current.single.capture.status, CaptureStatus.ready);
    },
  );

  test('cursor query plans use global and project cursor indexes', () async {
    final globalPlan = await database
        .customSelect(
          '''
EXPLAIN QUERY PLAN
SELECT c.*, p.name AS project_name
FROM captures AS c
INNER JOIN projects AS p ON p.id = c.project_id
WHERE c.status <> ? AND p.restore_operation_id IS NULL
ORDER BY COALESCE(c.captured_at, c.created_at) DESC, c.id DESC
LIMIT ?
''',
          variables: [
            Variable<String>(CaptureStatus.pendingCamera.name),
            const Variable<int>(51),
          ],
        )
        .get();
    expect(
      globalPlan.map((row) => row.read<String>('detail')).join('\n'),
      contains('capture_records_sort_cursor_idx'),
    );

    final projectPlan = await database
        .customSelect(
          '''
EXPLAIN QUERY PLAN
SELECT c.*, p.name AS project_name
FROM captures AS c
INNER JOIN projects AS p ON p.id = c.project_id
WHERE c.status <> ? AND p.restore_operation_id IS NULL AND c.project_id = ?
ORDER BY COALESCE(c.captured_at, c.created_at) DESC, c.id DESC
LIMIT ?
''',
          variables: [
            Variable<String>(CaptureStatus.pendingCamera.name),
            const Variable<String>('bulk'),
            const Variable<int>(51),
          ],
        )
        .get();
    expect(
      projectPlan.map((row) => row.read<String>('detail')).join('\n'),
      contains('capture_records_project_sort_cursor_idx'),
    );
  });
}
