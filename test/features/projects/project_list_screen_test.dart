import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/projects/project_list_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  late AppDatabase database;

  Future<void> pumpProjects(WidgetTester tester) async {
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
    await tester.pumpAndSettle();
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

  testWidgets('home search ignores Latin case and clears', (tester) async {
    await pumpProjects(tester);
    await tester.tap(find.byKey(const Key('search-projects')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('project-search-field')),
      'warehouse alpha',
    );
    await tester.pump();
    expect(find.text('Warehouse Alpha'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clear-project-search')));
    await tester.pump();
    expect(find.byType(Card), findsNWidgets(3));
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
    expect(find.byKey(const Key('close-project-search')), findsOneWidget);
    await disposeApp(tester);
  });
}
