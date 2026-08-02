import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/capture_template_rules.dart';
import 'package:sitemark/features/capture/capture_recent_suggestions.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  Future<void> pumpSuggestions(
    WidgetTester tester, {
    required String projectId,
    required TextEditingController controller,
    required FocusNode focusNode,
    required Future<List<String>> Function({
      required String projectId,
      required CaptureSuggestionField field,
      required int limit,
    })
    load,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: Focus(
            focusNode: focusNode,
            child: CaptureRecentSuggestions(
              projectId: projectId,
              field: CaptureSuggestionField.workLocation,
              controller: controller,
              focusNode: focusNode,
              load: load,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('loads at most three compact suggestions after focus', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var loadCount = 0;
    String? loadedProject;
    CaptureSuggestionField? loadedField;
    int? loadedLimit;
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpSuggestions(
      tester,
      projectId: 'project-1',
      controller: controller,
      focusNode: focusNode,
      load: ({required projectId, required field, required limit}) async {
        loadCount++;
        loadedProject = projectId;
        loadedField = field;
        loadedLimit = limit;
        return ['Zone A', 'Zone B', 'Zone C', 'Zone D'];
      },
    );

    expect(loadCount, 0);
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.pump();

    expect(loadCount, 1);
    expect(focusNode.hasFocus, isTrue);
    expect(loadedProject, 'project-1');
    expect(loadedField, CaptureSuggestionField.workLocation);
    expect(loadedLimit, 20);
    expect(find.text('Zone A'), findsOneWidget);
    expect(find.text('Zone B'), findsOneWidget);
    expect(find.text('Zone C'), findsOneWidget);
    expect(find.text('Zone D'), findsNothing);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('selecting a suggestion replaces only the target controller', (
    tester,
  ) async {
    final target = TextEditingController(text: 'Old location');
    final notes = TextEditingController(text: 'Keep this note');
    final focusNode = FocusNode();
    addTearDown(() {
      target.dispose();
      notes.dispose();
      focusNode.dispose();
    });

    await pumpSuggestions(
      tester,
      projectId: 'project-1',
      controller: target,
      focusNode: focusNode,
      load: ({required projectId, required field, required limit}) async => [
        'New location',
      ],
    );
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('New location'));

    expect(target.text, 'New location');
    expect(notes.text, 'Keep this note');
  });

  testWidgets('more opens up to twenty history entries with local filtering', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });
    final entries = List.generate(22, (index) => 'Floor $index');

    await pumpSuggestions(
      tester,
      projectId: 'project-1',
      controller: controller,
      focusNode: focusNode,
      load: ({required projectId, required field, required limit}) async =>
          entries,
    );
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('Search history'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('recent-suggestions-search')),
      '  floor 1 ',
    );
    await tester.pump();
    expect(find.text('Floor 1'), findsOneWidget);
    expect(find.text('Floor 2'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('recent-suggestions-search')),
      '',
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Floor 19'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Floor 19'), findsOneWidget);
    expect(find.text('Floor 20'), findsNothing);
  });

  testWidgets('load failure keeps input and exposes a local retry', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Typed value');
    final focusNode = FocusNode();
    var attempt = 0;
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await pumpSuggestions(
      tester,
      projectId: 'project-1',
      controller: controller,
      focusNode: focusNode,
      load: ({required projectId, required field, required limit}) async {
        attempt++;
        if (attempt == 1) throw StateError('database unavailable');
        return ['Recovered'];
      },
    );
    focusNode.requestFocus();
    await tester.pumpAndSettle();

    expect(controller.text, 'Typed value');
    expect(find.text('Could not load suggestions'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Typed value');
    expect(find.text('Recovered'), findsOneWidget);
  });

  testWidgets('changing project discards old asynchronous suggestions', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final oldProject = Completer<List<String>>();
    String projectId = 'project-1';
    late StateSetter setProject;
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: StatefulBuilder(
          builder: (context, setState) {
            setProject = setState;
            return Scaffold(
              body: Focus(
                focusNode: focusNode,
                child: CaptureRecentSuggestions(
                  projectId: projectId,
                  field: CaptureSuggestionField.workLocation,
                  controller: controller,
                  focusNode: focusNode,
                  load: ({required projectId, required field, required limit}) {
                    if (projectId == 'project-1') return oldProject.future;
                    return Future.value(['New project value']);
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    setProject(() => projectId = 'project-2');
    await tester.pumpAndSettle();
    oldProject.complete(['Old project value']);
    await tester.pumpAndSettle();

    expect(find.text('New project value'), findsOneWidget);
    expect(find.text('Old project value'), findsNothing);
  });
}
