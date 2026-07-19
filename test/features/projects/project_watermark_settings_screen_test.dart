import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/projects/project_watermark_settings_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

class _CountingAppDatabase extends AppDatabase {
  _CountingAppDatabase(super.executor) : super.forTesting();

  var projectByIdCalls = 0;

  @override
  Future<Project?> projectById(String projectId) {
    projectByIdCalls += 1;
    return super.projectById(projectId);
  }
}

void main() {
  testWidgets('repeated watermark slider drags read the project once', (
    tester,
  ) async {
    final database = _CountingAppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');

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
          home: const ProjectWatermarkSettingsScreen(projectId: 'project-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final opacitySlider = find.byType(Slider).first;
    await tester.drag(opacitySlider, const Offset(60, 0));
    await tester.pumpAndSettle();
    await tester.drag(opacitySlider, const Offset(-40, 0));
    await tester.pumpAndSettle();

    expect(database.projectByIdCalls, 1);
  });
}
