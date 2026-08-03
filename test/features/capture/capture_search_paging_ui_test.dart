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
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/all_captures_screen.dart';
import 'package:sitemark/features/capture/capture_paged_list.dart';
import 'package:sitemark/features/capture/capture_pager_controller.dart';
import 'package:sitemark/features/projects/project_detail_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

CaptureSummary _summary(
  int index, {
  String projectId = 'project-1',
  String projectName = '东区厂房改造',
  String? workLocation,
  String? notes,
  String? address,
  String? photoNumber,
  DateTime? capturedAt,
}) {
  final time =
      capturedAt ??
      DateTime(2026, 7, 16, 12).subtract(Duration(minutes: index));
  return CaptureSummary(
    capture: CaptureRecord(
      id: 'capture-$index',
      projectId: projectId,
      photoNumber: photoNumber ?? 'SM-20260716-${index + 1}',
      workLocation: workLocation ?? '区域 $index',
      workContent: '风管检查',
      photographer: '张工',
      notes: notes,
      address: address,
      originalPath: '/private/capture-$index.jpg',
      status: CaptureStatus.ready,
      createdAt: time,
      capturedAt: time,
      processingAttempts: 0,
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    ),
    projectName: projectName,
  );
}

CapturePage _page(List<CaptureSummary> rows, {required bool hasMore}) {
  final last = rows.lastOrNull;
  return CapturePage(
    rows: rows,
    nextCursor: last == null
        ? null
        : (
            sortTime: last.capture.capturedAt ?? last.capture.createdAt,
            id: last.capture.id,
          ),
    hasMore: hasMore,
  );
}

Widget _localized({
  required Widget home,
  AppDatabase? database,
  bool disableAnimations = false,
}) {
  return ProviderScope(
    overrides: [
      if (database != null) databaseProvider.overrideWithValue(database),
    ],
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
        data: MediaQueryData(
          size: const Size(400, 800),
          disableAnimations: disableAnimations,
        ),
        child: home,
      ),
    ),
  );
}

