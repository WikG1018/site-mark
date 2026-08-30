import 'dart:async';
import 'dart:math' show max, min;
import 'dart:ui' show SemanticsAction;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/features/capture/compact_filter_menu.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/features/capture/all_captures_screen.dart';
import 'package:sitemark/features/capture/capture_active_filter_chips.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/features/projects/project_action_sheet.dart';
import 'package:sitemark/features/projects/project_detail_screen.dart';
import 'package:sitemark/features/settings/sections/project_backup_selection_screen.dart';
import 'package:sitemark/features/capture/capture_date_filter_bar.dart';
import 'package:sitemark/features/capture/capture_filter_sheet.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/project_deletion_service.dart';

Widget filterHarnessLive(ValueNotifier<CaptureFilter> filter) {
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
            options: switch ((value.year, value.month)) {
              (2025, 6) => const CaptureDateOptions(
                years: [2025, 2026],
                months: [6],
                days: [1],
              ),
              (2025, _) => const CaptureDateOptions(
                years: [2025, 2026],
                months: [6],
              ),
              (2026, 7) => const CaptureDateOptions(
                years: [2025, 2026],
                months: [7, 8],
                days: [16, 17],
              ),
              (2026, 8) => const CaptureDateOptions(
                years: [2025, 2026],
                months: [7, 8],
                days: [2],
              ),
              (2026, _) => const CaptureDateOptions(
                years: [2025, 2026],
                months: [7, 8],
              ),
              _ => const CaptureDateOptions(years: [2025, 2026]),
            },
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

  testWidgets('below 360dp the three menus collapse into a filter button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final filter = ValueNotifier(const CaptureFilter());
    await tester.pumpWidget(filterHarnessLive(filter));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('filter-year')), findsNothing);
    expect(find.byKey(const Key('filter-month')), findsNothing);
    expect(find.byKey(const Key('filter-day')), findsNothing);
    expect(find.byKey(const Key('filter-sheet-trigger')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow filter sheet applies the same cascading selections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final filter = ValueNotifier(
      const CaptureFilter(year: 2026, month: 7, day: 16),
    );
    await tester.pumpWidget(filterHarnessLive(filter));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
    await tester.pumpAndSettle();

    // The sheet hosts the year/month/day compact menus, matching the wide bar.
    expect(find.byType(CompactFilterMenu<int?>), findsNWidgets(3));

    // Changing the year resets month and day, matching the wide bar.
    await tester.tap(find.byType(CompactFilterMenu<int?>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '2025'));
    await tester.pumpAndSettle();

    expect(filter.value.year, 2025);
    expect(filter.value.month, isNull);
    expect(filter.value.day, isNull);

    // The month dropdown now only lists months available in 2025.
    await tester.tap(find.byType(CompactFilterMenu<int?>).at(1));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, '6月'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, '7月'), findsNothing);
    await tester.tap(find.widgetWithText(MenuItemButton, '6月'));
    await tester.pumpAndSettle();

    expect(filter.value.year, 2025);
    expect(filter.value.month, 6);
    expect(filter.value.day, isNull);
  });

  testWidgets('filter draft reloads real date options for each parent choice', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-a', name: '甲项目');
    await database.createProject(id: 'project-b', name: '乙项目');

    Future<void> seed({
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

    await seed(
      id: 'capture-a',
      projectId: 'project-a',
      capturedAt: DateTime(2026, 7, 16, 9),
    );
    await seed(
      id: 'capture-b',
      projectId: 'project-b',
      capturedAt: DateTime(2025, 6, 1, 9),
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

    await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-project-project-a')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('filter-year-2026')), findsOneWidget);
    expect(find.byKey(const Key('filter-year-2025')), findsNothing);

    await tester.tap(find.byKey(const Key('filter-year-2026')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('filter-month-7')), findsOneWidget);
    expect(find.byKey(const Key('filter-month-8')), findsNothing);

    await tester.tap(find.byKey(const Key('filter-month-7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('filter-day-16')), findsOneWidget);
    expect(find.byKey(const Key('filter-day-15')), findsNothing);

    await tester.tap(find.byKey(const Key('filter-project-project-b')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('filter-year-2025')), findsOneWidget);
    expect(find.byKey(const Key('filter-year-2026')), findsNothing);

    await tester.tap(find.byKey(const Key('filter-year-2025')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('filter-month-6')), findsOneWidget);
    expect(find.byKey(const Key('filter-month-7')), findsNothing);

    await tester.tap(find.byKey(const Key('filter-month-6')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('filter-day-1')), findsOneWidget);
    expect(find.byKey(const Key('filter-day-2')), findsNothing);

    await tester.tap(find.byKey(const Key('filter-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-filter-project')), findsNothing);
    expect(find.byKey(const Key('active-filter-year')), findsNothing);
    expect(find.byKey(const ValueKey('capture-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-b')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('filter ignores a slower initial response after project switch', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final projectB = await database.createProject(id: 'project-b', name: '乙项目');
    final initialResponse = Completer<CaptureDateOptions>();
    final responseB = Completer<CaptureDateOptions>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: CaptureFilterSheet(
            initial: const CaptureFilter(),
            projects: [projectB],
            options: const CaptureDateOptions(years: [2024]),
            optionsLoader: (draft) => switch (draft.projectId) {
              'project-b' => responseB.future,
              _ => initialResponse.future,
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('filter-year-2024')), findsNothing);

    await tester.tap(find.byKey(const Key('filter-project-project-b')));
    await tester.pump();
    responseB.complete(const CaptureDateOptions(years: [2025]));
    await tester.pump();
    expect(find.byKey(const Key('filter-year-2025')), findsOneWidget);

    initialResponse.complete(const CaptureDateOptions(years: [2026]));
    await tester.pump();
    expect(find.byKey(const Key('filter-year-2025')), findsOneWidget);
    expect(find.byKey(const Key('filter-year-2026')), findsNothing);
  });

  testWidgets(
    'initial filter option loader failure clears stale choices safely',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final project = await database.createProject(
        id: 'project-b',
        name: '乙项目',
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: CaptureFilterSheet(
              initial: const CaptureFilter(),
              projects: [project],
              options: const CaptureDateOptions(years: [2026]),
              optionsLoader: (_) => Future<CaptureDateOptions>.error(
                StateError('date options failed'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('filter-year-2026')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'initial filter option loader completion after dispose is ignored',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final project = await database.createProject(
        id: 'project-a',
        name: '甲项目',
      );
      final response = Completer<CaptureDateOptions>();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: CaptureFilterSheet(
              initial: const CaptureFilter(),
              projects: [project],
              options: const CaptureDateOptions(years: [2026]),
              optionsLoader: (_) => response.future,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      response.complete(const CaptureDateOptions(years: [2025]));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reopening after apply never shows date options from the previous query',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'project-a', name: '甲项目');
      final parentRefresh = Completer<CaptureDateOptions>();
      final reopenedSheetRefresh = Completer<CaptureDateOptions>();
      var projectACalls = 0;
      final source = _DateOptionsQuerySource((query) {
        if (query.filter.projectId == null) {
          return Future.value(const CaptureDateOptions(years: [2025]));
        }
        projectACalls++;
        return switch (projectACalls) {
          1 => Future.value(const CaptureDateOptions(years: [2026])),
          2 => parentRefresh.future,
          3 => reopenedSheetRefresh.future,
          _ => Future.value(const CaptureDateOptions(years: [2026])),
        };
      });

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
            home: AllCapturesScreen(querySource: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-project-project-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('filter-year-2026')), findsOneWidget);

      await tester.tap(find.byKey(const Key('filter-apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('filter-year-2025')), findsNothing);
      expect(find.byKey(const Key('filter-year-2026')), findsNothing);
      expect(projectACalls, 3);

      reopenedSheetRefresh.complete(const CaptureDateOptions(years: [2026]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('filter-year-2026')), findsOneWidget);
      expect(find.byKey(const Key('filter-year-2025')), findsNothing);

      parentRefresh.complete(const CaptureDateOptions(years: [2026]));
      await tester.pump();
      await tester.tap(find.byKey(const Key('filter-cancel')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('filter keeps a selected date missing from current records', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: CaptureFilterSheet(
            initial: const CaptureFilter(year: 2026, month: 7, day: 16),
            projects: const [],
            options: const CaptureDateOptions(),
            optionsLoader: (_) async => const CaptureDateOptions(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('filter-year-2026')), findsOneWidget);
    expect(find.byKey(const Key('filter-month-7')), findsOneWidget);
    expect(find.byKey(const Key('filter-day-16')), findsOneWidget);
  });

  testWidgets('active chips label deleted projects and fit at 360dp', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final filter = ValueNotifier(
      const CaptureFilter(
        projectId: 'deleted-project',
        year: 2026,
        month: 8,
        day: 4,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
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
            builder: (context, value, _) => CaptureActiveFilterChips(
              filter: value,
              projects: const [],
              onChanged: (next) => filter.value = next,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已删除项目'), findsOneWidget);
    expect(find.text('8月'), findsOneWidget);
    expect(find.text('4日'), findsOneWidget);
    expect(find.byKey(const Key('active-filter-project')), findsOneWidget);
    expect(find.byKey(const Key('active-filter-year')), findsOneWidget);
    expect(find.byKey(const Key('active-filter-month')), findsOneWidget);
    expect(find.byKey(const Key('active-filter-day')), findsOneWidget);
    expect(
      tester
          .widget<InputChip>(find.byKey(const Key('active-filter-project')))
          .deleteButtonTooltipMessage,
      '移除项目筛选',
    );
    expect(
      tester
          .widget<InputChip>(find.byKey(const Key('active-filter-year')))
          .deleteButtonTooltipMessage,
      '移除年份筛选',
    );
    expect(
      tester
          .widget<InputChip>(find.byKey(const Key('active-filter-month')))
          .deleteButtonTooltipMessage,
      '移除月份筛选',
    );
    expect(
      tester
          .widget<InputChip>(find.byKey(const Key('active-filter-day')))
          .deleteButtonTooltipMessage,
      '移除日期筛选',
    );
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const Key('active-filter-chips')),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-filter-day')));
    await tester.pump();
    expect(filter.value.projectId, 'deleted-project');
    expect(filter.value.year, 2026);
    expect(filter.value.month, 8);
    expect(filter.value.day, isNull);
  });

  testWidgets(
    'English active chips name month and day with distinct delete semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: CaptureActiveFilterChips(
              filter: const CaptureFilter(
                projectId: 'deleted-project',
                year: 2026,
                month: 8,
                day: 4,
              ),
              projects: const [],
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Month 8'), findsOneWidget);
      expect(find.text('Day 4'), findsOneWidget);
      const expectations = <String, String>{
        'project': 'Remove project filter',
        'year': 'Remove year filter',
        'month': 'Remove month filter',
        'day': 'Remove day filter',
      };
      for (final entry in expectations.entries) {
        final chip = find.byKey(Key('active-filter-${entry.key}'));
        expect(
          tester.widget<InputChip>(chip).deleteButtonTooltipMessage,
          entry.value,
        );
      }

      final monthSemantics = tester
          .getSemantics(find.byKey(const Key('active-filter-month')))
          .label;
      final daySemantics = tester
          .getSemantics(find.byKey(const Key('active-filter-day')))
          .label;
      expect(RegExp('Month 8').allMatches(monthSemantics).length, 1);
      expect(RegExp('Day 4').allMatches(daySemantics).length, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

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

      await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-year-2026')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('filter-apply')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('active-filter-year')), findsOneWidget);

      await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-project-project-2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('filter-apply')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('active-filter-project')), findsOneWidget);
      expect(find.text('西区管线整改'), findsOneWidget);
      expect(find.byKey(const Key('active-filter-year')), findsNothing);
      expect(find.byKey(const Key('active-filter-month')), findsNothing);
      expect(find.byKey(const Key('active-filter-day')), findsNothing);

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

    await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-project-project-b')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-apply')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('filter-year-2026')), findsOneWidget);
    expect(find.byKey(const Key('filter-year-2025')), findsNothing);

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
    'filter controls are 48dp rounded rectangles with centered text',
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

      expect(tester.getSize(menuFinder).height, 48);
      expect(shape, isA<RoundedRectangleBorder>());
      final border = shape! as RoundedRectangleBorder;
      expect(border.borderRadius, BorderRadius.circular(10));
      expect(
        (tester.getCenter(buttonFinder).dx -
                tester.getCenter(find.text('全部年份')).dx)
            .abs(),
        lessThan(1),
      );
      expect(
        find.descendant(
          of: menuFinder,
          matching: find.byIcon(Icons.arrow_drop_down),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('filter menu animates and highlights the current option', (
    tester,
  ) async {
    final filter = ValueNotifier(const CaptureFilter(year: 2026));
    await tester.pumpWidget(filterHarnessLive(filter));
    await tester.pumpAndSettle();

    final menuFinder = find.byKey(const Key('filter-year'));
    final anchor = tester.widget<MenuAnchor>(
      find.descendant(of: menuFinder, matching: find.byType(MenuAnchor)),
    );
    final menuShape = anchor.style?.shape?.resolve(<WidgetState>{});

    expect(anchor.animated, isTrue);
    expect(anchor.alignmentOffset, const Offset(0, 6));
    expect(menuShape, isA<RoundedRectangleBorder>());
    expect(
      (menuShape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(14),
    );

    await tester.tap(menuFinder);
    await tester.pumpAndSettle();

    final selectedItem = tester.widget<MenuItemButton>(
      find.widgetWithText(MenuItemButton, '2026'),
    );
    final colorScheme = Theme.of(tester.element(menuFinder)).colorScheme;
    expect(
      selectedItem.leadingIcon,
      isA<Icon>().having((widget) => widget.icon, 'icon', Icons.check_rounded),
    );
    expect(
      selectedItem.style?.backgroundColor?.resolve(<WidgetState>{}),
      colorScheme.primaryContainer,
    );
  });

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

    expect(find.byKey(const Key('filter-sheet-trigger')), findsOneWidget);
    expect(find.byKey(const Key('project-filter')), findsNothing);
    expect(find.byKey(const Key('filter-year')), findsNothing);

    await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-project-project-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-apply')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('active-filter-chips')), findsOneWidget);
    expect(find.byKey(const Key('active-filter-project')), findsOneWidget);
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

  Widget pumpProjectDetail(
    AppDatabase database,
    String projectId, {
    ProjectDeletionService? deletionService,
    Locale locale = const Locale('zh'),
    bool withRouter = false,
  }) {
    final overrides = [
      databaseProvider.overrideWithValue(database),
      if (deletionService != null)
        projectDeletionServiceProvider.overrideWithValue(deletionService),
    ];
    if (withRouter) {
      final router = GoRouter(
        initialLocation: '/projects/$projectId',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: SizedBox(key: Key('project-list-root'))),
            routes: [
              GoRoute(
                path: 'projects/:projectId',
                builder: (_, state) => ProjectDetailScreen(
                  projectId: state.pathParameters['projectId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/settings/backup-restore/backup',
            builder: (_, state) {
              final arguments = state.extra as ProjectBackupSelectionArguments;
              return Scaffold(
                body: Column(
                  children: [
                    for (final projectId in arguments.initialProjectIds)
                      SizedBox(key: Key('backup-initial-$projectId')),
                  ],
                ),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      return ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          locale: locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      );
    }
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
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

  Widget pumpSwitchableProjectDetail(
    AppDatabase database,
    ValueNotifier<String> projectId,
  ) {
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
        home: ValueListenableBuilder<String>(
          valueListenable: projectId,
          builder: (_, value, _) => ProjectDetailScreen(projectId: value),
        ),
      ),
    );
  }

  Widget pumpSwitchableProjectDetailWithRouter(
    AppDatabase database,
    ValueNotifier<String> projectId,
  ) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => ValueListenableBuilder<String>(
            valueListenable: projectId,
            builder: (_, value, _) => ProjectDetailScreen(projectId: value),
          ),
        ),
        GoRoute(
          path: '/settings/backup-restore/backup',
          builder: (_, _) => const Scaffold(
            body: SizedBox(key: Key('stale-backup-destination')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp.router(
        locale: const Locale('zh'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
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

  testWidgets('all records shows current date beside the filter trigger', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    await seedReadyCaptureForFilterTest(
      database,
      id: 'capture-a',
      projectId: 'project-1',
      capturedAt: DateTime(2026, 8, 4, 9),
    );
    await seedReadyCaptureForFilterTest(
      database,
      id: 'capture-b',
      projectId: 'project-1',
      capturedAt: DateTime(2026, 8, 4, 8),
    );
    await seedReadyCaptureForFilterTest(
      database,
      id: 'capture-c',
      projectId: 'project-1',
      capturedAt: DateTime(2026, 8, 3, 18),
    );

    await tester.pumpWidget(pumpAllCaptures(database));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('filter-sheet-trigger')), findsOneWidget);
    expect(find.byKey(const Key('project-filter')), findsNothing);
    expect(find.byKey(const Key('filter-year')), findsNothing);
    expect(find.byKey(const Key('visible-capture-date')), findsOneWidget);
    expect(find.text('2026-08-04'), findsOneWidget);
    expect(find.byType(SliverPersistentHeader), findsNothing);
    final filterRect = tester.getRect(
      find.byKey(const Key('filter-sheet-trigger')),
    );
    final dateRect = tester.getRect(
      find.byKey(const Key('visible-capture-date')),
    );
    expect(dateRect.left, greaterThan(filterRect.right));
    expect((dateRect.center.dy - filterRect.center.dy).abs(), lessThan(2));
    await unmountTree(tester);
  });

  testWidgets('all records hides the visible date when there are no rows', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '空项目');

    await tester.pumpWidget(pumpAllCaptures(database));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('visible-capture-date')), findsNothing);
    expect(find.byKey(const Key('filter-sheet-trigger')), findsOneWidget);
    await unmountTree(tester);
  });

  testWidgets('filter sheet keeps a draft and chips remove independently', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    await database.createProject(id: 'project-2', name: '西区管线整改');
    await seedReadyCaptureForFilterTest(
      database,
      id: 'capture-a',
      projectId: 'project-1',
      capturedAt: DateTime(2026, 8, 4, 9),
    );
    await seedReadyCaptureForFilterTest(
      database,
      id: 'capture-b',
      projectId: 'project-2',
      capturedAt: DateTime(2026, 8, 3, 9),
    );

    await tester.pumpWidget(pumpAllCaptures(database));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-project-project-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-year-2026')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-month-8')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-day-4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('active-filter-project')), findsNothing);
    expect(find.byKey(const Key('active-filter-year')), findsNothing);
    expect(find.byKey(const Key('capture-a')), findsOneWidget);
    expect(find.byKey(const Key('capture-b')), findsOneWidget);

    await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-project-project-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-year-2026')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-month-8')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-day-4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-apply')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('active-filter-project')), findsOneWidget);
    expect(find.byKey(const Key('active-filter-year')), findsOneWidget);
    expect(find.byKey(const Key('active-filter-month')), findsOneWidget);
    expect(find.byKey(const Key('active-filter-day')), findsOneWidget);
    expect(find.byKey(const Key('visible-capture-date')), findsOneWidget);
    expect(find.text('2026-08-04'), findsOneWidget);
    expect(find.byKey(const Key('capture-a')), findsOneWidget);
    expect(find.byKey(const Key('capture-b')), findsNothing);

    await tester.tap(find.byKey(const Key('remove-filter-month')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-filter-month')), findsNothing);
    expect(find.byKey(const Key('active-filter-day')), findsNothing);
    expect(find.byKey(const Key('active-filter-project')), findsOneWidget);
    expect(find.byKey(const Key('active-filter-year')), findsOneWidget);

    await tester.tap(find.byKey(const Key('remove-filter-project')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-filter-project')), findsNothing);
    expect(find.byKey(const Key('active-filter-year')), findsOneWidget);
    expect(find.byKey(const Key('capture-b')), findsOneWidget);
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
    expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
    expect(find.text('已选 0 张'), findsOneWidget);

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

    await tester.tap(find.byKey(const Key('filter-sheet-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-year-2026')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-apply')));
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
    expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
    expect(find.text('已选 0 张'), findsOneWidget);

    await tester.tap(find.byKey(const Key('select-all-captures')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('batch-action-bar')), findsOneWidget);
    await unmountTree(tester);
  });

  testWidgets(
    'project detail uses one compact action sheet and preselects only itself for backup',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'project-1', name: '东区项目');
      await database.createProject(id: 'project-2', name: '西区项目');
      await seedReadyCaptureForFilterTest(
        database,
        id: 'capture-a',
        projectId: 'project-1',
        capturedAt: DateTime(2026, 7, 16, 9),
      );

      await tester.pumpWidget(
        pumpProjectDetail(database, 'project-1', withRouter: true),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('此项目水印设置'), findsNothing);
      expect(find.byTooltip('备份项目'), findsNothing);
      expect(find.byKey(const Key('project-watermark-action')), findsNothing);
      expect(find.byKey(const Key('project-backup-action')), findsNothing);
      expect(find.byKey(const Key('project-actions')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byKey(const Key('edit-captures')),
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('edit-captures')), findsOneWidget);
      expect(find.byKey(const Key('project-summary')), findsOneWidget);
      expect(find.text('1 张照片'), findsOneWidget);

      await tester.tap(find.byKey(const Key('project-actions')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('project-action-sheet')), findsOneWidget);
      expect(find.text('此项目水印设置'), findsOneWidget);
      expect(find.text('备份项目'), findsOneWidget);
      expect(find.text('重命名项目'), findsOneWidget);
      expect(find.byKey(const Key('pin-project')), findsOneWidget);
      expect(find.byKey(const Key('complete-project')), findsOneWidget);
      expect(find.byKey(const Key('archive-project')), findsOneWidget);
      expect(find.byKey(const Key('reopen-project')), findsNothing);

      final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(bottomSheet.showDragHandle, isTrue);
      expect(
        find.ancestor(
          of: find.byKey(const Key('project-action-sheet')),
          matching: find.byType(SafeArea),
        ),
        findsWidgets,
      );
      final deleteIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('delete-project')),
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      expect(
        deleteIcon.color,
        Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.error,
      );

      await tester.tap(find.byKey(const Key('project-backup-action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backup-initial-project-1')), findsOneWidget);
      expect(find.byKey(const Key('backup-initial-project-2')), findsNothing);
      await unmountTree(tester);
    },
  );

  testWidgets('project action sheet follows lifecycle and pin state', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'active', name: '进行中');
    await database.createProject(
      id: 'completed',
      name: '已完成',
      lifecycleStatus: ProjectLifecycleStatus.completed,
      isPinned: true,
    );
    await database.createProject(
      id: 'archived',
      name: '已归档',
      lifecycleStatus: ProjectLifecycleStatus.archived,
    );

    Future<void> expectActions(
      String projectId, {
      required List<Key> present,
      required List<Key> absent,
    }) async {
      await tester.pumpWidget(pumpProjectDetail(database, projectId));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reopen-project')), findsNothing);
      await tester.tap(find.byKey(const Key('project-actions')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const Key('project-action-sheet'));
      for (final key in present) {
        expect(
          find.descendant(of: sheet, matching: find.byKey(key)),
          findsOneWidget,
        );
      }
      for (final key in absent) {
        expect(
          find.descendant(of: sheet, matching: find.byKey(key)),
          findsNothing,
        );
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    await expectActions(
      'active',
      present: const [
        Key('pin-project'),
        Key('complete-project'),
        Key('archive-project'),
      ],
      absent: const [Key('unpin-project'), Key('reopen-project')],
    );
    await expectActions(
      'completed',
      present: const [
        Key('unpin-project'),
        Key('reopen-project'),
        Key('archive-project'),
      ],
      absent: const [Key('pin-project'), Key('complete-project')],
    );
    await expectActions(
      'archived',
      present: const [Key('pin-project'), Key('reopen-project')],
      absent: const [
        Key('unpin-project'),
        Key('complete-project'),
        Key('archive-project'),
      ],
    );
    await unmountTree(tester);
  });

  testWidgets('stale action sheet cannot pin a project after detail switches', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-a', name: '项目 A');
    await database.createProject(id: 'project-b', name: '项目 B');
    final projectId = ValueNotifier('project-a');
    addTearDown(projectId.dispose);

    await tester.pumpWidget(pumpSwitchableProjectDetail(database, projectId));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project-actions')));
    await tester.pumpAndSettle();

    projectId.value = 'project-b';
    await tester.pumpAndSettle();
    expect(find.text('项目 B'), findsWidgets);
    expect(find.byKey(const Key('project-action-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('pin-project')));
    await tester.pumpAndSettle();

    expect((await database.projectById('project-a'))?.isPinned, isFalse);
    expect((await database.projectById('project-b'))?.isPinned, isFalse);
    await unmountTree(tester);
  });

  testWidgets(
    'stale action sheet cannot navigate to backup after detail switches',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'project-a', name: '项目 A');
      await database.createProject(id: 'project-b', name: '项目 B');
      final projectId = ValueNotifier('project-a');
      addTearDown(projectId.dispose);

      await tester.pumpWidget(
        pumpSwitchableProjectDetailWithRouter(database, projectId),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-actions')));
      await tester.pumpAndSettle();

      projectId.value = 'project-b';
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-backup-action')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stale-backup-destination')), findsNothing);
      expect(find.text('项目 B'), findsWidgets);
      await unmountTree(tester);
    },
  );

  testWidgets('action sheet uses the latest project when rename is selected', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '旧名称');

    await tester.pumpWidget(pumpProjectDetail(database, 'project-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project-actions')));
    await tester.pumpAndSettle();

    await database.renameProject(projectId: 'project-1', name: '外部更新名称');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rename-project')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      find.byKey(const Key('rename-project-name')),
    );
    expect(field.controller?.text, '外部更新名称');
    await unmountTree(tester);
  });

  testWidgets(
    'stale lifecycle action is rejected after external state change',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'project-1', name: '项目');

      await tester.pumpWidget(pumpProjectDetail(database, 'project-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-actions')));
      await tester.pumpAndSettle();

      await database.updateProjectLifecycleStatus(
        projectId: 'project-1',
        expectedStatus: ProjectLifecycleStatus.active,
        targetStatus: ProjectLifecycleStatus.archived,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complete-project')));
      await tester.pumpAndSettle();

      expect(
        (await database.projectById('project-1'))?.lifecycleStatus,
        ProjectLifecycleStatus.archived,
      );
      expect(find.text('项目状态已变化，请重试'), findsNothing);
      await unmountTree(tester);
    },
  );

  testWidgets('project actions apply pin, unpin, complete, and archive', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'pin', name: '置顶目标');
    await database.createProject(id: 'unpin', name: '取消置顶目标', isPinned: true);
    await database.createProject(id: 'complete', name: '完成目标');
    await database.createProject(id: 'archive', name: '归档目标');

    Future<void> selectAction(String projectId, Key actionKey) async {
      await tester.pumpWidget(pumpProjectDetail(database, projectId));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(actionKey));
      await tester.pumpAndSettle();
    }

    await selectAction('pin', const Key('pin-project'));
    expect((await database.projectById('pin'))?.isPinned, isTrue);

    await selectAction('unpin', const Key('unpin-project'));
    expect((await database.projectById('unpin'))?.isPinned, isFalse);

    await selectAction('complete', const Key('complete-project'));
    expect(
      (await database.projectById('complete'))?.lifecycleStatus,
      ProjectLifecycleStatus.completed,
    );

    await selectAction('archive', const Key('archive-project'));
    expect(
      (await database.projectById('archive'))?.lifecycleStatus,
      ProjectLifecycleStatus.archived,
    );
    await unmountTree(tester);
  });

  testWidgets(
    'project action sheet remains scrollable and semantic at 360dp with 3x text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final project = await database.createProject(id: 'project-1', name: '项目');
      final semantics = tester.ensureSemantics();
      try {
        for (final (locale, deleteLabel) in const [
          (Locale('zh'), '删除项目'),
          (Locale('en'), 'Delete project'),
        ]) {
          ProjectAction? selected;
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              supportedLocales: AppStrings.supportedLocales,
              localizationsDelegates: const [
                AppStrings.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(3)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: FilledButton(
                    key: const Key('open-project-actions'),
                    onPressed: () async {
                      selected = await showProjectActionSheet(context, project);
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byKey(const Key('open-project-actions')));
          await tester.pumpAndSettle();

          final sheet = find.byKey(const Key('project-action-sheet'));
          final scrollable = find.descendant(
            of: sheet,
            matching: find.byType(Scrollable),
          );
          await tester.scrollUntilVisible(
            find.byKey(const Key('delete-project')),
            160,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final deleteRow = find.byKey(const Key('delete-project'));
          expect(tester.getSemantics(deleteRow).label, deleteLabel);
          expect(
            tester
                .getSemantics(deleteRow)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );
          final deleteIcon = tester.widget<Icon>(
            find.descendant(
              of: deleteRow,
              matching: find.byIcon(Icons.delete_outline),
            ),
          );
          expect(
            deleteIcon.color,
            Theme.of(tester.element(deleteRow)).colorScheme.error,
          );

          await tester.tap(deleteRow);
          await tester.pumpAndSettle();
          expect(selected, ProjectAction.delete);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'project actions rename while preserving historical capture evidence',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'project-1', name: '旧项目');
      await seedReadyCaptureForFilterTest(
        database,
        id: 'capture-a',
        projectId: 'project-1',
        capturedAt: DateTime(2026, 7, 16, 9),
      );
      final before = await database.captureById('capture-a');

      await tester.pumpWidget(pumpProjectDetail(database, 'project-1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('project-actions')), findsOneWidget);
      await tester.tap(find.byKey(const Key('project-actions')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rename-project')), findsOneWidget);
      expect(find.byKey(const Key('delete-project')), findsOneWidget);
      await tester.tap(find.byKey(const Key('rename-project')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.byKey(const Key('rename-project-name')),
      );
      expect(field.controller?.text, '旧项目');
      await tester.enterText(
        find.byKey(const Key('rename-project-name')),
        '新项目',
      );
      await tester.tap(find.byKey(const Key('confirm-rename-project')));
      await tester.pumpAndSettle();

      expect(find.text('新项目'), findsWidgets);
      expect((await database.projectById('project-1'))?.name, '新项目');
      final after = await database.captureById('capture-a');
      expect(after?.photoNumber, before?.photoNumber);
      expect(after?.originalPath, before?.originalPath);
      expect(after?.originalSha256, before?.originalSha256);
      await unmountTree(tester);
    },
  );

  testWidgets('rename keeps dialog open for invalid and conflicting names', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '旧项目');
    await database.createProject(id: 'project-2', name: 'Cloud Site');
    await database.createProject(id: 'project-3', name: 'A/B');

    await tester.pumpWidget(pumpProjectDetail(database, 'project-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rename-project')));
    await tester.pumpAndSettle();

    Future<void> submit(String name) async {
      await tester.enterText(
        find.byKey(const Key('rename-project-name')),
        name,
      );
      await tester.tap(find.byKey(const Key('confirm-rename-project')));
      await tester.pumpAndSettle();
    }

    await submit(' ');
    expect(find.text('请输入项目名称'), findsOneWidget);
    expect(find.byKey(const Key('rename-project-name')), findsOneWidget);

    await submit(' cloud   site ');
    expect(find.text('已存在同名项目'), findsOneWidget);
    expect(find.byKey(const Key('rename-project-name')), findsOneWidget);

    await submit('A?B');
    expect(find.text('项目名称生成的文件名与已有项目重复'), findsOneWidget);
    expect(find.byKey(const Key('rename-project-name')), findsOneWidget);
    await unmountTree(tester);
  });

  testWidgets(
    'clean delete shows one English retained-assets notice after routing home',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'project-1', name: '东区项目');
      final deleteGate = Completer<void>();
      final service = _FakeProjectDeletionService(
        database: database,
        previewResult: const ProjectDeletionPreview(
          projectName: '东区项目',
          captureCount: 12,
          privateOriginalCount: 7,
        ),
        deleteResult: const ProjectDeletionResult(cleanupPending: false),
        deleteGate: deleteGate,
      );

      await tester.pumpWidget(
        pumpProjectDetail(
          database,
          'project-1',
          deletionService: service,
          locale: const Locale('en'),
          withRouter: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-project')));
      await tester.pumpAndSettle();

      expect(find.textContaining('东区项目'), findsWidgets);
      expect(find.textContaining('12'), findsOneWidget);
      expect(find.textContaining('7'), findsOneWidget);
      expect(find.textContaining('system gallery'), findsOneWidget);
      expect(find.textContaining('exported backups'), findsOneWidget);
      expect(find.textContaining('also delete'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);

      await tester.tap(find.byKey(const Key('confirm-delete-project')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirm-delete-project')));
      deleteGate.complete();
      await tester.pumpAndSettle();

      expect(service.deleteCalls, 1);
      expect(find.byKey(const Key('project-list-root')), findsOneWidget);
      expect(
        find.text(
          'Project deleted. Photos in the system gallery and exported '
          'backups were retained.',
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('next time the app starts'), findsNothing);
      await unmountTree(tester);
    },
  );

  testWidgets('delete cleanup pending notice survives root navigation', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区项目');
    final service = _FakeProjectDeletionService(
      database: database,
      previewResult: const ProjectDeletionPreview(
        projectName: '东区项目',
        captureCount: 1,
        privateOriginalCount: 1,
      ),
      deleteResult: const ProjectDeletionResult(cleanupPending: true),
    );
    await tester.pumpWidget(
      pumpProjectDetail(
        database,
        'project-1',
        deletionService: service,
        withRouter: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('project-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-project')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-project')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('project-list-root')), findsOneWidget);
    expect(find.textContaining('下次启动继续清理'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('系统相册'), findsOneWidget);
    await unmountTree(tester);
  });

  testWidgets('delete failure stays on project and back cancels one layer', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区项目');
    final service = _FakeProjectDeletionService(
      database: database,
      previewResult: const ProjectDeletionPreview(
        projectName: '东区项目',
        captureCount: 1,
        privateOriginalCount: 1,
      ),
      deleteError: StateError('sensitive raw failure'),
    );
    await tester.pumpWidget(
      pumpProjectDetail(
        database,
        'project-1',
        deletionService: service,
        withRouter: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('project-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-project')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-actions')), findsOneWidget);
    expect(find.byKey(const Key('project-list-root')), findsNothing);

    await tester.tap(find.byKey(const Key('project-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-project')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-project')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('project-actions')), findsOneWidget);
    expect(find.text('项目删除失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('sensitive raw failure'), findsNothing);
    await unmountTree(tester);
  });

  testWidgets('project action dialogs fit at 360dp and expose English labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: 'East Plant');
    final service = _FakeProjectDeletionService(
      database: database,
      previewResult: const ProjectDeletionPreview(
        projectName: 'East Plant',
        captureCount: 999,
        privateOriginalCount: 999,
      ),
    );
    await tester.pumpWidget(
      pumpProjectDetail(
        database,
        'project-1',
        deletionService: service,
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Project actions'), findsOneWidget);
    await tester.tap(find.byKey(const Key('project-actions')));
    await tester.pumpAndSettle();
    expect(find.text('Rename project'), findsOneWidget);
    expect(find.text('Delete project'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-project')));
    await tester.pumpAndSettle();
    expect(find.textContaining('system gallery'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

final class _DateOptionsQuerySource implements CaptureQuerySource {
  _DateOptionsQuerySource(this._loadOptions);

  final Future<CaptureDateOptions> Function(CaptureListQuery query)
  _loadOptions;

  @override
  Future<CapturePage> loadPage(
    CaptureListQuery query, {
    CapturePageCursor? after,
    int limit = 50,
  }) async => const CapturePage(rows: [], nextCursor: null, hasMore: false);

  @override
  Future<int> count(CaptureListQuery query) async => 0;

  @override
  Future<CaptureDateOptions> loadDateOptions(CaptureListQuery query) =>
      _loadOptions(query);

  @override
  Future<CaptureSelectionSnapshot> loadSelectable(
    CaptureListQuery query,
  ) async => const CaptureSelectionSnapshot(ids: {}, allReady: false);

  @override
  Future<CaptureSelectionSnapshot> inspectSelection(Set<String> ids) async =>
      CaptureSelectionSnapshot(ids: ids, allReady: ids.isNotEmpty);

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

class _FakeProjectDeletionService extends ProjectDeletionService {
  _FakeProjectDeletionService({
    required super.database,
    required this.previewResult,
    this.deleteResult = const ProjectDeletionResult(cleanupPending: false),
    this.deleteError,
    this.deleteGate,
  }) : super(
         capturePaths: _UnusedCapturePaths(),
         files: _UnusedPrivateFiles(),
         pendingStore: _UnusedPendingStore(),
       );

  final ProjectDeletionPreview previewResult;
  final ProjectDeletionResult deleteResult;
  final Object? deleteError;
  final Completer<void>? deleteGate;
  int deleteCalls = 0;

  @override
  Future<ProjectDeletionPreview> preview(String projectId) async =>
      previewResult;

  @override
  Future<ProjectDeletionResult> deleteProject(String projectId) async {
    deleteCalls++;
    await deleteGate?.future;
    if (deleteError != null) throw deleteError!;
    return deleteResult;
  }
}

class _UnusedCapturePaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) =>
      throw UnimplementedError();
}

class _UnusedPrivateFiles implements PrivateFileStore {
  @override
  Future<void> deleteIfExists(String path) => throw UnimplementedError();

  @override
  Future<bool> exists(String path) => throw UnimplementedError();
}

class _UnusedPendingStore implements ProjectDeletionPendingStore {
  @override
  Future<void> clear(String projectId) => throw UnimplementedError();

  @override
  Future<List<PendingProjectDeletion>> list() => throw UnimplementedError();

  @override
  Future<void> write(PendingProjectDeletion pending) =>
      throw UnimplementedError();
}
