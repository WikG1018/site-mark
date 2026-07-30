import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/projects/project_list_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

class _ControlledProjectsDatabase extends AppDatabase {
  _ControlledProjectsDatabase() : super.forTesting(NativeDatabase.memory());

  final projectEvents = StreamController<List<Project>>();

  @override
  Stream<List<Project>> watchProjects() => projectEvents.stream;

  @override
  Future<void> close() async {
    await projectEvents.close();
    await super.close();
  }
}

void main() {
  late AppDatabase database;

  Future<void> pumpProjects(WidgetTester tester, {bool settle = true}) async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'east', name: '东区厂房改造');
    await database.createProject(id: 'west', name: '西区管线整改');
    await database.createProject(id: 'warehouse', name: 'Warehouse Alpha');
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
          home: const ProjectListScreen(),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
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
    await tester.pump();
    expect(find.text('东区厂房改造'), findsOneWidget);
    expect(find.text('西区管线整改'), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('home no longer exposes the old restore action', (tester) async {
    await pumpProjects(tester);
    expect(find.byKey(const Key('import-project')), findsNothing);
    await disposeApp(tester);
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
    await tester.pump();
    expect(find.text('Warehouse Alpha'), findsOneWidget);
    expect(find.byKey(const Key('project-search-action')), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.tap(find.byKey(const Key('project-search-action')));
    await tester.pump();
    expect(find.byType(Card), findsNWidgets(3));
    expect(find.byKey(const Key('project-search-field')), findsOneWidget);

    await tester.tap(find.byKey(const Key('project-search-action')));
    await tester.pump();
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
    await tester.pump();
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
}
