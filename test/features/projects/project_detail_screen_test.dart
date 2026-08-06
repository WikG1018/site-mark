import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/features/projects/project_detail_screen.dart';
import 'package:sitemark/features/settings/sections/project_backup_selection_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/project_deletion_service.dart';

class _FakeCaptureOutputPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _RecordingPrivateFileStore implements PrivateFileStore {
  @override
  Future<void> deleteIfExists(String path) async {}

  @override
  Future<bool> exists(String path) async => true;
}

class _MemoryProjectDeletionPendingStore
    implements ProjectDeletionPendingStore {
  final pending = <PendingProjectDeletion>[];

  @override
  Future<void> clear(String projectId) async {
    pending.removeWhere((entry) => entry.projectId == projectId);
  }

  @override
  Future<List<PendingProjectDeletion>> list() async => List.of(pending);

  @override
  Future<void> write(PendingProjectDeletion item) async {
    pending.add(item);
  }
}

void main() {
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Drift/conditional polling and SnackBar timers.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpUi(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    required AppDatabase database,
    required String projectId,
    ProjectDeletionService? deletions,
    void Function(String location)? onRoute,
  }) async {
    final router = GoRouter(
      initialLocation: '/projects/$projectId',
      routes: [
        GoRoute(
          path: '/projects/:projectId',
          builder: (context, state) => ProjectDetailScreen(
            projectId: state.pathParameters['projectId']!,
          ),
        ),
        GoRoute(
          path: '/settings/backup-restore/backup',
          builder: (context, state) {
            onRoute?.call(state.uri.toString());
            final args = state.extra;
            return Scaffold(
              body: Text(
                args is ProjectBackupSelectionArguments
                    ? 'backup:${args.initialProjectIds.join(',')}'
                    : 'backup:none',
                key: const Key('backup-route-probe'),
              ),
            );
          },
        ),
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Text('home', key: Key('home-probe'))),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          captureOutputPathsProvider.overrideWithValue(
            _FakeCaptureOutputPaths(),
          ),
          if (deletions != null)
            projectDeletionServiceProvider.overrideWithValue(deletions),
        ],
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
      ),
    );
    await pumpUi(tester);
  }

  Future<void> seedProject(
    AppDatabase database, {
    required String id,
    required String name,
    ProjectLifecycleStatus status = ProjectLifecycleStatus.active,
    bool pinned = false,
  }) async {
    await database.createProject(
      id: id,
      name: name,
      lifecycleStatus: status,
      isPinned: pinned,
    );
  }

  testWidgets('shows active project summary', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await seedProject(database, id: 'p1', name: '东区厂房改造');

    await pumpDetail(tester, database: database, projectId: 'p1');

    expect(find.byKey(const Key('project-summary')), findsOneWidget);
    expect(find.text('东区厂房改造'), findsWidgets);
    expect(find.byKey(const Key('project-status-banner')), findsNothing);
    expect(find.byKey(const Key('project-actions')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('archived project shows banner and hides capture FAB', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await seedProject(
      database,
      id: 'p1',
      name: '已归档项目',
      status: ProjectLifecycleStatus.archived,
    );

    await pumpDetail(tester, database: database, projectId: 'p1');

    expect(find.byKey(const Key('project-status-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-fab')), findsNothing);
    await unmount(tester);
  });

  testWidgets('pin from action sheet persists', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await seedProject(database, id: 'p1', name: '东区厂房改造');

    await pumpDetail(tester, database: database, projectId: 'p1');

    await tester.tap(find.byKey(const Key('project-actions')));
    await pumpUi(tester);
    expect(find.byKey(const Key('project-action-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pin-project')));
    await pumpUi(tester);

    final pinned = await database.projectById('p1');
    expect(pinned?.isPinned, isTrue);
    await unmount(tester);
  });

  testWidgets('complete from action sheet marks project completed', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await seedProject(database, id: 'p1', name: '东区厂房改造');

    await pumpDetail(tester, database: database, projectId: 'p1');

    await tester.tap(find.byKey(const Key('project-actions')));
    await pumpUi(tester);
    await tester.tap(find.byKey(const Key('complete-project')));
    await pumpUi(tester);

    final completed = await database.projectById('p1');
    expect(completed?.lifecycleStatus, ProjectLifecycleStatus.completed);
    expect(find.byKey(const Key('project-status-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-fab')), findsNothing);
    await unmount(tester);
  });

  testWidgets('backup action opens selection route preselecting project', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await seedProject(database, id: 'p1', name: '东区厂房改造');
    String? route;
    await pumpDetail(
      tester,
      database: database,
      projectId: 'p1',
      onRoute: (value) => route = value,
    );

    await tester.tap(find.byKey(const Key('project-actions')));
    await pumpUi(tester);
    await tester.tap(find.byKey(const Key('project-backup-action')));
    await pumpUi(tester);

    expect(find.byKey(const Key('backup-route-probe')), findsOneWidget);
    expect(find.text('backup:p1'), findsOneWidget);
    expect(route, contains('/settings/backup-restore/backup'));
    await unmount(tester);
  });

  testWidgets('delete confirms, removes project, and returns home', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await seedProject(database, id: 'p1', name: '东区厂房改造');
    final deletions = ProjectDeletionService(
      database: database,
      capturePaths: _FakeCaptureOutputPaths(),
      files: _RecordingPrivateFileStore(),
      pendingStore: _MemoryProjectDeletionPendingStore(),
    );

    await pumpDetail(
      tester,
      database: database,
      projectId: 'p1',
      deletions: deletions,
    );

    await tester.tap(find.byKey(const Key('project-actions')));
    await pumpUi(tester);
    await tester.tap(find.byKey(const Key('delete-project')));
    await pumpUi(tester);
    expect(find.byKey(const Key('confirm-delete-project')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-project')));
    await pumpUi(tester);

    expect(await database.projectById('p1'), isNull);
    expect(find.byKey(const Key('home-probe')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('missing project shows not-found state', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await pumpDetail(tester, database: database, projectId: 'missing');

    expect(find.byKey(const Key('project-not-found')), findsOneWidget);
    await unmount(tester);
  });
}