Widget _pagedHarness(
  CapturePagerController controller,
  CaptureQuerySource source, {
  bool disableAnimations = false,
}) {
  return _localized(
    disableAnimations: disableAnimations,
    home: Scaffold(
      body: CapturePagedList(
        controller: controller,
        source: source,
        emptyMessage: '没有记录',
        itemBuilder: (context, summary, visibleRows) => SizedBox(
          key: Key('row-${summary.capture.id}'),
          height: 64,
          child: Text(summary.capture.workLocation),
        ),
      ),
    ),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 20,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) return;
  }
  fail('UI did not reach the expected state after ${maxPumps * 50}ms');
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets(
    'all records debounces search for exactly 250ms and back exits search',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final source = _FakeCaptureQuerySource(
        defaultPage: _page([
          _summary(
            0,
            notes: '21栋机房复核',
            address: '21栋北侧入口',
            photoNumber: '21栋-001',
          ),
        ], hasMore: false),
        dateOptions: const CaptureDateOptions(years: [2030]),
      );
      addTearDown(() {
        unawaited(source.dispose());
        unawaited(database.close());
      });

      await tester.pumpWidget(
        _localized(
          database: database,
          home: AllCapturesScreen(querySource: source),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter-year')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, '2030'), findsOneWidget);
      expect(find.widgetWithText(MenuItemButton, '2026'), findsNothing);
      await tester.tapAt(const Offset(390, 790));
      await tester.pumpAndSettle();

      source.pageQueries.clear();
      await tester.tap(find.byKey(const Key('search-captures')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('capture-search-field')),
        '21栋',
      );
      await tester.pump();
      expect(find.byKey(const Key('clear-capture-search')), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 249));
      expect(source.pageQueries, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(source.pageQueries.single.searchText, '21栋');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('capture-search-snippet')), findsOneWidget);
      expect(find.text('备注：21栋机房复核'), findsOneWidget);
      expect(find.text('地址：21栋北侧入口'), findsNothing);
      expect(find.text('照片编号：21栋-001'), findsNothing);

      await tester.binding.handlePopRoute();
      await _pumpUntil(
        tester,
        () =>
            find.byKey(const Key('capture-search-field')).evaluate().isEmpty &&
            find.byKey(const Key('capture-list-content')).evaluate().length ==
                1,
      );
      expect(find.byKey(const Key('capture-search-field')), findsNothing);
      expect(find.byType(AllCapturesScreen), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets(
    'query change while scrolled keeps one scroll position and returns to top',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final nextQueryPage = Completer<CapturePage>();
      final source = _FakeCaptureQuerySource()
        ..enqueue(
          () =>
              Future.value(_page(List.generate(50, _summary), hasMore: false)),
        )
        ..enqueue(() => nextQueryPage.future);
      addTearDown(() {
        unawaited(source.dispose());
        unawaited(database.close());
      });

      await tester.pumpWidget(
        _localized(
          database: database,
          home: AllCapturesScreen(querySource: source),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('capture-35')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        greaterThan(0),
      );

      source.pageQueries.clear();
      await tester.tap(find.byKey(const Key('search-captures')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('capture-search-field')),
        '新查询',
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(source.pageQueries.single.searchText, '新查询');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byKey(const Key('capture-list-skeleton')), findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        0,
      );

      nextQueryPage.complete(
        _page([_summary(99, workLocation: '新查询结果')], hasMore: false),
      );
      await _pumpUntil(
        tester,
        () => find.byKey(const ValueKey('capture-99')).evaluate().isNotEmpty,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byKey(const ValueKey('capture-99')), findsOneWidget);
      expect(find.byKey(const Key('capture-list-content')), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets('project, date, and search compose into one repository query', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final source = _FakeCaptureQuerySource(
      defaultPage: _page([_summary(0)], hasMore: false),
      dateOptions: const CaptureDateOptions(years: [2026]),
    );
    addTearDown(() {
      unawaited(source.dispose());
      unawaited(database.close());
    });

    await tester.pumpWidget(
      _localized(
        database: database,
        home: ProjectDetailScreen(projectId: 'project-1', querySource: source),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-captures')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('capture-search-field')), '风管');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('filter-year')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '2026'));
    await tester.pumpAndSettle();

    final query = source.pageQueries.last;
    expect(query.filter.projectId, 'project-1');
    expect(query.filter.year, 2026);
    expect(query.searchText, '风管');
    expect(source.dateQueries.last.filter.projectId, 'project-1');

    await _unmount(tester);
  });

  testWidgets(
    'project deep link shows a skeleton then an explicit missing state',
    (tester) async {
      final database = _ControlledProjectDatabase();
      final source = _FakeCaptureQuerySource();
      addTearDown(() {
        unawaited(source.dispose());
        unawaited(database.close());
      });

      await tester.pumpWidget(
        _localized(
          database: database,
          home: ProjectDetailScreen(
            projectId: 'missing-project',
            querySource: source,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('project-capture-list-skeleton')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('search-captures')), findsNothing);
      expect(find.byKey(const Key('edit-captures')), findsNothing);

      database.projectLookup.complete(null);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('project-not-found')), findsOneWidget);
      expect(find.text('项目不存在或已删除'), findsWidgets);
      expect(
        find.byKey(const Key('project-capture-list-skeleton')),
        findsNothing,
      );
      expect(find.byKey(const Key('search-captures')), findsNothing);
      expect(find.byKey(const Key('edit-captures')), findsNothing);
      expect(find.byKey(const Key('project-actions')), findsNothing);

      await _unmount(tester);
    },
  );

  testWidgets('project lookup error shows an explicit localized state', (
    tester,
  ) async {
    final database = _ControlledProjectDatabase();
    final source = _FakeCaptureQuerySource();
    addTearDown(() {
      unawaited(source.dispose());
      unawaited(database.close());
    });

    await tester.pumpWidget(
      _localized(
        database: database,
        home: ProjectDetailScreen(
          projectId: 'unavailable-project',
          querySource: source,
        ),
      ),
    );
    await tester.pump();
    database.projectLookup.completeError(StateError('lookup failed'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('project-load-error')), findsOneWidget);
    expect(find.text('项目加载失败，请返回后重试'), findsWidgets);
    expect(find.byKey(const Key('search-captures')), findsNothing);
    expect(find.byKey(const Key('edit-captures')), findsNothing);

    await _unmount(tester);
  });

  testWidgets(
    'successful project deep link leaves loading for normal content',
    (tester) async {
      final database = _ControlledProjectDatabase();
      final project = await database.createProject(
        id: 'project-1',
        name: '东区厂房改造',
      );
      final source = _FakeCaptureQuerySource(
        defaultPage: _page([_summary(0)], hasMore: false),
      );
      addTearDown(() {
        unawaited(source.dispose());
        unawaited(database.close());
      });

      await tester.pumpWidget(
        _localized(
          database: database,
          home: ProjectDetailScreen(
            projectId: 'project-1',
            querySource: source,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('project-capture-list-skeleton')),
        findsOneWidget,
      );

      database.projectLookup.complete(project);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('project-not-found')), findsNothing);
      expect(find.byKey(const Key('project-load-error')), findsNothing);
      expect(find.text('东区厂房改造'), findsWidgets);
      expect(find.byKey(const ValueKey('capture-0')), findsOneWidget);
      expect(find.byKey(const Key('search-captures')), findsOneWidget);
      expect(find.byKey(const Key('edit-captures')), findsOneWidget);

      await _unmount(tester);
    },
  );

  testWidgets('initial load uses a skeleton and does not wait for count', (
    tester,
  ) async {
    final page = Completer<CapturePage>();
    final count = Completer<int>();
    final source = _FakeCaptureQuerySource(countFuture: count.future)
      ..enqueue(() => page.future);
    final controller = CapturePagerController(source);
    unawaited(controller.setQuery(const CaptureListQuery()));
    addTearDown(() {
      controller.dispose();
      unawaited(source.dispose());
    });

    await tester.pumpWidget(_pagedHarness(controller, source));
    await tester.pump();
    expect(find.byKey(const Key('capture-list-skeleton')), findsOneWidget);

    page.complete(_page([_summary(0)], hasMore: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('row-capture-0')), findsOneWidget);
    expect(controller.state.totalCount, isNull);

    count.complete(1);
    await tester.pump();
    expect(find.byKey(const Key('row-capture-0')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('initial error retries without leaving the list surface', (
    tester,
  ) async {
    final source = _FakeCaptureQuerySource()
      ..enqueue(() => Future.error(StateError('first page failed')))
      ..enqueue(() => Future.value(_page([_summary(0)], hasMore: false)));
    final controller = CapturePagerController(source);
    unawaited(controller.setQuery(const CaptureListQuery()));
    addTearDown(() {
      controller.dispose();
      unawaited(source.dispose());
    });

    await tester.pumpWidget(_pagedHarness(controller, source));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture-initial-error')), findsOneWidget);

    await tester.tap(find.byKey(const Key('capture-initial-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('row-capture-0')), findsOneWidget);
    expect(find.byKey(const Key('capture-initial-error')), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
    'eight remaining rows load more and retry keeps existing cards live',
    (tester) async {
      final firstRows = List.generate(50, _summary);
      final nextPage = Completer<CapturePage>();
      final source = _FakeCaptureQuerySource()
        ..enqueue(() => Future.value(_page(firstRows, hasMore: true)))
        ..enqueue(() => nextPage.future)
        ..enqueue(() => Future.value(_page([_summary(50)], hasMore: false)));
      final controller = CapturePagerController(source);
      unawaited(controller.setQuery(const CaptureListQuery()));
      addTearDown(() {
        controller.dispose();
        unawaited(source.dispose());
      });

      await tester.pumpWidget(_pagedHarness(controller, source));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('row-capture-42')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(source.pageQueries, hasLength(2));
      expect(controller.state.loadingMore, isTrue);
      await tester.scrollUntilVisible(
        find.byKey(const Key('capture-next-page-loading')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const Key('capture-next-page-loading')),
        findsOneWidget,
      );
      expect(controller.state.rows.first.capture.id, 'capture-0');

      nextPage.completeError(StateError('next page failed'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('capture-next-page-retry')), findsOneWidget);
      expect(controller.state.rows.first.capture.id, 'capture-0');

      await tester.tap(find.byKey(const Key('capture-next-page-retry')));
      await tester.pumpAndSettle();
      expect(controller.state.rows, hasLength(51));
      expect(source.watchedIdSets.last, hasLength(51));

      source.watchedRows.add([
        _summary(0, workLocation: '已实时更新'),
        ...List.generate(50, (index) => _summary(index + 1)),
      ]);
      await tester.pump();
      expect(controller.state.rows.first.capture.workLocation, '已实时更新');
      await _unmount(tester);
    },
  );

  testWidgets(
    'watched edit that no longer matches the search refreshes the page',
    (tester) async {
      final source = _FakeCaptureQuerySource()
        ..enqueue(
          () => Future.value(
            _page([_summary(0, notes: '保留关键词')], hasMore: false),
          ),
        )
        ..enqueue(() => Future.value(_page([], hasMore: false)));
      final controller = CapturePagerController(source);
      unawaited(
        controller.setQuery(const CaptureListQuery(searchText: '保留关键词')),
      );
      addTearDown(() {
        controller.dispose();
        unawaited(source.dispose());
      });

      await tester.pumpWidget(_pagedHarness(controller, source));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('row-capture-0')), findsOneWidget);

      source.watchedRows.add([_summary(0, notes: '已移除关键词')]);
      await tester.pumpAndSettle();

      expect(source.pageQueries, hasLength(2));
      expect(find.byKey(const Key('row-capture-0')), findsNothing);
      await _unmount(tester);
    },
  );

  testWidgets('watched edit outside the date predicate refreshes the page', (
    tester,
  ) async {
    final source = _FakeCaptureQuerySource()
      ..enqueue(
        () => Future.value(
          _page([
            _summary(0, capturedAt: DateTime(2026, 7, 16, 12)),
          ], hasMore: false),
        ),
      )
      ..enqueue(() => Future.value(_page([], hasMore: false)));
    final controller = CapturePagerController(source);
    unawaited(
      controller.setQuery(
        const CaptureListQuery(
          filter: CaptureFilter(year: 2026, month: 7, day: 16),
        ),
      ),
    );
    addTearDown(() {
      controller.dispose();
      unawaited(source.dispose());
    });

    await tester.pumpWidget(_pagedHarness(controller, source));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('row-capture-0')), findsOneWidget);

    source.watchedRows.add([
      _summary(0, capturedAt: DateTime(2026, 7, 17, 12)),
    ]);
    await tester.pumpAndSettle();

    expect(source.pageQueries, hasLength(2));
    expect(find.byKey(const Key('row-capture-0')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('stale watched refresh cannot overwrite a later query', (
    tester,
  ) async {
    final staleRefresh = Completer<CapturePage>();
    final source = _FakeCaptureQuerySource()
      ..enqueue(
        () => Future.value(_page([_summary(0, notes: '旧关键词')], hasMore: false)),
      )
      ..enqueue(() => staleRefresh.future)
      ..enqueue(
        () => Future.value(_page([_summary(1, notes: '新关键词')], hasMore: false)),
      );
    final controller = CapturePagerController(source);
    unawaited(controller.setQuery(const CaptureListQuery(searchText: '旧关键词')));
    addTearDown(() {
      controller.dispose();
      unawaited(source.dispose());
    });

    await tester.pumpWidget(_pagedHarness(controller, source));
    await tester.pumpAndSettle();
    source.watchedRows.add([_summary(0, notes: '已移除关键词')]);
    await _pumpUntil(tester, () => source.pageQueries.length == 2);

    await controller.setQuery(const CaptureListQuery(searchText: '新关键词'));
    await tester.pump();
    staleRefresh.complete(_page([_summary(2, notes: '过期关键词')], hasMore: false));
    await tester.pumpAndSettle();

    expect(controller.state.query.searchText, '新关键词');
    expect(find.byKey(const Key('row-capture-1')), findsOneWidget);
    expect(find.byKey(const Key('row-capture-2')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a newer cursor refreshes at top without showing an action', (
    tester,
  ) async {
    final source = _FakeCaptureQuerySource()
      ..enqueue(() => Future.value(_page([_summary(1)], hasMore: false)))
      ..enqueue(
        () => Future.value(
          _page([
            _summary(0, capturedAt: DateTime(2026, 7, 16, 13)),
          ], hasMore: false),
        ),
      );
    final controller = CapturePagerController(source);
    unawaited(controller.setQuery(const CaptureListQuery()));
    addTearDown(() {
      controller.dispose();
      unawaited(source.dispose());
    });
    await tester.pumpWidget(_pagedHarness(controller, source));
    await tester.pumpAndSettle();

    source.newestCursors.add((
      sortTime: DateTime(2026, 7, 16, 13),
      id: 'capture-0',
    ));
    await tester.pumpAndSettle();

    expect(source.pageQueries, hasLength(2));
    expect(find.byKey(const Key('capture-new-records')), findsNothing);
    expect(find.byKey(const Key('row-capture-0')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a newer cursor while scrolled shows the localized action', (
    tester,
  ) async {
    final rows = List.generate(20, _summary);
    final source = _FakeCaptureQuerySource()
      ..enqueue(() => Future.value(_page(rows, hasMore: false)))
      ..enqueue(
        () => Future.value(
          _page([
            _summary(99, capturedAt: DateTime(2026, 7, 16, 13)),
          ], hasMore: false),
        ),
      );
    final controller = CapturePagerController(source);
    unawaited(controller.setQuery(const CaptureListQuery()));
    addTearDown(() {
      controller.dispose();
      unawaited(source.dispose());
    });
    await tester.pumpWidget(_pagedHarness(controller, source));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    source.newestCursors.add((
      sortTime: DateTime(2026, 7, 16, 13),
      id: 'capture-99',
    ));
    await tester.pump();

    expect(find.byKey(const Key('capture-new-records')), findsOneWidget);
    expect(find.text('有新记录'), findsOneWidget);
    expect(source.pageQueries, hasLength(1));

    await tester.tap(find.byKey(const Key('capture-new-records')));
    await tester.pumpAndSettle();
    expect(source.pageQueries, hasLength(2));
    expect(find.byKey(const Key('row-capture-99')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
    'reduced animation makes the new list and title transitions zero',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final source = _FakeCaptureQuerySource(
        defaultPage: _page([_summary(0)], hasMore: false),
      );
      addTearDown(() {
        unawaited(source.dispose());
        unawaited(database.close());
      });
      await tester.pumpWidget(
        _localized(
          database: database,
          disableAnimations: true,
          home: AllCapturesScreen(querySource: source),
        ),
      );
      await tester.pumpAndSettle();

      final listSwitcher = tester.widget<AnimatedSwitcher>(
        find.byKey(const Key('capture-page-switcher')),
      );
      expect(listSwitcher.duration, Duration.zero);

      await tester.tap(find.byKey(const Key('search-captures')));
      await tester.pump();
      final titleSwitcher = tester.widget<AnimatedSwitcher>(
        find.byKey(const Key('capture-search-title-switcher')),
      );
      expect(titleSwitcher.duration, Duration.zero);
      expect(find.byKey(const Key('capture-search-field')), findsOneWidget);
      await _unmount(tester);
    },
  );
}

final class _FakeCaptureQuerySource implements CaptureQuerySource {
  _FakeCaptureQuerySource({
    this.defaultPage = const CapturePage(
      rows: [],
      nextCursor: null,
      hasMore: false,
    ),
    this.dateOptions = const CaptureDateOptions(),
    this.countFuture,
  });

  final CapturePage defaultPage;
  final CaptureDateOptions dateOptions;
  final Future<int>? countFuture;
  final Queue<Future<CapturePage> Function()> _pages = Queue();
  final List<CaptureListQuery> pageQueries = [];
  final List<CaptureListQuery> dateQueries = [];
  final List<Set<String>> watchedIdSets = [];
  final StreamController<CapturePageCursor?> newestCursors =
      StreamController<CapturePageCursor?>.broadcast(sync: true);
  final StreamController<List<CaptureSummary>> watchedRows =
      StreamController<List<CaptureSummary>>.broadcast(sync: true);
  bool _disposed = false;

  void enqueue(Future<CapturePage> Function() loader) => _pages.add(loader);

  @override
  Future<CapturePage> loadPage(
    CaptureListQuery query, {
    CapturePageCursor? after,
    int limit = 50,
  }) {
    pageQueries.add(query);
    return _pages.isEmpty ? Future.value(defaultPage) : _pages.removeFirst()();
  }

  @override
  Future<int> count(CaptureListQuery query) => countFuture ?? Future.value(0);

  @override
  Future<CaptureDateOptions> loadDateOptions(CaptureListQuery query) async {
    dateQueries.add(query);
    return dateOptions;
  }

  @override
  Stream<CapturePageCursor?> watchNewestCursor(CaptureListQuery query) =>
      newestCursors.stream;

  @override
  Stream<List<CaptureSummary>> watchByIds(Set<String> ids) {
    watchedIdSets.add(Set.unmodifiable(ids));
    return watchedRows.stream;
  }

  @override
  Future<List<CaptureSummary>> loadAdjacent(
    CaptureListQuery query,
    CapturePageCursor cursor, {
    required bool newer,
    int limit = 10,
  }) async => const [];

  @override
  Future<CaptureSelectionSnapshot> inspectSelection(Set<String> ids) async =>
      CaptureSelectionSnapshot(ids: ids, allReady: ids.isNotEmpty);

  @override
  Future<CaptureSelectionSnapshot> loadSelectable(
    CaptureListQuery query,
  ) async => const CaptureSelectionSnapshot(ids: {}, allReady: false);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await newestCursors.close();
    await watchedRows.close();
  }
}

final class _ControlledProjectDatabase extends AppDatabase {
  _ControlledProjectDatabase() : super.forTesting(NativeDatabase.memory());

  final Completer<Project?> projectLookup = Completer<Project?>();
  final StreamController<Project?> _projectWatch =
      StreamController<Project?>.broadcast();
  var _watchBridged = false;

  void _bridgeProjectLookup() {
    if (_watchBridged) return;
    _watchBridged = true;
    projectLookup.future.then(
      (value) {
        if (!_projectWatch.isClosed) {
          _projectWatch.add(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_projectWatch.isClosed) {
          _projectWatch.addError(error, stackTrace);
        }
      },
    );
  }

  @override
  Future<Project?> projectById(String projectId) => projectLookup.future;

  @override
  Stream<Project?> watchProjectById(String projectId) {
    _bridgeProjectLookup();
    return _projectWatch.stream;
  }

  @override
  Future<void> close() async {
    await _projectWatch.close();
    await super.close();
  }
}
