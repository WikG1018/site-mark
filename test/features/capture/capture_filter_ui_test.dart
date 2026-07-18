import 'dart:math' show max, min;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/all_captures_screen.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/features/projects/project_detail_screen.dart';
import 'package:sitemark/features/capture/capture_date_filter_bar.dart';
import 'package:sitemark/l10n/app_strings.dart';

CaptureRecord _record({required String id, required DateTime capturedAt}) {
  return CaptureRecord(
    id: id,
    projectId: 'project-1',
    photoNumber: 'SM-$id',
    workLocation: 'A 区',
    workContent: '风管',
    photographer: '张工',
    originalPath: '/private/$id.jpg',
    status: CaptureStatus.ready,
    createdAt: capturedAt,
    capturedAt: capturedAt,
    processingAttempts: 0,
    watermarkLocaleCode: 'zh',
    locationResolution: 'resolved',
  );
}

CaptureSummary _summary({required String id, required DateTime capturedAt}) {
  return CaptureSummary(
    capture: _record(id: id, capturedAt: capturedAt),
    projectName: '东区厂房改造',
  );
}

Widget filterHarnessLive(ValueNotifier<CaptureFilter> filter) {
  final summaries = [
    _summary(id: 'a', capturedAt: DateTime(2025, 6, 1, 9)),
    _summary(id: 'b', capturedAt: DateTime(2026, 7, 16, 9)),
    _summary(id: 'c', capturedAt: DateTime(2026, 8, 2, 9)),
    _summary(id: 'd', capturedAt: DateTime(2026, 7, 16, 14)),
    _summary(id: 'e', capturedAt: DateTime(2026, 7, 17, 9)),
  ];
  return MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: ValueListenableBuilder<CaptureFilter>(
        valueListenable: filter,
        builder: (context, value, _) {
          return CaptureDateFilterBar(
            filter: value,
            summaries: summaries,
            onChanged: (next) => filter.value = next,
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('changing year clears month and day', (tester) async {
    final filter = ValueNotifier(
      const CaptureFilter(year: 2026, month: 7, day: 16),
    );
    await tester.pumpWidget(filterHarnessLive(filter));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-year')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '2025'));
    await tester.pumpAndSettle();

    expect(filter.value.year, 2025);
    expect(filter.value.month, isNull);
    expect(filter.value.day, isNull);
  });

  testWidgets('changing month clears day but keeps year', (tester) async {
    final filter = ValueNotifier(
      const CaptureFilter(year: 2026, month: 7, day: 16),
    );
    await tester.pumpWidget(filterHarnessLive(filter));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-month')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '8月'));
    await tester.pumpAndSettle();

    expect(filter.value.year, 2026);
    expect(filter.value.month, 8);
    expect(filter.value.day, isNull);
  });

  testWidgets('clearing year resets the entire date selection', (tester) async {
    final filter = ValueNotifier(
      const CaptureFilter(year: 2026, month: 7, day: 16),
    );
    await tester.pumpWidget(filterHarnessLive(filter));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-year')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '全部年份'));
    await tester.pumpAndSettle();

    expect(filter.value.year, isNull);
    expect(filter.value.month, isNull);
    expect(filter.value.day, isNull);
  });

  testWidgets('month control shows all-months label until year chosen', (
    tester,
  ) async {
    final filter = ValueNotifier(const CaptureFilter());
    await tester.pumpWidget(filterHarnessLive(filter));
    await tester.pumpAndSettle();

    expect(find.text('全部月份'), findsOneWidget);
    expect(find.text('全部日期'), findsOneWidget);
  });

  testWidgets('day options reflect selected year and month', (tester) async {
    final filter = ValueNotifier(const CaptureFilter(year: 2026, month: 7));
    await tester.pumpWidget(filterHarnessLive(filter));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-day')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    // July 16 and July 17 are the distinct days available.
    expect(find.text('16日'), findsWidgets);
    expect(find.text('17日'), findsWidgets);
  });

  testWidgets(
    'all-records changing project clears year/month/day date filters',
    (tester) async {
      // Two projects: project-1 has a July 2026 capture, project-2 has none.
      // Selecting 2026 under "all projects" then switching to project-2 must
      // reset the date cascade so the user is not left staring at a
      // filtered-empty state caused by a stale year selection.
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await database.createProject(id: 'project-1', name: '东区厂房改造');
      await database.createProject(id: 'project-2', name: '西区管线整改');
      final pending = await database.createPendingCapture(
        id: 'capture-a',
        projectId: 'project-1',
        originalPath: '/private/capture-a.jpg',
        workLocation: 'A 区',
        workContent: '风管',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
        createdAt: DateTime(2026, 7, 16, 9),
      );
      final captured = await database.markCaptured(
        captureId: pending.id,
        capturedAt: DateTime(2026, 7, 16, 9, 30),
      );
      final rendering = await database.markRendering(
        captureId: captured.id,
        originalSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      await database.markReady(
        captureId: rendering.id,
        publishedUri: 'content://media/site-mark/capture-a',
      );

      await tester.pumpWidget(
        ProviderScope(
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
            home: const AllCapturesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select year 2026 from the date cascade.
      await tester.tap(find.byKey(const Key('filter-year')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '2026'));
      await tester.pumpAndSettle();

      // The year menu now reflects the 2026 selection instead of "全部年份".
      expect(find.text('全部年份'), findsNothing);

      // Switch the project from "all projects" to project-2 (no captures).
      await tester.tap(find.byKey(const Key('project-filter')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '西区管线整改'));
      await tester.pumpAndSettle();

      // The project -> year -> month -> day cascade must clear: the year
      // control drops back to the "all years" label.
      expect(find.text('全部年份'), findsOneWidget);
      expect(find.text('全部月份'), findsOneWidget);
      expect(find.text('全部日期'), findsOneWidget);

      // Unmount the tree so the StreamBuilder subscriptions to the Drift
      // streams are cancelled before the database closes; otherwise pending
      // stream timers trip the test framework's "timers pending" invariant.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('all-records date options follow the selected project', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await database.createProject(id: 'project-a', name: '甲项目');
    await database.createProject(id: 'project-b', name: '乙项目');

    Future<void> seedReadyCapture({
      required String id,
      required String projectId,
      required DateTime capturedAt,
    }) async {
      final pending = await database.createPendingCapture(
        id: id,
        projectId: projectId,
        originalPath: '/private/$id.jpg',
        workLocation: 'A 区',
        workContent: '风管',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
        createdAt: capturedAt,
      );
      final captured = await database.markCaptured(
        captureId: pending.id,
        capturedAt: capturedAt,
      );
      final rendering = await database.markRendering(
        captureId: captured.id,
        originalSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      await database.markReady(
        captureId: rendering.id,
        publishedUri: 'content://media/site-mark/$id',
      );
    }

    await seedReadyCapture(
      id: 'capture-2025',
      projectId: 'project-a',
      capturedAt: DateTime(2025, 6, 1, 9),
    );
    await seedReadyCapture(
      id: 'capture-2026',
      projectId: 'project-b',
      capturedAt: DateTime(2026, 7, 16, 9),
    );

    await tester.pumpWidget(
      ProviderScope(
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
          home: const AllCapturesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('project-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '乙项目'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-year')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(MenuItemButton, '2026'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, '2025'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
  testWidgets('date controls share one row at 360dp', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final filter = ValueNotifier(const CaptureFilter());
    await tester.pumpWidget(filterHarnessLive(filter));
    await tester.pumpAndSettle();
    final tops = [
      tester.getTopLeft(find.byKey(const Key('filter-year'))).dy,
      tester.getTopLeft(find.byKey(const Key('filter-month'))).dy,
      tester.getTopLeft(find.byKey(const Key('filter-day'))).dy,
    ];
    expect(tops.reduce(max) - tops.reduce(min), lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'filter controls are 44dp rounded rectangles with centered text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final filter = ValueNotifier(const CaptureFilter());
      await tester.pumpWidget(filterHarnessLive(filter));
      await tester.pumpAndSettle();

      final menuFinder = find.byKey(const Key('filter-year'));
      final buttonFinder = find.descendant(
        of: menuFinder,
        matching: find.byType(OutlinedButton),
      );
      final button = tester.widget<OutlinedButton>(buttonFinder);
      final shape = button.style?.shape?.resolve(<WidgetState>{});

      expect(tester.getSize(menuFinder).height, 44);
      expect(shape, isA<RoundedRectangleBorder>());
      final border = shape! as RoundedRectangleBorder;
      expect(border.borderRadius, BorderRadius.circular(10));
      expect(
        (tester.getCenter(buttonFinder).dx -
                tester.getCenter(find.text('全部年份')).dx)
            .abs(),
        lessThan(1),
      );
    },
  );

  testWidgets('all-records controls share one row at 360dp', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final pending = await database.createPendingCapture(
      id: 'capture-a',
      projectId: 'project-1',
      originalPath: '/private/capture-a.jpg',
      workLocation: 'A 区',
      workContent: '风管',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 9),
    );
    final captured = await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9, 30),
    );
    final rendering = await database.markRendering(
      captureId: captured.id,
      originalSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await database.markReady(
      captureId: rendering.id,
      publishedUri: 'content://media/site-mark/capture-a',
    );

    await tester.pumpWidget(
      ProviderScope(
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
          home: const AllCapturesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tops = [
      tester.getTopLeft(find.byKey(const Key('project-filter'))).dy,
      tester.getTopLeft(find.byKey(const Key('filter-year'))).dy,
      tester.getTopLeft(find.byKey(const Key('filter-month'))).dy,
      tester.getTopLeft(find.byKey(const Key('filter-day'))).dy,
    ];
    expect(tops.reduce(max) - tops.reduce(min), lessThan(1));
    expect(tester.takeException(), isNull);

    // Unmount the tree so the StreamBuilder subscriptions to the Drift
    // streams are cancelled before the database closes.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
  // Task 4: capture list edit mode and batch action bar.

  Future<void> seedReadyCaptureForFilterTest(
    AppDatabase database, {
    required String id,
    required String projectId,
    required DateTime capturedAt,
  }) async {
    final pending = await database.createPendingCapture(
      id: id,
      projectId: projectId,
      originalPath: '/private/$id.jpg',
      workLocation: 'A 区',
      workContent: '风管',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      createdAt: capturedAt,
    );
    final captured = await database.markCaptured(
      captureId: pending.id,
      capturedAt: capturedAt,
    );
    final rendering = await database.markRendering(
      captureId: captured.id,
      originalSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await database.markReady(
      captureId: rendering.id,
      publishedUri: 'content://media/site-mark/$id',
    );
  }

  Widget pumpAllCaptures(AppDatabase database) {
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
        home: const AllCapturesScreen(),
      ),
    );
  }

  Widget pumpProjectDetail(AppDatabase database, String projectId) {
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
        home: ProjectDetailScreen(projectId: projectId),
      ),
    );
  }

  Future<void> unmountTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('record cards show a short date and sequence title', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '云湖之城');
    await seedReadyCaptureForFilterTest(
      database,
      id: 'capture-a',
      projectId: 'project-1',
      capturedAt: DateTime(2026, 7, 17, 9),
    );

    await tester.pumpWidget(pumpAllCaptures(database));
    await tester.pumpAndSettle();

    expect(find.text('2026-07-17 · 001'), findsOneWidget);
    expect(find.text('云湖之城-SM-20260717-001'), findsNothing);
    await unmountTree(tester);
  });

  testWidgets('all-records edit mode shows checkboxes and batch bar', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    await seedReadyCaptureForFilterTest(
      database,
      id: 'capture-a',
      projectId: 'project-1',
      capturedAt: DateTime(2026, 7, 16, 9),
    );

    await tester.pumpWidget(pumpAllCaptures(database));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsWidgets);
    expect(find.byKey(const Key('batch-action-bar')), findsNothing);

    await tester.tap(find.byKey(const Key('select-all-captures')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
    await unmountTree(tester);
  });

  testWidgets('select-all button toggles eligible rows and skips busy rows', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    await seedReadyCaptureForFilterTest(
      database,
      id: 'capture-ready',
      projectId: 'project-1',
      capturedAt: DateTime(2026, 7, 16, 9),
    );
    final busy = await database.createPendingCapture(
      id: 'capture-busy',
      projectId: 'project-1',
      originalPath: '/private/capture-busy.jpg',
      workLocation: 'B 区',
      workContent: '检查',
      photographer: '李工',
      watermarkLocaleCode: 'zh',
      createdAt: DateTime(2026, 7, 16, 10),
    );
    await database.markCaptured(
      captureId: busy.id,
      capturedAt: DateTime(2026, 7, 16, 10),
    );

    await tester.pumpWidget(pumpAllCaptures(database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('select-all-captures')));
    await tester.pumpAndSettle();
    final firstValues = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .map((checkbox) => checkbox.value)
        .toList();
    expect(firstValues.where((value) => value == true), hasLength(1));
    expect(find.byTooltip('取消全选'), findsOneWidget);

    await tester.tap(find.byKey(const Key('select-all-captures')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((checkbox) => checkbox.value == false),
      isTrue,
    );
    expect(find.byTooltip('全选'), findsOneWidget);
    await unmountTree(tester);
  });

  testWidgets('all-records changing date filter clears selection', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    await seedReadyCaptureForFilterTest(
      database,
      id: 'capture-a',
      projectId: 'project-1',
      capturedAt: DateTime(2026, 7, 16, 9),
    );

    await tester.pumpWidget(pumpAllCaptures(database));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('select-all-captures')));
    await tester.pumpAndSettle();

    bool anyChecked() => tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .any((cb) => cb.value == true);
    expect(anyChecked(), isTrue);

    await tester.tap(find.byKey(const Key('filter-year')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '2026'));
    await tester.pumpAndSettle();

    expect(anyChecked(), isFalse);
    await unmountTree(tester);
  });

  testWidgets('all-records batch bar fits at 360dp', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    await seedReadyCaptureForFilterTest(
      database,
      id: 'capture-a',
      projectId: 'project-1',
      capturedAt: DateTime(2026, 7, 16, 9),
    );

    await tester.pumpWidget(pumpAllCaptures(database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('select-all-captures')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountTree(tester);
  });

  testWidgets('project detail edit mode shows checkboxes and batch bar', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    await seedReadyCaptureForFilterTest(
      database,
      id: 'capture-a',
      projectId: 'project-1',
      capturedAt: DateTime(2026, 7, 16, 9),
    );

    await tester.pumpWidget(pumpProjectDetail(database, 'project-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsWidgets);
    expect(find.byKey(const Key('batch-action-bar')), findsNothing);

    await tester.tap(find.byKey(const Key('select-all-captures')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
    await unmountTree(tester);
  });

  testWidgets('busy record tap is disabled while editing', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final pending = await database.createPendingCapture(
      id: 'capture-busy',
      projectId: 'project-1',
      originalPath: '/private/capture-busy.jpg',
      workLocation: 'A 区',
      workContent: '风管检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    );
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9),
    );

    await tester.pumpWidget(pumpAllCaptures(database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-captures')));
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    await tester.tap(
      find.descendant(
        of: find.byType(CaptureRecordCard),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await unmountTree(tester);
  });
}
