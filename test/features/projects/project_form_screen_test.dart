import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/features/projects/project_form_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  testWidgets('create failure resets saving and shows a friendly snackbar', (
    tester,
  ) async {
    final database = _FailingCreateDatabase();
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const ProjectFormScreen(),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('project-name')), 'East Plant');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings(const Locale('en')).createProjectFailed),
      findsOneWidget,
    );
    expect(find.textContaining(r'C:\private\database'), findsNothing);
    expect(find.textContaining('sitemark.sqlite'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNotNull,
    );
    expect(find.byKey(const Key('project-name')), findsOneWidget);
  });
}

class _FailingCreateDatabase extends AppDatabase {
  _FailingCreateDatabase() : super.forTesting(NativeDatabase.memory());

  @override
  Future<Project> createProject({
    required String id,
    required String name,
    String? description,
    String? watermarkPosition,
    double? watermarkOpacity,
    int? watermarkAccentColorArgb,
    double? watermarkFontScale,
    String? restoreOperationId,
    ProjectLifecycleStatus lifecycleStatus = ProjectLifecycleStatus.active,
    bool isPinned = false,
    DateTime? createdAt,
  }) {
    return Future<Project>.error(
      StateError(r'disk full at C:\private\database\sitemark.sqlite'),
    );
  }
}
