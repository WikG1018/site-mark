import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/domain/project_summary.dart';
import 'package:sitemark/features/projects/project_list_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';

class _TestCaptureOutputPaths implements CaptureOutputPaths {
  _TestCaptureOutputPaths(this.renderedPath);

  final String renderedPath;

  @override
  Future<String> renderedPhotoPath(String captureId) async {
    return renderedPath;
  }
}

class _ControlledProjectsDatabase extends AppDatabase {
  _ControlledProjectsDatabase() : super.forTesting(NativeDatabase.memory());

  final projectEvents = StreamController<List<ProjectSummary>>();

  @override
  Stream<List<ProjectSummary>> watchProjectSummaries({
    ProjectLifecycleStatus? status,
    String search = '',
  }) => projectEvents.stream;

  @override
  Future<void> close() async {
    await projectEvents.close();
    await super.close();
  }
}

void main() {
  late AppDatabase database;

  Future<void> pumpProjects(
    WidgetTester tester, {
    bool settle = true,
    Locale locale = const Locale('zh'),
  }) async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'east', name: '东区厂房改造');
    await database.createProject(id: 'west', name: '西区管线整改');
    await database.createProject(id: 'warehouse', name: 'Warehouse Alpha');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const ProjectListScreen(),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<ProviderContainer> pumpProjectList(
    WidgetTester tester, {
    required int captures,
  }) async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(id: 'recent', name: '最近项目');
    for (var index = 1; index <= captures; index++) {
      final id = 'capture-$index';
      final capturedAt = DateTime.utc(2026, 8, 3, 8, index);
      final pending = await database.createPendingCapture(
        id: id,
        projectId: 'recent',
        originalPath: '/private/$id.jpg',
        workLocation: 'A 区',
        workContent: '检查',
        photographer: '张工',
        watermarkLocaleCode: 'zh',
        createdAt: capturedAt,
      );
      await database.markCaptured(
        captureId: pending.id,
        capturedAt: capturedAt,
      );
      await database.markRendering(
        captureId: pending.id,
        originalSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      await database.markReady(
        captureId: pending.id,
        publishedUri: 'content://media/$id',
      );
    }
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        captureOutputPathsProvider.overrideWithValue(
          _TestCaptureOutputPaths(
            File('assets/branding/sitemark-icon.png').absolute.path,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ProjectListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pumpAndSettle();
    return container;
  }

  // Dispose the widget tree before the test ends so the StreamBuilder cancels
  // its drift stream subscription, preventing a pending-timer failure at
  // teardown (same pattern used by test/widget_test.dart's disposeApp).
  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('home search filters by Chinese project name', (tester) async {
    await pumpProjects(tester);
    await tester.tap(find.byKey(const Key('search-projects')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('project-search-field')), '东区');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('project-card-east')),
        matching: find.text('东区厂房改造'),
      ),
      findsOneWidget,
    );
    expect(find.text('西区管线整改'), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('home no longer exposes the old restore action', (tester) async {
    await pumpProjects(tester);
    expect(find.byKey(const Key('import-project')), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('status filter announces its title and current value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpProjects(tester, locale: const Locale('en'));
    try {
      expect(
        tester.getSemantics(find.byKey(const Key('project-status-filter'))),
        matchesSemantics(
          label: 'Project status: Active',
          isButton: true,
          hasTapAction: true,
        ),
      );
    } finally {
      semantics.dispose();
      await disposeApp(tester);
    }
  });

  testWidgets('project card is one tap target and shows recent thumbnails', (
    tester,
  ) async {
    final container = await pumpProjectList(tester, captures: 3);
    try {
      expect(
        find.byKey(const Key('project-thumbnail-capture-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('project-thumbnail-capture-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('project-thumbnail-capture-1')),
        findsOneWidget,
      );
      expect(find.byType(PopupMenuButton), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(database.close);
    }
  });

  testWidgets(
    'home first frame shows Skeletonizer without real project cards',
    (tester) async {
      database = _ControlledProjectsDatabase();
      addTearDown(database.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: const MaterialApp(
            locale: Locale('zh'),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: ProjectListScreen(),
          ),
        ),
      );

      // Loading state shows a fixed skeleton layout but no real project data.
      expect(find.byKey(const Key('project-list-skeleton')), findsOneWidget);
      expect(find.text('东区厂房改造'), findsNothing);
      expect(find.text('西区管线整改'), findsNothing);
      await disposeApp(tester);
    },
  );

  testWidgets('home search ignores Latin case and clears then exits', (
    tester,
  ) async {
    await pumpProjects(tester);
    await tester.tap(find.byKey(const Key('search-projects')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('project-search-field')),
      'warehouse alpha',
    );
    await tester.pumpAndSettle();
    expect(find.text('Warehouse Alpha'), findsOneWidget);
    expect(find.byKey(const Key('project-search-action')), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.tap(find.byKey(const Key('project-search-action')));
    await tester.pumpAndSettle();
    expect(find.text('东区厂房改造'), findsOneWidget);
    expect(find.text('西区管线整改'), findsOneWidget);
    expect(find.text('Warehouse Alpha'), findsOneWidget);
    expect(find.byKey(const Key('project-search-field')), findsOneWidget);

    await tester.tap(find.byKey(const Key('project-search-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-search-field')), findsNothing);
    expect(find.byKey(const Key('project-title')), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('search no-result state keeps exit available', (tester) async {
    await pumpProjects(tester);
    await tester.tap(find.byKey(const Key('search-projects')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('project-search-field')),
      '不存在',
    );
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的项目'), findsOneWidget);
    expect(find.byKey(const Key('project-search-action')), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('system back closes home search instead of leaving the app', (
    tester,
  ) async {
    await pumpProjects(tester);
    await tester.tap(find.byKey(const Key('search-projects')));
    await tester.pump();
    expect(find.byKey(const Key('project-search-field')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('project-search-field')), findsNothing);
    expect(find.byKey(const Key('project-title')), findsOneWidget);
    expect(find.text('东区厂房改造'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('project title area does not use a switching animation', (
    tester,
  ) async {
    await pumpProjects(tester);
    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.byType(AnimatedSwitcher)),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('search-projects')));
    await tester.pump();
    expect(
      find.descendant(of: appBar, matching: find.byType(AnimatedSwitcher)),
      findsNothing,
    );
    await disposeApp(tester);
  });

  testWidgets('defaults to active and switches lifecycle filters', (
    tester,
  ) async {
    await pumpProjects(tester);
    expect(
      find.byKey(const Key('project-status-badge-active')),
      findsNWidgets(3),
    );
    await database.updateProjectLifecycleStatus(
      projectId: 'west',
      expectedStatus: ProjectLifecycleStatus.active,
      targetStatus: ProjectLifecycleStatus.archived,
    );
    await tester.pumpAndSettle();
    expect(find.text('已归档'), findsNothing);
    expect(find.text('西区管线整改'), findsNothing);

    await tester.tap(find.byKey(const Key('project-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project-status-archived')));
    await tester.pumpAndSettle();
    expect(find.text('西区管线整改'), findsOneWidget);
    expect(find.text('东区厂房改造'), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('search spans statuses and shows status badges', (tester) async {
    await pumpProjects(tester);
    await database.updateProjectLifecycleStatus(
      projectId: 'east',
      expectedStatus: ProjectLifecycleStatus.active,
      targetStatus: ProjectLifecycleStatus.completed,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-projects')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('project-search-field')),
      '东区厂房改造',
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('project-card-east')),
        matching: find.text('东区厂房改造'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('project-status-badge-completed')),
      findsOneWidget,
    );
    await disposeApp(tester);
  });

  testWidgets('status sheet system back only closes the sheet', (tester) async {
    await pumpProjects(tester);
    await tester.tap(find.byKey(const Key('project-status-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-status-active')), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('project-status-active')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('project-status-archived')))
          .selected,
      isFalse,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-status-active')), findsNothing);
    expect(find.byKey(const Key('project-title')), findsOneWidget);
    expect(find.text('东区厂房改造'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('exiting search restores the active-filter scroll position', (
    tester,
  ) async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final base = DateTime(2026, 8, 3, 8);
    for (var index = 0; index < 30; index++) {
      await database.createProject(
        id: 'project-$index',
        name: '项目${index.toString().padLeft(2, '0')}',
        createdAt: base.add(Duration(minutes: index)),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ProjectListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('项目00'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('项目00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-projects')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('project-search-field')),
      '项目29',
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('project-card-project-29')),
        matching: find.text('项目29'),
      ),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-search-field')), findsNothing);
    expect(find.text('项目00'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('narrow width and large text do not overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(
      id: 'long',
      name: '超长项目名称用于验证窄屏和大字体布局是否会溢出',
      isPinned: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const ProjectListScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });

  testWidgets('disableAnimations does not add custom transitions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(
            AppDatabase.forTesting(NativeDatabase.memory()),
          ),
        ],
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const ProjectListScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AnimatedSwitcher), findsNothing);
    await disposeApp(tester);
  });
}
