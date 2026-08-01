import 'dart:async';
import 'dart:collection';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/all_captures_screen.dart';
import 'package:sitemark/features/projects/project_detail_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

CaptureSummary _summary(int index, {String projectId = 'project-1'}) {
  final time = DateTime(2026, 7, 16, 12).subtract(Duration(minutes: index));
  return CaptureSummary(
    capture: CaptureRecord(
      id: 'capture-$index',
      projectId: projectId,
      photoNumber: 'SM-20260716-${index + 1}',
      workLocation: '区域 $index',
      workContent: '风管检查',
      photographer: '张工',
      originalPath: '/private/capture-$index.jpg',
      status: CaptureStatus.ready,
      createdAt: time,
      capturedAt: time,
      processingAttempts: 0,
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    ),
    projectName: '东区厂房改造',
  );
}

Widget _localized({required AppDatabase database, required Widget home}) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(database)],
    child: MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: home,
      ),
    ),
  );
}

IconButton _actionButton(WidgetTester tester, IconData icon) {
  final finder = find.ancestor(
    of: find.byIcon(icon),
    matching: find.byType(IconButton),
  );
  return tester.widget<IconButton>(finder.first);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'all records selects 120 query results from 50 loaded rows and retries failure',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'project-1', name: '东区厂房改造');
      final firstAttempt = Completer<CaptureSelectionSnapshot>();
      final retryAttempt = Completer<CaptureSelectionSnapshot>();
      final source =
          _ControlledCaptureQuerySource(rows: List.generate(50, _summary))
            ..selectable.addAll([
              () => firstAttempt.future,
              () => retryAttempt.future,
            ]);

      await tester.pumpWidget(
        _localized(
          database: database,
          home: AllCapturesScreen(querySource: source),
        ),
      );
      await _pumpUi(tester);
      expect(source.pageLimits.first, 50);

      await tester.tap(find.byKey(const Key('edit-captures')));
      await _pumpUi(tester);
      await tester.tap(find.byType(Checkbox).first);
      await _pumpUi(tester);
      expect(find.text('已选 1 张'), findsOneWidget);

      await tester.tap(find.byKey(const Key('select-all-captures')));
      await tester.pump();
      expect(find.byKey(const Key('select-all-progress')), findsOneWidget);

      firstAttempt.completeError(StateError('selection failed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('已选 1 张'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pump();
      retryAttempt.complete(
        CaptureSelectionSnapshot(
          ids: List.generate(120, (index) => 'capture-$index').toSet(),
          allReady: false,
        ),
      );
      await _pumpUi(tester);

      expect(find.text('已选 120 张'), findsOneWidget);
      expect(_actionButton(tester, Icons.archive_outlined).onPressed, isNull);
      expect(_actionButton(tester, Icons.save_outlined).onPressed, isNull);
      expect(
        _actionButton(tester, Icons.cleaning_services_outlined).onPressed,
        isNotNull,
      );
      expect(_actionButton(tester, Icons.delete_outline).onPressed, isNotNull);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await _pumpUi(tester);
      expect(find.textContaining('120 张照片'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await _pumpUi(tester);

      await tester.tap(find.byKey(const Key('select-all-captures')));
      await _pumpUi(tester);
      expect(find.byKey(const Key('batch-action-bar')), findsNothing);
      await _unmount(tester);
    },
  );

  testWidgets(
    'project selection ignores stale qualification and retries the latest failure',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'project-1', name: '东区厂房改造');
      final first = Completer<CaptureSelectionSnapshot>();
      final second = Completer<CaptureSelectionSnapshot>();
      final retry = Completer<CaptureSelectionSnapshot>();
      final source =
          _ControlledCaptureQuerySource(rows: List.generate(50, _summary))
            ..inspections.addAll([
              () => first.future,
              () => second.future,
              () => retry.future,
            ]);

      await tester.pumpWidget(
        _localized(
          database: database,
          home: ProjectDetailScreen(
            projectId: 'project-1',
            querySource: source,
          ),
        ),
      );
      await _pumpUi(tester);
      await tester.tap(find.byKey(const Key('edit-captures')));
      await _pumpUi(tester);

      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pump();
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      expect(source.inspectedIds, [
        {'capture-0'},
        {'capture-0', 'capture-1'},
      ]);

      first.complete(
        const CaptureSelectionSnapshot(ids: {'capture-0'}, allReady: true),
      );
      await tester.pump();
      expect(find.text('已选 2 张'), findsOneWidget);
      expect(_actionButton(tester, Icons.archive_outlined).onPressed, isNull);

      second.completeError(StateError('inspect failed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('已选 2 张'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pump();
      retry.complete(
        const CaptureSelectionSnapshot(
          ids: {'capture-0', 'capture-1'},
          allReady: true,
        ),
      );
      await _pumpUi(tester);
      expect(
        _actionButton(tester, Icons.archive_outlined).onPressed,
        isNotNull,
      );
      expect(_actionButton(tester, Icons.save_outlined).onPressed, isNotNull);
      await _unmount(tester);
    },
  );

  testWidgets('full toggle clears a manually complete all-records selection', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final source = _ControlledCaptureQuerySource(
      rows: List.generate(50, _summary),
      selectableSnapshot: const CaptureSelectionSnapshot(
        ids: {'capture-0'},
        allReady: true,
      ),
    );

    await tester.pumpWidget(
      _localized(
        database: database,
        home: AllCapturesScreen(querySource: source),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.byKey(const Key('edit-captures')));
    await _pumpUi(tester);
    await tester.tap(find.byType(Checkbox).first);
    await _pumpUi(tester);
    expect(find.text('已选 1 张'), findsOneWidget);

    await tester.tap(find.byKey(const Key('select-all-captures')));
    await _pumpUi(tester);

    expect(source.selectableQueries, hasLength(1));
    expect(find.byKey(const Key('batch-action-bar')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('all-records full toggle refreshes changed query membership', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final source =
        _ControlledCaptureQuerySource(rows: List.generate(50, _summary))
          ..selectable.addAll([
            () => Future.value(
              CaptureSelectionSnapshot(
                ids: List.generate(120, (index) => 'capture-$index').toSet(),
                allReady: true,
              ),
            ),
            () => Future.value(
              CaptureSelectionSnapshot(
                ids: List.generate(121, (index) => 'capture-$index').toSet(),
                allReady: true,
              ),
            ),
          ]);

    await tester.pumpWidget(
      _localized(
        database: database,
        home: AllCapturesScreen(querySource: source),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.byKey(const Key('edit-captures')));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const Key('select-all-captures')));
    await _pumpUi(tester);
    expect(find.text('已选 120 张'), findsOneWidget);

    await tester.tap(find.byKey(const Key('select-all-captures')));
    await _pumpUi(tester);

    expect(source.selectableQueries, hasLength(2));
    expect(find.text('已选 121 张'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('project detail full selection includes unloaded IDs', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final source = _ControlledCaptureQuerySource(
      rows: List.generate(50, _summary),
      selectableSnapshot: CaptureSelectionSnapshot(
        ids: List.generate(120, (index) => 'capture-$index').toSet(),
        allReady: true,
      ),
    );

    await tester.pumpWidget(
      _localized(
        database: database,
        home: ProjectDetailScreen(projectId: 'project-1', querySource: source),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.byKey(const Key('edit-captures')));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const Key('select-all-captures')));
    await _pumpUi(tester);

    expect(source.selectableQueries.single.filter.projectId, 'project-1');
    expect(find.text('已选 120 张'), findsOneWidget);
    expect(_actionButton(tester, Icons.archive_outlined).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('select-all-captures')));
    await _pumpUi(tester);

    expect(source.selectableQueries, hasLength(2));
    expect(find.byKey(const Key('batch-action-bar')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('leaving edit mode invalidates an in-flight full selection', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final pending = Completer<CaptureSelectionSnapshot>();
    final source = _ControlledCaptureQuerySource(
      rows: List.generate(50, _summary),
    )..selectable.add(() => pending.future);

    await tester.pumpWidget(
      _localized(
        database: database,
        home: AllCapturesScreen(querySource: source),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.byKey(const Key('edit-captures')));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const Key('select-all-captures')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pump();

    pending.complete(
      CaptureSelectionSnapshot(
        ids: List.generate(120, (index) => 'capture-$index').toSet(),
        allReady: true,
      ),
    );
    await _pumpUi(tester);

    expect(find.byKey(const Key('batch-action-bar')), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    await _unmount(tester);
  });
}

final class _ControlledCaptureQuerySource implements CaptureQuerySource {
  _ControlledCaptureQuerySource({
    required this.rows,
    this.selectableSnapshot = const CaptureSelectionSnapshot(
      ids: {},
      allReady: false,
    ),
  });

  final List<CaptureSummary> rows;
  final CaptureSelectionSnapshot selectableSnapshot;
  final Queue<Future<CaptureSelectionSnapshot> Function()> selectable = Queue();
  final Queue<Future<CaptureSelectionSnapshot> Function()> inspections =
      Queue();
  final List<CaptureListQuery> selectableQueries = [];
  final List<Set<String>> inspectedIds = [];
  final List<int> pageLimits = [];

  @override
  Future<CapturePage> loadPage(
    CaptureListQuery query, {
    CapturePageCursor? after,
    int limit = 50,
  }) async {
    pageLimits.add(limit);
    if (after != null) {
      return const CapturePage(rows: [], nextCursor: null, hasMore: false);
    }
    final firstPage = rows.take(limit).toList(growable: false);
    final last = firstPage.last;
    return CapturePage(
      rows: firstPage,
      nextCursor: (sortTime: last.capture.capturedAt!, id: last.capture.id),
      hasMore: true,
    );
  }

  @override
  Future<int> count(CaptureListQuery query) async => 120;

  @override
  Future<CaptureDateOptions> loadDateOptions(CaptureListQuery query) async =>
      const CaptureDateOptions(years: [2026]);

  @override
  Future<CaptureSelectionSnapshot> loadSelectable(CaptureListQuery query) {
    selectableQueries.add(query);
    return selectable.isEmpty
        ? Future.value(selectableSnapshot)
        : selectable.removeFirst()();
  }

  @override
  Future<CaptureSelectionSnapshot> inspectSelection(Set<String> ids) {
    inspectedIds.add(Set.unmodifiable(ids));
    return inspections.isEmpty
        ? Future.value(
            CaptureSelectionSnapshot(ids: ids, allReady: ids.isNotEmpty),
          )
        : inspections.removeFirst()();
  }

  @override
  Future<List<CaptureSummary>> loadAdjacent(
    CaptureListQuery query,
    CapturePageCursor cursor, {
    required bool newer,
    int limit = 10,
  }) async => const [];

  @override
  Stream<CapturePageCursor?> watchNewestCursor(CaptureListQuery query) =>
      const Stream.empty();

  @override
  Stream<List<CaptureSummary>> watchByIds(Set<String> ids) =>
      const Stream.empty();
}
