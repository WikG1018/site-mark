import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/projects/project_watermark_settings_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(id: 'project-1', name: '东区厂房改造');
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpWatermarkSettings(WidgetTester tester) async {
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
  }

  testWidgets('preview reflects the persisted watermark parameters', (
    tester,
  ) async {
    await pumpWatermarkSettings(tester);

    expect(find.byKey(const Key('watermark-preview')), findsOneWidget);
    expect(find.text('SM-2026-0001'), findsOneWidget);

    final opacity = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('watermark-preview-opacity')),
    );
    expect(opacity.opacity, 0.78);
    expect(opacity.duration, const Duration(milliseconds: 200));

    final align = tester.widget<Align>(
      find.descendant(
        of: find.byKey(const Key('watermark-preview')),
        matching: find.byType(Align),
      ),
    );
    expect(align.alignment, Alignment.bottomLeft);

    final number = tester.widget<Text>(find.text('SM-2026-0001'));
    expect(number.style?.color, const Color(0xff37c58b));
    expect(number.style?.fontSize, 11.0);
  });

  testWidgets('preview follows the opacity slider while dragging', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpWatermarkSettings(tester);
    final slider = find.byType(Slider).first;
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();

    await tester.timedDrag(
      slider,
      const Offset(500, 0),
      const Duration(milliseconds: 200),
    );
    await tester.pumpAndSettle();

    final opacity = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('watermark-preview-opacity')),
    );
    expect(opacity.opacity, 0.95);
  });

  testWidgets('preview follows position and accent color changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpWatermarkSettings(tester);

    await tester.scrollUntilVisible(
      find.text('右下'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('右下'));
    await tester.tap(find.text('右下'));
    await tester.pumpAndSettle();
    final align = tester.widget<Align>(
      find.descendant(
        of: find.byKey(const Key('watermark-preview')),
        matching: find.byType(Align),
      ),
    );
    expect(align.alignment, Alignment.bottomRight);

    await tester.scrollUntilVisible(
      find.byKey(const Key('accent-blue')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('accent-blue')));
    await tester.tap(find.byKey(const Key('accent-blue')));
    await tester.pumpAndSettle();
    final number = tester.widget<Text>(find.text('SM-2026-0001'));
    expect(number.style?.color, const Color(0xff1565c0));

    // The preview is display-only: nothing is persisted until 保存 is tapped.
    final project = await database.projectById('project-1');
    expect(project?.watermarkPosition, 'bottomLeft');
    expect(project?.watermarkAccentColorArgb, 0xff37c58b);
  });
}
