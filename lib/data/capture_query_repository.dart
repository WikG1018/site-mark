import 'package:drift/drift.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/capture_status.dart';

final class CapturePage {
  const CapturePage({
    required this.rows,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<CaptureSummary> rows;
  final CapturePageCursor? nextCursor;
  final bool hasMore;
}

final class CaptureSelectionSnapshot {
  const CaptureSelectionSnapshot({required this.ids, required this.allReady});

  final Set<String> ids;
  final bool allReady;
}

abstract interface class CaptureQuerySource {
  Future<CapturePage> loadPage(
    CaptureListQuery query, {
    CapturePageCursor? after,
    int limit = 50,
  });

  Future<int> count(CaptureListQuery query);

  Future<CaptureDateOptions> loadDateOptions(CaptureListQuery query);

  Future<CaptureSelectionSnapshot> loadSelectable(CaptureListQuery query);

  Future<CaptureSelectionSnapshot> inspectSelection(Set<String> ids);

  Future<List<CaptureSummary>> loadAdjacent(
    CaptureListQuery query,
    CapturePageCursor cursor, {
    required bool newer,
    int limit = 10,
  });

  Stream<CapturePageCursor?> watchNewestCursor(CaptureListQuery query);

  Stream<List<CaptureSummary>> watchByIds(Set<String> ids);
}

String escapeLikeLiteral(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

final class CaptureQueryRepository implements CaptureQuerySource {
  CaptureQueryRepository(this._database);

  static const _summarySelect = '''
SELECT c.*, p.name AS project_name
FROM captures AS c
INNER JOIN projects AS p ON p.id = c.project_id
''';
  static const _descendingOrder =
      'ORDER BY COALESCE(c.captured_at, c.created_at) DESC, c.id DESC';

  final AppDatabase _database;

  @override
  Future<CapturePage> loadPage(
    CaptureListQuery query, {
    CapturePageCursor? after,
    int limit = 50,
  }) async {
    final pageLimit = _boundedLimit(limit);
    final predicate = _predicate(query);
    final clauses = [...predicate.clauses];
    final variables = [...predicate.variables];
    if (after != null) {
      clauses.add('''
(
  COALESCE(c.captured_at, c.created_at) < ?
  OR (
    COALESCE(c.captured_at, c.created_at) = ?
    AND c.id < ?
  )
)
''');
      variables.addAll([
        Variable<DateTime>(after.sortTime),
        Variable<DateTime>(after.sortTime),
        Variable<String>(after.id),
      ]);
    }
    variables.add(Variable<int>(pageLimit + 1));

    final result = await _database
        .customSelect(
          '''
$_summarySelect
WHERE ${clauses.join('\nAND ')}
$_descendingOrder
LIMIT ?
''',
          variables: variables,
          readsFrom: {_database.captureRecords, _database.projects},
        )
        .get();
    final hasMore = result.length > pageLimit;
    final rows = result
        .take(pageLimit)
        .map(_mapSummary)
        .toList(growable: false);
    return CapturePage(
      rows: rows,
      nextCursor: rows.isEmpty ? null : _cursorFor(rows.last.capture),
      hasMore: hasMore,
    );
  }

  @override
  Future<int> count(CaptureListQuery query) async {
    final predicate = _predicate(query);
    final row = await _database
        .customSelect(
          '''
SELECT COUNT(*) AS total
FROM captures AS c
INNER JOIN projects AS p ON p.id = c.project_id
WHERE ${predicate.clauses.join('\nAND ')}
''',
          variables: predicate.variables,
          readsFrom: {_database.captureRecords, _database.projects},
        )
        .getSingle();
    return row.read<int>('total');
  }

  @override
  Future<CaptureDateOptions> loadDateOptions(CaptureListQuery query) async {
    final filter = query.filter;
    final years = await _distinctDatePart(
      query.copyWith(filter: CaptureFilter(projectId: filter.projectId)),
      _DatePart.year,
    );
    final months = filter.year == null
        ? const <int>[]
        : await _distinctDatePart(
            query.copyWith(
              filter: CaptureFilter(
                projectId: filter.projectId,
                year: filter.year,
              ),
            ),
            _DatePart.month,
          );
    final days = filter.month == null
        ? const <int>[]
        : await _distinctDatePart(
            query.copyWith(
              filter: CaptureFilter(
                projectId: filter.projectId,
                year: filter.year,
                month: filter.month,
              ),
            ),
            _DatePart.day,
          );
    return CaptureDateOptions(years: years, months: months, days: days);
  }

  Future<List<int>> _distinctDatePart(
    CaptureListQuery query,
    _DatePart part,
  ) async {
    final predicate = _predicate(query);
    final fixedFormat = switch (part) {
      _DatePart.year => '%Y',
      _DatePart.month => '%m',
      _DatePart.day => '%d',
    };
    final rows = await _database
        .customSelect(
          '''
SELECT DISTINCT CAST(
  strftime('$fixedFormat', COALESCE(c.captured_at, c.created_at), 'unixepoch', 'localtime')
  AS INTEGER
) AS value
FROM captures AS c
INNER JOIN projects AS p ON p.id = c.project_id
WHERE ${predicate.clauses.join('\nAND ')}
ORDER BY value ASC
''',
          variables: predicate.variables,
          readsFrom: {_database.captureRecords, _database.projects},
        )
        .get();
    return rows.map((row) => row.read<int>('value')).toList(growable: false);
  }

  @override
  Future<CaptureSelectionSnapshot> loadSelectable(
    CaptureListQuery query,
  ) async {
    final predicate = _predicate(query);
    return _loadSelection(
      clauses: predicate.clauses,
      variables: predicate.variables,
    );
  }

  @override
  Future<CaptureSelectionSnapshot> inspectSelection(Set<String> ids) {
    if (ids.isEmpty) {
      return Future.value(
        const CaptureSelectionSnapshot(ids: {}, allReady: false),
      );
    }
    final placeholders = List.filled(ids.length, '?').join(', ');
    return _loadSelection(
      clauses: ['p.restore_operation_id IS NULL', 'c.id IN ($placeholders)'],
      variables: ids.map(Variable<String>.new).toList(growable: false),
    );
  }

  Future<CaptureSelectionSnapshot> _loadSelection({
    required List<String> clauses,
    required List<Variable<Object>> variables,
  }) async {
    final allClauses = [...clauses, 'c.status IN (?, ?)'];
    final ready = Variable<String>(CaptureStatus.ready.name);
    final failed = Variable<String>(CaptureStatus.failed.name);
    final rows = await _database
        .customSelect(
          '''
SELECT
  c.id,
  MIN(CASE WHEN c.status = ? THEN 1 ELSE 0 END) OVER () AS all_ready
FROM captures AS c
INNER JOIN projects AS p ON p.id = c.project_id
WHERE ${allClauses.join('\nAND ')}
ORDER BY COALESCE(c.captured_at, c.created_at) DESC, c.id DESC
''',
          // The aggregate's ready-status placeholder occurs before WHERE.
          variables: [ready, ...variables, ready, failed],
          readsFrom: {_database.captureRecords, _database.projects},
        )
        .get();
    return CaptureSelectionSnapshot(
      ids: rows.map((row) => row.read<String>('id')).toSet(),
      allReady: rows.isNotEmpty && rows.first.read<int>('all_ready') == 1,
    );
  }

  @override
  Future<List<CaptureSummary>> loadAdjacent(
    CaptureListQuery query,
    CapturePageCursor cursor, {
    required bool newer,
    int limit = 10,
  }) async {
    final adjacentLimit = _boundedLimit(limit);
    final predicate = _predicate(query);
    final comparison = newer ? '>' : '<';
    final order = newer
        ? 'ORDER BY COALESCE(c.captured_at, c.created_at) ASC, c.id ASC'
        : _descendingOrder;
    final rows = await _database
        .customSelect(
          '''
$_summarySelect
WHERE ${predicate.clauses.join('\nAND ')}
AND (
  COALESCE(c.captured_at, c.created_at) $comparison ?
  OR (
    COALESCE(c.captured_at, c.created_at) = ?
    AND c.id $comparison ?
  )
)
$order
LIMIT ?
''',
          variables: [
            ...predicate.variables,
            Variable<DateTime>(cursor.sortTime),
            Variable<DateTime>(cursor.sortTime),
            Variable<String>(cursor.id),
            Variable<int>(adjacentLimit),
          ],
          readsFrom: {_database.captureRecords, _database.projects},
        )
        .get();
    final summaries = rows.map(_mapSummary).toList(growable: false);
    return newer ? summaries.reversed.toList(growable: false) : summaries;
  }

  @override
  Stream<CapturePageCursor?> watchNewestCursor(CaptureListQuery query) {
    final predicate = _predicate(query);
    return _database
        .customSelect(
          '''
$_summarySelect
WHERE ${predicate.clauses.join('\nAND ')}
$_descendingOrder
LIMIT 1
''',
          variables: predicate.variables,
          readsFrom: {_database.captureRecords, _database.projects},
        )
        .watch()
        .map(
          (rows) => rows.isEmpty
              ? null
              : _cursorFor(_mapSummary(rows.single).capture),
        );
  }

  @override
  Stream<List<CaptureSummary>> watchByIds(Set<String> ids) =>
      _database.watchCaptureSummariesByIds(ids);

  _Predicate _predicate(CaptureListQuery query) {
    final clauses = <String>['c.status <> ?', 'p.restore_operation_id IS NULL'];
    final variables = <Variable<Object>>[
      Variable<String>(CaptureStatus.pendingCamera.name),
    ];
    final filter = query.filter;
    if (filter.projectId != null) {
      clauses.add('c.project_id = ?');
      variables.add(Variable<String>(filter.projectId!));
    }
    final range = filter.localRange;
    if (range != null) {
      clauses.add('COALESCE(c.captured_at, c.created_at) >= ?');
      clauses.add('COALESCE(c.captured_at, c.created_at) < ?');
      variables.add(Variable<DateTime>(range.start));
      variables.add(Variable<DateTime>(range.end));
    }
    for (final term in query.normalizedTerms) {
      clauses.add(r'''(
  lower(p.name) LIKE lower(?) ESCAPE '\'
  OR lower(c.work_location) LIKE lower(?) ESCAPE '\'
  OR lower(c.work_content) LIKE lower(?) ESCAPE '\'
  OR lower(c.photographer) LIKE lower(?) ESCAPE '\'
  OR lower(COALESCE(c.notes, '')) LIKE lower(?) ESCAPE '\'
  OR lower(COALESCE(c.photo_number, '')) LIKE lower(?) ESCAPE '\'
  OR lower(COALESCE(c.address, '')) LIKE lower(?) ESCAPE '\'
)''');
      final pattern = '%${escapeLikeLiteral(term)}%';
      variables.addAll(List.generate(7, (_) => Variable<String>(pattern)));
    }
    return _Predicate(clauses: clauses, variables: variables);
  }

  CaptureSummary _mapSummary(QueryRow row) => CaptureSummary(
    capture: _database.captureRecords.map(row.data),
    projectName: row.read<String>('project_name'),
  );

  CapturePageCursor _cursorFor(CaptureRecord capture) =>
      (sortTime: capture.capturedAt ?? capture.createdAt, id: capture.id);

  int _boundedLimit(int limit) {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive');
    }
    return limit > 50 ? 50 : limit;
  }
}

final class _Predicate {
  const _Predicate({required this.clauses, required this.variables});

  final List<String> clauses;
  final List<Variable<Object>> variables;
}

enum _DatePart { year, month, day }
