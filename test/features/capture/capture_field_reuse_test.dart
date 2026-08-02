import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_failure.dart';
import 'package:sitemark/domain/capture_template_rules.dart';
import 'package:sitemark/features/capture/capture_form_screen.dart';
import 'package:sitemark/features/capture/capture_recent_suggestions.dart';
import 'package:sitemark/features/capture/capture_template_sheet.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/platform/capture_form_draft_store.dart';
import 'package:sitemark/platform/memory_pressure_coordinator.dart';
import 'package:sitemark/platform/memory_pressure_service.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_location_coordinator.dart';
import 'package:sitemark/workflow/capture_template_service.dart';
import 'package:sitemark/workflow/capture_workflow.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

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

  testWidgets(
    'replacing a focused focus node loads the new field immediately',
    (tester) async {
      final controller = TextEditingController();
      final oldFocus = FocusNode();
      final newFocus = FocusNode();
      var useNewFocus = false;
      var newLoadCount = 0;
      late StateSetter rebuild;
      addTearDown(() {
        controller.dispose();
        oldFocus.dispose();
        newFocus.dispose();
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
              rebuild = setState;
              final focusNode = useNewFocus ? newFocus : oldFocus;
              return Scaffold(
                body: Column(
                  children: [
                    Focus(focusNode: oldFocus, child: const SizedBox()),
                    Focus(focusNode: newFocus, child: const SizedBox()),
                    CaptureRecentSuggestions(
                      projectId: 'project-1',
                      field: CaptureSuggestionField.workLocation,
                      controller: controller,
                      focusNode: focusNode,
                      load:
                          ({
                            required projectId,
                            required field,
                            required limit,
                          }) {
                            if (focusNode == newFocus) newLoadCount++;
                            return Future.value(['New focused value']);
                          },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      newFocus.requestFocus();
      rebuild(() => useNewFocus = true);
      await tester.pumpAndSettle();

      expect(newLoadCount, 1);
      expect(find.text('New focused value'), findsOneWidget);
    },
  );

  testWidgets('simultaneous focused node and identity replacement loads once', (
    tester,
  ) async {
    final controller = TextEditingController();
    final oldFocus = FocusNode();
    final idleFocus = FocusNode();
    final newFocus = FocusNode();
    final staleResult = Completer<List<String>>();
    final newResult = Completer<List<String>>();
    var projectId = 'project-old';
    var field = CaptureSuggestionField.workLocation;
    var selectedFocus = oldFocus;
    var newLoadCount = 0;
    late StateSetter rebuild;
    addTearDown(() {
      controller.dispose();
      oldFocus.dispose();
      idleFocus.dispose();
      newFocus.dispose();
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
            rebuild = setState;
            return Scaffold(
              body: Column(
                children: [
                  Focus(focusNode: oldFocus, child: const SizedBox()),
                  Focus(focusNode: idleFocus, child: const SizedBox()),
                  Focus(focusNode: newFocus, child: const SizedBox()),
                  CaptureRecentSuggestions(
                    projectId: projectId,
                    field: field,
                    controller: controller,
                    focusNode: selectedFocus,
                    load:
                        ({required projectId, required field, required limit}) {
                          if (projectId == 'project-old') {
                            return staleResult.future;
                          }
                          if (projectId == 'project-new' &&
                              field == CaptureSuggestionField.photographer) {
                            newLoadCount++;
                            return newResult.future;
                          }
                          return Future.value(const <String>[]);
                        },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    oldFocus.requestFocus();
    await tester.pump();

    rebuild(() {
      projectId = 'project-gap';
      selectedFocus = idleFocus;
    });
    await tester.pump();

    newFocus.requestFocus();
    rebuild(() {
      projectId = 'project-new';
      field = CaptureSuggestionField.photographer;
      selectedFocus = newFocus;
    });
    await tester.pump();

    expect(newLoadCount, 1);
    newResult.complete(['New identity value']);
    await tester.pumpAndSettle();
    staleResult.complete(['Stale identity value']);
    await tester.pumpAndSettle();

    expect(find.text('New identity value'), findsOneWidget);
    expect(find.text('Stale identity value'), findsNothing);
  });

  testWidgets('more selection closes history and changes only its controller', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Before');
    final notes = TextEditingController(text: 'Keep note');
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      notes.dispose();
      focusNode.dispose();
    });
    await pumpSuggestions(
      tester,
      projectId: 'project-1',
      controller: controller,
      focusNode: focusNode,
      load: ({required projectId, required field, required limit}) async => [
        'One',
        'Two',
        'Three',
        'Four',
      ],
    );
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recent-suggestions-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Four'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.text, 'Four');
    expect(notes.text, 'Keep note');
  });

  testWidgets('system back closes only the history dialog', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });
    await pumpSuggestions(
      tester,
      projectId: 'project-1',
      controller: controller,
      focusNode: focusNode,
      load: ({required projectId, required field, required limit}) async => [
        'One',
        'Two',
        'Three',
        'Four',
      ],
    );
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recent-suggestions-more')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('capture-recent-suggestions')), findsOneWidget);
  });

  testWidgets('uses zero duration when animations are disabled', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
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
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Focus(
              focusNode: focusNode,
              child: CaptureRecentSuggestions(
                projectId: 'project-1',
                field: CaptureSuggestionField.workLocation,
                controller: controller,
                focusNode: focusNode,
                load: ({required projectId, required field, required limit}) =>
                    Future.value(['Value']),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<AnimatedSize>(
            find.byKey(const Key('capture-recent-suggestions')),
          )
          .duration,
      Duration.zero,
    );
  });

  testWidgets('long suggestions do not overflow at 360dp', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });
    await pumpSuggestions(
      tester,
      projectId: 'project-1',
      controller: controller,
      focusNode: focusNode,
      load: ({required projectId, required field, required limit}) async =>
          List.filled(4, 'Very long suggestion value for a narrow phone'),
    );
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recent-suggestions-more')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'template sheet lists newest first and applies only required fields',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'project-1', name: 'Project');
      var clock = DateTime(2026, 8, 1, 8);
      var nextId = 0;
      final service = CaptureTemplateService(
        database: database,
        idGenerator: () => 'template-${nextId++}',
        clock: () => clock,
      );
      await service.create(
        projectId: 'project-1',
        name: 'Older',
        workLocation: 'Old location',
        workContent: 'Old content',
        photographer: 'Old photographer',
      );
      clock = DateTime(2026, 8, 1, 9);
      await service.create(
        projectId: 'project-1',
        name: 'Newer',
        workLocation: 'New location',
        workContent: 'New content',
        photographer: 'New photographer',
      );

      CaptureRequiredFieldsSnapshot? selected;
      await _pumpTemplateSheetHost(
        tester,
        service: service,
        onSelected: (value) => selected = value,
      );
      await _openTemplateSheet(tester);

      expect(
        tester.getTopLeft(find.text('Newer')).dy,
        lessThan(tester.getTopLeft(find.text('Older')).dy),
      );
      await tester.tap(find.text('Newer'));
      await tester.pumpAndSettle();

      expect(
        selected,
        const CaptureRequiredFieldsSnapshot(
          workLocation: 'New location',
          workContent: 'New content',
          photographer: 'New photographer',
        ),
      );
      expect(find.byKey(const Key('capture-template-sheet')), findsNothing);
    },
  );

  testWidgets('template create keeps input and maps every service failure', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final failures = <CaptureTemplateFailure>[
      CaptureTemplateFailure.emptyName,
      CaptureTemplateFailure.nameTooLong,
      CaptureTemplateFailure.emptyWorkLocation,
      CaptureTemplateFailure.workLocationTooLong,
      CaptureTemplateFailure.emptyWorkContent,
      CaptureTemplateFailure.workContentTooLong,
      CaptureTemplateFailure.emptyPhotographer,
      CaptureTemplateFailure.photographerTooLong,
      CaptureTemplateFailure.duplicateName,
      CaptureTemplateFailure.projectLimitReached,
      CaptureTemplateFailure.invalidCharacter,
    ];
    final service = _FailureSequenceTemplateService(database, failures);
    await _pumpTemplateSheetHost(tester, service: service);
    await _openTemplateSheet(tester);
    await tester.tap(find.byKey(const Key('capture-template-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('capture-template-name')),
      'Keep this name',
    );

    const expected = <String>[
      'Enter a template name',
      'Template name is too long',
      'Work location is required',
      'Work location is too long',
      'Work content is required',
      'Work content is too long',
      'Photographer is required',
      'Photographer is too long',
      'A template with this name already exists',
      'This project already has 100 templates',
      'Template text cannot contain unsupported characters',
    ];
    for (var index = 0; index < expected.length; index++) {
      await tester.tap(find.byKey(const Key('capture-template-save')));
      await tester.pumpAndSettle();
      expect(find.text(expected[index]), findsOneWidget);
      expect(find.byKey(const Key('capture-template-sheet')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('capture-template-name')))
            .controller!
            .text,
        'Keep this name',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('capture-template-work-location')),
            )
            .controller!
            .text,
        'Current location',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('capture-template-work-content')),
            )
            .controller!
            .text,
        'Current content',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('capture-template-photographer')),
            )
            .controller!
            .text,
        'Current photographer',
      );
    }
  });

  testWidgets('load failure retries inside the open template sheet', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final service = _RetryingWatchTemplateService(database);
    await _pumpTemplateSheetHost(tester, service: service);
    await _openTemplateSheet(tester);

    expect(find.text('Could not load templates'), findsOneWidget);
    expect(find.byKey(const Key('capture-template-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture-template-retry')));
    await tester.pumpAndSettle();

    expect(service.watchCount, 2);
    expect(find.text('No templates yet'), findsOneWidget);
  });

  testWidgets('rename moves a template to the top', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    });
    final service = _RenameTemplateService(database);
    addTearDown(service.close);
    await _pumpTemplateSheetHost(tester, service: service);
    await _openTemplateSheet(tester);

    await tester.tap(
      find.byKey(const Key('capture-template-rename-template-0')),
    );
    await tester.pump(AppMotion.short4);
    await tester.enterText(
      find.byKey(const Key('capture-template-rename-name')),
      'Renamed first',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 400));
    final save = find.byKey(const Key('capture-template-rename-save'));
    await tester.ensureVisible(save);
    await tester.pump();
    await tester.tap(save.hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('Renamed first')).dy,
      lessThan(tester.getTopLeft(find.text('Second')).dy),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('creates and deletes a template without closing the sheet', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    });
    final service = _CrudTemplateService(database);
    addTearDown(service.close);
    await _pumpTemplateSheetHost(tester, service: service);
    await _openTemplateSheet(tester);

    await tester.tap(find.byKey(const Key('capture-template-create')));
    await tester.pump(AppMotion.short4);
    await tester.enterText(
      find.byKey(const Key('capture-template-name')),
      'Created template',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 400));
    final save = find.byKey(const Key('capture-template-save'));
    await tester.ensureVisible(save);
    await tester.tap(save.hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Created template'), findsOneWidget);
    expect(service.templates, hasLength(1));
    await tester.tap(
      find.byKey(const Key('capture-template-delete-created-template')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture-template-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Created template'), findsNothing);
    expect(service.templates, isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'real service persists normalized create and keeps duplicate rename input',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await database.close();
      });
      await database.createProject(id: 'project-1', name: 'Project');
      var nextId = 0;
      final service = CaptureTemplateService(
        database: database,
        idGenerator: () => 'real-template-${nextId++}',
      );
      await service.create(
        projectId: 'project-1',
        name: 'Existing',
        workLocation: 'Existing location',
        workContent: 'Existing content',
        photographer: 'Existing photographer',
      );
      await _pumpTemplateSheetHost(tester, service: service);
      await _openTemplateSheet(tester);

      await tester.tap(find.byKey(const Key('capture-template-create')));
      await tester.pump(AppMotion.short4);
      await tester.enterText(
        find.byKey(const Key('capture-template-name')),
        '  New   template  ',
      );
      await tester.enterText(
        find.byKey(const Key('capture-template-work-location')),
        '  New location  ',
      );
      await tester.enterText(
        find.byKey(const Key('capture-template-work-content')),
        '  New content  ',
      );
      await tester.enterText(
        find.byKey(const Key('capture-template-photographer')),
        '  New photographer  ',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.byKey(const Key('capture-template-save')).hitTestable(),
      );
      await _pumpUntilFound(tester, find.text('New template'));

      final created = (await database.captureTemplatesForProject(
        'project-1',
      )).singleWhere((value) => value.id == 'real-template-1');
      expect(created.name, 'New template');
      expect(created.workLocation, 'New location');
      expect(created.workContent, 'New content');
      expect(created.photographer, 'New photographer');

      await tester.tap(find.byKey(const Key('capture-template-create')));
      await tester.pump(AppMotion.short4);
      await tester.enterText(
        find.byKey(const Key('capture-template-name')),
        '  NEW   TEMPLATE ',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.byKey(const Key('capture-template-save')).hitTestable(),
      );
      await _pumpUntilFound(
        tester,
        find.text('A template with this name already exists'),
      );
      expect(find.byKey(const Key('capture-template-sheet')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('capture-template-name')))
            .controller!
            .text,
        '  NEW   TEMPLATE ',
      );

      await tester.tap(find.text('Cancel'));
      await tester.pump(AppMotion.short4);
      await tester.tap(
        find.byKey(const Key('capture-template-rename-real-template-1')),
      );
      await tester.pump(AppMotion.short4);
      await tester.enterText(
        find.byKey(const Key('capture-template-rename-name')),
        '  EXISTING  ',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.byKey(const Key('capture-template-rename-save')).hitTestable(),
      );
      await _pumpUntilFound(
        tester,
        find.text('A template with this name already exists'),
      );
      expect(find.byKey(const Key('capture-template-sheet')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('capture-template-rename-name')),
            )
            .controller!
            .text,
        '  EXISTING  ',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('delete explains scope and a failed write keeps sheet open', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final service = _DeleteFailureTemplateService(database);
    await _pumpTemplateSheetHost(tester, service: service);
    await _openTemplateSheet(tester);

    await tester.tap(
      find.byKey(const Key('capture-template-delete-template-1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Only this template will be deleted. Photos and the current form are not affected.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('capture-template-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('capture-template-sheet')), findsOneWidget);
    expect(find.text('Could not delete template. Try again.'), findsOneWidget);
  });

  testWidgets('pending create disables every template action and system back', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final service = _PendingTemplateService(database);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await service.close();
      await database.close();
    });
    await _pumpTemplateSheetHost(tester, service: service);
    await _openTemplateSheet(tester);
    await tester.tap(find.byKey(const Key('capture-template-create')));
    await tester.pump(AppMotion.short4);
    await tester.enterText(
      find.byKey(const Key('capture-template-name')),
      'Pending create',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(const Key('capture-template-save')).hitTestable(),
    );
    await tester.pump();

    expect(service.createCount, 1);
    _expectTemplateActionsDisabled(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('capture-template-sheet')), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('capture-template-save')),
      warnIfMissed: false,
    );
    expect(service.createCount, 1);

    service.completeCreate();
    await tester.pumpAndSettle();
    _expectTemplateActionsEnabled(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture-template-sheet')), findsNothing);
  });

  testWidgets('pending rename disables every template action and system back', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final service = _PendingTemplateService(database);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await service.close();
      await database.close();
    });
    await _pumpTemplateSheetHost(tester, service: service);
    await _openTemplateSheet(tester);
    await tester.tap(
      find.byKey(const Key('capture-template-rename-template-1')),
    );
    await tester.pump(AppMotion.short4);
    await tester.enterText(
      find.byKey(const Key('capture-template-rename-name')),
      'Pending rename',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(const Key('capture-template-rename-save')).hitTestable(),
    );
    await tester.pump();

    expect(service.renameCount, 1);
    _expectTemplateActionsDisabled(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('capture-template-sheet')), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('capture-template-rename-save')),
      warnIfMissed: false,
    );
    expect(service.renameCount, 1);

    service.completeRename();
    await tester.pumpAndSettle();
    _expectTemplateActionsEnabled(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('pending delete disables every template action and system back', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final service = _PendingTemplateService(database);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await service.close();
      await database.close();
    });
    await _pumpTemplateSheetHost(tester, service: service);
    await _openTemplateSheet(tester);
    await tester.tap(
      find.byKey(const Key('capture-template-delete-template-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture-template-delete-confirm')));
    await tester.pump();

    expect(service.deleteCount, 1);
    _expectTemplateActionsDisabled(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('capture-template-sheet')), findsOneWidget);
    expect(service.deleteCount, 1);

    service.completeDelete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('capture-template-create')))
          .onPressed,
      isNotNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'disabled animations remain operable and keyboard inset is kept',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final service = _DeleteFailureTemplateService(database);
      await _pumpTemplateSheetHost(
        tester,
        service: service,
        mediaQuery: const MediaQueryData(
          disableAnimations: true,
          viewInsets: EdgeInsets.only(bottom: 240),
        ),
      );
      await _openTemplateSheet(tester);

      expect(
        tester
            .widget<AnimatedSwitcher>(
              find.byKey(const Key('capture-template-switcher')),
            )
            .duration,
        Duration.zero,
      );
      expect(
        tester
            .widget<AnimatedSize>(
              find.byKey(const Key('capture-template-editor-size')),
            )
            .duration,
        Duration.zero,
      );
      expect(
        tester
            .widget<AnimatedPadding>(
              find.byKey(const Key('capture-template-keyboard-padding')),
            )
            .padding,
        const EdgeInsets.only(bottom: 240),
      );
      await tester.tap(find.text('Template one'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('capture-template-sheet')), findsNothing);
    },
  );

  testWidgets(
    'capture form applies templates, preserves notes, and undo is one-level',
    (tester) async {
      final rig = await _CaptureFormTestRig.create();
      addTearDown(rig.dispose);
      final service = CaptureTemplateService(database: rig.database);
      await service.create(
        projectId: 'project-1',
        name: 'Template one',
        workLocation: 'One location',
        workContent: 'One content',
        photographer: 'One photographer',
      );
      await service.create(
        projectId: 'project-1',
        name: 'Template two',
        workLocation: 'Two location',
        workContent: 'Two content',
        photographer: 'Two photographer',
      );
      await rig.drafts.save(_draft('project-1', 'Original'));
      await rig.pump(tester);

      expect(find.byKey(const Key('capture-template-button')), findsOneWidget);
      await _applyTemplateFromForm(tester, 'Template one');
      expect(rig.fieldText(tester, const Key('work-location')), 'One location');
      expect(rig.fieldText(tester, const Key('notes')), 'Original notes');
      await _applyTemplateFromForm(tester, 'Template two');
      expect(rig.fieldText(tester, const Key('work-location')), 'Two location');
      expect(rig.fieldText(tester, const Key('notes')), 'Original notes');

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(rig.fieldText(tester, const Key('work-location')), 'One location');
      expect(rig.fieldText(tester, const Key('work-content')), 'One content');
      expect(
        rig.fieldText(tester, const Key('photographer')),
        'One photographer',
      );
      expect(rig.fieldText(tester, const Key('notes')), 'Original notes');
    },
  );

  testWidgets(
    'cancelling a reopened template sheet keeps the prior undo valid',
    (tester) async {
      final rig = await _CaptureFormTestRig.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await rig.dispose();
      });
      final service = _CrudTemplateService(rig.database);
      addTearDown(service.close);
      rig.templateService = service;
      await service.create(
        projectId: 'project-1',
        name: 'Applied template',
        workLocation: 'Applied location',
        workContent: 'Applied content',
        photographer: 'Applied photographer',
      );
      await rig.drafts.save(_draft('project-1', 'Original'));
      await rig.pump(tester);

      await _applyTemplateFromForm(tester, 'Applied template');
      await tester.tap(find.byKey(const Key('capture-template-button')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(
        rig.fieldText(tester, const Key('work-location')),
        'Original location',
      );
      expect(
        rig.fieldText(tester, const Key('work-content')),
        'Original content',
      );
      expect(
        rig.fieldText(tester, const Key('photographer')),
        'Original photographer',
      );
      expect(rig.fieldText(tester, const Key('notes')), 'Original notes');
    },
  );

  testWidgets('template result and undo cannot mutate a replacement project', (
    tester,
  ) async {
    final rig = await _CaptureFormTestRig.create();
    addTearDown(rig.dispose);
    final service = CaptureTemplateService(database: rig.database);
    await service.create(
      projectId: 'project-1',
      name: 'Old project template',
      workLocation: 'Old template location',
      workContent: 'Old template content',
      photographer: 'Old template photographer',
    );
    await rig.drafts.save(_draft('project-1', 'Old'));
    await rig.drafts.save(_draft('project-2', 'New'));
    await rig.pump(tester);

    await _applyTemplateFromForm(tester, 'Old project template');
    await rig.switchProject(tester, 'project-2');
    expect(find.text('Undo'), findsNothing);
    expect(rig.fieldText(tester, const Key('work-location')), 'New location');
    expect(rig.fieldText(tester, const Key('notes')), 'New notes');
  });

  testWidgets('closing an old-project sheet cannot mutate the new project', (
    tester,
  ) async {
    final rig = await _CaptureFormTestRig.create();
    addTearDown(rig.dispose);
    final service = CaptureTemplateService(database: rig.database);
    await service.create(
      projectId: 'project-1',
      name: 'Old project template',
      workLocation: 'Old template location',
      workContent: 'Old template content',
      photographer: 'Old template photographer',
    );
    await rig.drafts.save(_draft('project-1', 'Old'));
    await rig.drafts.save(_draft('project-2', 'New'));
    await rig.pump(tester);

    await tester.tap(find.byKey(const Key('capture-template-button')));
    await tester.pumpAndSettle();
    rig.projectId.value = 'project-2';
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capture-template-sheet')), findsNothing);
    expect(rig.fieldText(tester, const Key('work-location')), 'New location');
    expect(rig.fieldText(tester, const Key('work-content')), 'New content');
    expect(
      rig.fieldText(tester, const Key('photographer')),
      'New photographer',
    );
    expect(rig.fieldText(tester, const Key('notes')), 'New notes');
    expect(find.text('Template applied'), findsNothing);
  });

  testWidgets(
    'project replacement closes its old sheet and can open the new project sheet',
    (tester) async {
      final rig = await _CaptureFormTestRig.create();
      final service = _CrudTemplateService(rig.database);
      rig.templateService = service;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await service.close();
        await rig.dispose();
      });
      await service.create(
        projectId: 'project-1',
        name: 'Project one template',
        workLocation: 'One location',
        workContent: 'One content',
        photographer: 'One photographer',
      );
      await service.create(
        projectId: 'project-2',
        name: 'Project two template',
        workLocation: 'Two location',
        workContent: 'Two content',
        photographer: 'Two photographer',
      );
      await rig.pump(tester);

      await tester.tap(find.byKey(const Key('capture-template-button')));
      await tester.pumpAndSettle();
      expect(find.text('Project one template'), findsOneWidget);

      rig.projectId.value = 'project-2';
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('capture-template-sheet')), findsNothing);
      expect(find.byType(CaptureFormScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('capture-template-button')));
      await tester.pumpAndSettle();
      expect(find.text('Project two template'), findsOneWidget);
      expect(find.text('Project one template'), findsNothing);
    },
  );

  testWidgets(
    'project replacement before the sheet first frame discards the old sheet',
    (tester) async {
      final rig = await _CaptureFormTestRig.create();
      final service = _CrudTemplateService(rig.database);
      rig.templateService = service;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await service.close();
        await rig.dispose();
      });
      await service.create(
        projectId: 'project-1',
        name: 'Project one template',
        workLocation: 'One location',
        workContent: 'One content',
        photographer: 'One photographer',
      );
      await service.create(
        projectId: 'project-2',
        name: 'Project two template',
        workLocation: 'Two location',
        workContent: 'Two content',
        photographer: 'Two photographer',
      );
      await rig.pump(tester);

      await tester.tap(find.byKey(const Key('capture-template-button')));
      rig.projectId.value = 'project-2';
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('capture-template-sheet')), findsNothing);
      expect(find.byType(CaptureFormScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('capture-template-button')));
      await tester.pumpAndSettle();
      expect(find.text('Project two template'), findsOneWidget);
      expect(find.text('Project one template'), findsNothing);
    },
  );

  testWidgets(
    'disposing the capture form before the sheet first frame leaves no modal',
    (tester) async {
      final rig = await _CaptureFormTestRig.create();
      final service = _CrudTemplateService(rig.database);
      rig.templateService = service;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await service.close();
        await rig.dispose();
      });
      await rig.pump(tester);

      await tester.tap(find.byKey(const Key('capture-template-button')));
      rig.showForm.value = false;
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('capture-form-replacement')), findsOneWidget);
      expect(find.byKey(const Key('capture-template-sheet')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a late sheet removal never pops an unrelated route above it', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final service = _CrudTemplateService(database);
    final controller = CaptureTemplateSheetController();
    final navigatorKey = GlobalKey<NavigatorState>();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await service.close();
      await database.close();
    });
    await _pumpTemplateSheetHost(
      tester,
      service: service,
      controller: controller,
      navigatorKey: navigatorKey,
    );

    await tester.tap(find.byKey(const Key('open-template-sheet')));
    controller.dismiss();
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (context) => const Scaffold(
            body: Text('Unrelated route', key: Key('unrelated-route')),
          ),
        ),
      ),
    );
    controller.dismiss();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unrelated-route')), findsOneWidget);
    expect(find.byKey(const Key('capture-template-sheet')), findsNothing);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unrelated-route')), findsNothing);
    expect(find.byKey(const Key('capture-template-sheet')), findsNothing);
    expect(find.byKey(const Key('open-template-sheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final outcome in [
    CaptureWorkflowOutcome.queued,
    CaptureWorkflowOutcome.delayed,
  ]) {
    testWidgets('stale ${outcome.name} clears only the origin project draft', (
      tester,
    ) async {
      final rig = await _CaptureFormTestRig.create();
      addTearDown(rig.dispose);
      await rig.drafts.save(_draft('project-1', 'Old'));
      await rig.drafts.save(_draft('project-2', 'Saved new'));
      await rig.pump(tester);

      final originalElement = tester.element(find.byType(CaptureFormScreen));
      await rig.capture(tester);
      expect(rig.workflow.drafts.single.projectId, 'project-1');

      await rig.switchProject(tester, 'project-2');
      expect(
        identical(
          originalElement,
          tester.element(find.byType(CaptureFormScreen)),
        ),
        isTrue,
      );
      await rig.enterCurrentFields(tester, prefix: 'Edited new');

      rig.workflow.complete(0, outcome);
      await tester.pumpAndSettle();

      expect(await rig.drafts.load('project-1'), isNull);
      expect(
        (await rig.drafts.load('project-2'))?.workLocation,
        'Saved new location',
      );
      expect(
        rig.fieldText(tester, const Key('work-location')),
        'Edited new location',
      );
      expect(
        rig.fieldText(tester, const Key('work-content')),
        'Edited new content',
      );
      expect(
        rig.fieldText(tester, const Key('photographer')),
        'Edited new photographer',
      );
      expect(rig.fieldText(tester, const Key('notes')), 'Edited new notes');
      expect(
        find.text('Photo queued for background processing. Continue shooting.'),
        findsNothing,
      );
      expect(
        find.text(
          'Photo saved. Background processing is delayed and will retry automatically; you can continue shooting.',
        ),
        findsNothing,
      );
    });
  }

  testWidgets('stale completion cannot finish a newer capture operation', (
    tester,
  ) async {
    final rig = await _CaptureFormTestRig.create();
    addTearDown(rig.dispose);
    await rig.drafts.save(_draft('project-1', 'Old'));
    await rig.drafts.save(_draft('project-2', 'New'));
    await rig.pump(tester);

    await rig.capture(tester);
    await rig.switchProject(tester, 'project-2');
    await rig.enterCurrentFields(tester, prefix: 'Project 2');
    await rig.capture(tester);
    expect(rig.workflow.drafts, hasLength(2));
    expect(rig.workflow.drafts.last.projectId, 'project-2');
    expect(rig.captureButton(tester).onPressed, isNull);
    expect(find.byKey(const ValueKey('capture-button-busy')), findsOneWidget);

    rig.workflow.complete(0, CaptureWorkflowOutcome.queued);
    await tester.pump();

    expect(rig.captureButton(tester).onPressed, isNull);
    expect(find.byKey(const ValueKey('capture-button-busy')), findsOneWidget);
    expect(rig.fieldText(tester, const Key('notes')), 'Project 2 notes');
    expect(
      find.text('Photo queued for background processing. Continue shooting.'),
      findsNothing,
    );

    rig.workflow.complete(1, CaptureWorkflowOutcome.cancelled);
    await tester.pumpAndSettle();

    expect(rig.captureButton(tester).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('capture-button-idle')), findsOneWidget);
    expect(rig.fieldText(tester, const Key('notes')), 'Project 2 notes');
  });

  for (final outcome in [
    CaptureWorkflowOutcome.cancelled,
    CaptureWorkflowOutcome.failed,
  ]) {
    testWidgets(
      'stale ${outcome.name} leaves the replacement project unchanged',
      (tester) async {
        final rig = await _CaptureFormTestRig.create();
        addTearDown(rig.dispose);
        await rig.drafts.save(_draft('project-1', 'Old'));
        await rig.drafts.save(_draft('project-2', 'New'));
        await rig.pump(tester);

        await rig.capture(tester);
        await rig.switchProject(tester, 'project-2');
        await rig.enterCurrentFields(tester, prefix: 'Project 2');
        await rig.capture(tester);

        rig.workflow.complete(
          0,
          outcome,
          failureCode: outcome == CaptureWorkflowOutcome.failed
              ? CaptureFailureCode.cameraUnavailable
              : null,
        );
        await tester.pump();

        expect(rig.captureButton(tester).onPressed, isNull);
        expect(
          find.byKey(const ValueKey('capture-button-busy')),
          findsOneWidget,
        );
        expect(
          rig.fieldText(tester, const Key('work-location')),
          'Project 2 location',
        );
        expect(rig.fieldText(tester, const Key('notes')), 'Project 2 notes');
        expect(find.textContaining('Capture failed'), findsNothing);

        rig.workflow.complete(1, CaptureWorkflowOutcome.cancelled);
        await tester.pumpAndSettle();
        expect(rig.captureButton(tester).onPressed, isNotNull);
      },
    );
  }

  testWidgets('same CaptureFormScreen state isolates a replacement project', (
    tester,
  ) async {
    final database = _DelayedProjectDatabase();
    final drafts = MemoryCaptureFormDraftStore();
    final memory = MemoryPressureController();
    await database.createProject(id: 'project-1', name: 'Old project');
    await database.createProject(id: 'project-2', name: 'New project');
    await drafts.save(
      const CaptureFormDraftSnapshot(
        projectId: 'project-2',
        workLocation: 'New location',
        workContent: 'New content',
        photographer: 'New photographer',
        notes: 'New notes',
      ),
    );
    String projectId = 'project-1';
    late StateSetter replaceProject;
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          captureFormDraftStoreProvider.overrideWithValue(drafts),
          memoryPressureControllerProvider.overrideWithValue(memory),
          platformServicesProvider.overrideWithValue(_FormPlatform()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: StatefulBuilder(
            builder: (context, setState) {
              replaceProject = setState;
              return CaptureFormScreen(projectId: projectId);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await database.releaseFirstProject();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture-form')), findsOneWidget);

    database.delaySecondProject = true;
    replaceProject(() => projectId = 'project-2');
    await tester.pump();

    expect(find.byKey(const Key('capture-form')), findsNothing);
    expect(find.byKey(const Key('capture-button')), findsNothing);

    await database.releaseSecondProject();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('work-location')))
          .controller!
          .text,
      'New location',
    );
    await memory.dispatch(MemoryPressureLevel.kill);
    expect((await drafts.load('project-2'))?.workLocation, 'New location');
    expect(await drafts.load('project-1'), isNull);
  });
}

Future<void> _pumpTemplateSheetHost(
  WidgetTester tester, {
  required CaptureTemplateService service,
  ValueChanged<CaptureRequiredFieldsSnapshot>? onSelected,
  MediaQueryData? mediaQuery,
  CaptureTemplateSheetController? controller,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('en'),
      builder: mediaQuery == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: mediaQuery.disableAnimations,
                viewInsets: mediaQuery.viewInsets,
              ),
              child: child!,
            ),
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            key: const Key('open-template-sheet'),
            onPressed: () async {
              final value = await showCaptureTemplateSheet(
                context: context,
                projectId: 'project-1',
                current: const CaptureRequiredFieldsSnapshot(
                  workLocation: 'Current location',
                  workContent: 'Current content',
                  photographer: 'Current photographer',
                ),
                service: service,
                controller: controller,
              );
              if (value != null) onSelected?.call(value);
            },
            child: const Text('Open templates'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openTemplateSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-template-sheet')));
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

Future<void> _applyTemplateFromForm(
  WidgetTester tester,
  String templateName,
) async {
  final button = find.byKey(const Key('capture-template-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.tap(find.text(templateName));
  await tester.pumpAndSettle();
}

void _expectTemplateActionsDisabled(WidgetTester tester) {
  expect(
    tester
        .widget<TextButton>(find.byKey(const Key('capture-template-create')))
        .onPressed,
    isNull,
  );
  expect(
    tester
        .widget<ListTile>(find.byKey(const Key('capture-template-template-1')))
        .onTap,
    isNull,
  );
  expect(
    tester
        .widget<IconButton>(
          find.byKey(const Key('capture-template-rename-template-1')),
        )
        .onPressed,
    isNull,
  );
  expect(
    tester
        .widget<IconButton>(
          find.byKey(const Key('capture-template-delete-template-1')),
        )
        .onPressed,
    isNull,
  );
}

void _expectTemplateActionsEnabled(WidgetTester tester) {
  expect(
    tester
        .widget<TextButton>(find.byKey(const Key('capture-template-create')))
        .onPressed,
    isNotNull,
  );
  expect(
    tester
        .widget<ListTile>(find.byKey(const Key('capture-template-template-1')))
        .onTap,
    isNotNull,
  );
  expect(
    tester
        .widget<IconButton>(
          find.byKey(const Key('capture-template-rename-template-1')),
        )
        .onPressed,
    isNotNull,
  );
  expect(
    tester
        .widget<IconButton>(
          find.byKey(const Key('capture-template-delete-template-1')),
        )
        .onPressed,
    isNotNull,
  );
}

CaptureTemplate _template({
  required String id,
  required String name,
  DateTime? updatedAt,
}) {
  final timestamp = updatedAt ?? DateTime(2026, 8, 1);
  return CaptureTemplate(
    id: id,
    projectId: 'project-1',
    name: name,
    nameKey: name.toLowerCase(),
    workLocation: '$name location',
    workContent: '$name content',
    photographer: '$name photographer',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

class _FailureSequenceTemplateService extends CaptureTemplateService {
  _FailureSequenceTemplateService(AppDatabase database, this.failures)
    : super(database: database);

  final List<CaptureTemplateFailure> failures;
  var _attempt = 0;

  @override
  Stream<List<CaptureTemplate>> watch(String projectId) =>
      Stream.value(const <CaptureTemplate>[]);

  @override
  Future<CaptureTemplate> create({
    required String projectId,
    required String name,
    required String workLocation,
    required String workContent,
    required String photographer,
  }) async {
    throw CaptureTemplateException(failures[_attempt++]);
  }
}

class _RetryingWatchTemplateService extends CaptureTemplateService {
  _RetryingWatchTemplateService(AppDatabase database)
    : super(database: database);

  var watchCount = 0;

  @override
  Stream<List<CaptureTemplate>> watch(String projectId) {
    watchCount++;
    if (watchCount == 1) {
      return Stream<List<CaptureTemplate>>.error(
        StateError('database unavailable'),
      );
    }
    return Stream.value(const <CaptureTemplate>[]);
  }
}

class _DeleteFailureTemplateService extends CaptureTemplateService {
  _DeleteFailureTemplateService(AppDatabase database)
    : super(database: database);

  @override
  Stream<List<CaptureTemplate>> watch(String projectId) =>
      Stream.value([_template(id: 'template-1', name: 'Template one')]);

  @override
  Future<void> delete({
    required String projectId,
    required String templateId,
  }) async {
    throw StateError('database unavailable');
  }
}

class _RenameTemplateService extends CaptureTemplateService {
  _RenameTemplateService(AppDatabase database) : super(database: database);

  final _updates = StreamController<List<CaptureTemplate>>.broadcast();
  List<CaptureTemplate> _templates = [
    _template(
      id: 'template-1',
      name: 'Second',
      updatedAt: DateTime(2026, 8, 1, 9),
    ),
    _template(
      id: 'template-0',
      name: 'First',
      updatedAt: DateTime(2026, 8, 1, 8),
    ),
  ];

  @override
  Stream<List<CaptureTemplate>> watch(String projectId) async* {
    yield _templates;
    yield* _updates.stream;
  }

  @override
  Future<CaptureTemplate> rename({
    required String projectId,
    required String templateId,
    required String name,
  }) async {
    final current = _templates.singleWhere((value) => value.id == templateId);
    final renamed = CaptureTemplate(
      id: current.id,
      projectId: current.projectId,
      name: name,
      nameKey: name.toLowerCase(),
      workLocation: current.workLocation,
      workContent: current.workContent,
      photographer: current.photographer,
      createdAt: current.createdAt,
      updatedAt: DateTime(2026, 8, 1, 10),
    );
    _templates = [
      renamed,
      ..._templates.where((value) => value.id != templateId),
    ];
    _updates.add(_templates);
    return renamed;
  }

  Future<void> close() => _updates.close();
}

class _CrudTemplateService extends CaptureTemplateService {
  _CrudTemplateService(AppDatabase database) : super(database: database);

  final _updates = StreamController<List<CaptureTemplate>>.broadcast();
  final List<CaptureTemplate> templates = [];

  @override
  Stream<List<CaptureTemplate>> watch(String projectId) async* {
    List<CaptureTemplate> forProject(List<CaptureTemplate> values) => values
        .where((value) => value.projectId == projectId)
        .toList(growable: false);
    yield forProject(templates);
    await for (final update in _updates.stream) {
      yield forProject(update);
    }
  }

  @override
  Future<CaptureTemplate> create({
    required String projectId,
    required String name,
    required String workLocation,
    required String workContent,
    required String photographer,
  }) async {
    final created = CaptureTemplate(
      id: 'created-template',
      projectId: projectId,
      name: name,
      nameKey: name.toLowerCase(),
      workLocation: workLocation,
      workContent: workContent,
      photographer: photographer,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
    );
    templates.add(created);
    _updates.add([...templates]);
    return created;
  }

  @override
  Future<void> delete({
    required String projectId,
    required String templateId,
  }) async {
    templates.removeWhere(
      (value) => value.projectId == projectId && value.id == templateId,
    );
    _updates.add([...templates]);
  }

  Future<void> close() => _updates.close();
}

class _PendingTemplateService extends CaptureTemplateService {
  _PendingTemplateService(AppDatabase database) : super(database: database);

  final _updates = StreamController<List<CaptureTemplate>>.broadcast();
  final _createResult = Completer<void>();
  final _renameResult = Completer<void>();
  final _deleteResult = Completer<void>();
  List<CaptureTemplate> _templates = [
    _template(id: 'template-1', name: 'Template one'),
  ];
  var createCount = 0;
  var renameCount = 0;
  var deleteCount = 0;

  String? _createProjectId;
  String? _createName;
  String? _createWorkLocation;
  String? _createWorkContent;
  String? _createPhotographer;
  String? _renameTemplateId;
  String? _renameName;

  @override
  Stream<List<CaptureTemplate>> watch(String projectId) async* {
    yield _templates;
    yield* _updates.stream;
  }

  @override
  Future<CaptureTemplate> create({
    required String projectId,
    required String name,
    required String workLocation,
    required String workContent,
    required String photographer,
  }) async {
    createCount++;
    _createProjectId = projectId;
    _createName = name;
    _createWorkLocation = workLocation;
    _createWorkContent = workContent;
    _createPhotographer = photographer;
    await _createResult.future;
    final created = CaptureTemplate(
      id: 'template-2',
      projectId: _createProjectId!,
      name: _createName!,
      nameKey: _createName!.toLowerCase(),
      workLocation: _createWorkLocation!,
      workContent: _createWorkContent!,
      photographer: _createPhotographer!,
      createdAt: DateTime(2026, 8, 1, 1),
      updatedAt: DateTime(2026, 8, 1, 1),
    );
    _templates = [created, ..._templates];
    _updates.add(_templates);
    return created;
  }

  @override
  Future<CaptureTemplate> rename({
    required String projectId,
    required String templateId,
    required String name,
  }) async {
    renameCount++;
    _renameTemplateId = templateId;
    _renameName = name;
    await _renameResult.future;
    final current = _templates.singleWhere(
      (value) => value.id == _renameTemplateId,
    );
    final renamed = CaptureTemplate(
      id: current.id,
      projectId: current.projectId,
      name: _renameName!,
      nameKey: _renameName!.toLowerCase(),
      workLocation: current.workLocation,
      workContent: current.workContent,
      photographer: current.photographer,
      createdAt: current.createdAt,
      updatedAt: DateTime(2026, 8, 1, 1),
    );
    _templates = [renamed];
    _updates.add(_templates);
    return renamed;
  }

  @override
  Future<void> delete({
    required String projectId,
    required String templateId,
  }) async {
    deleteCount++;
    await _deleteResult.future;
    _templates = [
      ..._templates.where(
        (value) => value.projectId != projectId || value.id != templateId,
      ),
    ];
    _updates.add(_templates);
  }

  void completeCreate() => _createResult.complete();

  void completeRename() => _renameResult.complete();

  void completeDelete() => _deleteResult.complete();

  Future<void> close() => _updates.close();
}

class _DelayedProjectDatabase extends AppDatabase {
  _DelayedProjectDatabase() : super.forTesting(NativeDatabase.memory());

  final Completer<Project?> _firstProject = Completer<Project?>();
  final Completer<Project?> _secondProject = Completer<Project?>();
  var _delayFirstProject = true;
  var delaySecondProject = false;

  @override
  Future<Project?> projectById(String projectId) {
    if (projectId == 'project-1' && _delayFirstProject) {
      return _firstProject.future;
    }
    if (projectId == 'project-2' && delaySecondProject) {
      return _secondProject.future;
    }
    return super.projectById(projectId);
  }

  Future<void> releaseFirstProject() async {
    _delayFirstProject = false;
    _firstProject.complete(await super.projectById('project-1'));
  }

  Future<void> releaseSecondProject() async {
    delaySecondProject = false;
    _secondProject.complete(await super.projectById('project-2'));
  }
}

class _FormPlatform implements PlatformServices {
  @override
  Future<String> createCameraTarget(String captureId) async => '/$captureId';

  @override
  Future<void> deletePublishedImage(String contentUri) async {}

  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}

  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      LocationPermissionState.granted;

  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      ImageMetadataResult(
        width: 0,
        height: 0,
        fileSizeBytes: 0,
        mimeType: 'image/jpeg',
      );

  @override
  Future<CameraCaptureResult> launchCamera(String captureId) async =>
      CameraCaptureResult(
        outcome: CameraOutcome.cancelled,
        outputPath: '/$captureId',
      );

  @override
  Future<void> openApplicationSettings() async {}

  @override
  Future<String> publishJpeg(String sourcePath, String displayName) async => '';

  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;

  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async =>
      LocationResult(outcome: LocationOutcome.unavailable);

  @override
  Future<LocationPermissionState> requestLocationPermission() async =>
      LocationPermissionState.granted;
}

CaptureFormDraftSnapshot _draft(String projectId, String prefix) {
  return CaptureFormDraftSnapshot(
    projectId: projectId,
    workLocation: '$prefix location',
    workContent: '$prefix content',
    photographer: '$prefix photographer',
    notes: '$prefix notes',
  );
}

class _CaptureFormTestRig {
  _CaptureFormTestRig._({
    required this.database,
    required this.platform,
    required this.workflow,
  });

  static Future<_CaptureFormTestRig> create() async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createProject(id: 'project-1', name: 'Old project');
    await database.createProject(id: 'project-2', name: 'New project');
    final platform = _FormPlatform();
    return _CaptureFormTestRig._(
      database: database,
      platform: platform,
      workflow: _ControlledCaptureWorkflow(
        database: database,
        platform: platform,
      ),
    );
  }

  final AppDatabase database;
  final _FormPlatform platform;
  final _ControlledCaptureWorkflow workflow;
  final drafts = MemoryCaptureFormDraftStore();
  final memory = MemoryPressureController();
  final projectId = ValueNotifier<String>('project-1');
  final showForm = ValueNotifier<bool>(true);
  CaptureTemplateService? templateService;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          captureFormDraftStoreProvider.overrideWithValue(drafts),
          memoryPressureControllerProvider.overrideWithValue(memory),
          platformServicesProvider.overrideWithValue(platform),
          captureWorkflowProvider.overrideWithValue(workflow),
          if (templateService != null)
            captureTemplateServiceProvider.overrideWithValue(templateService!),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: ValueListenableBuilder<bool>(
            valueListenable: showForm,
            builder: (context, visible, child) {
              if (!visible) {
                return const Scaffold(
                  key: Key('capture-form-replacement'),
                  body: SizedBox.shrink(),
                );
              }
              return ValueListenableBuilder<String>(
                valueListenable: projectId,
                builder: (context, value, child) {
                  return CaptureFormScreen(projectId: value);
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> switchProject(WidgetTester tester, String value) async {
    projectId.value = value;
    await tester.pumpAndSettle();
  }

  Future<void> enterCurrentFields(
    WidgetTester tester, {
    required String prefix,
  }) async {
    await tester.enterText(
      find.byKey(const Key('work-location')),
      '$prefix location',
    );
    await tester.enterText(
      find.byKey(const Key('work-content')),
      '$prefix content',
    );
    await tester.enterText(
      find.byKey(const Key('photographer')),
      '$prefix photographer',
    );
    await tester.enterText(find.byKey(const Key('notes')), '$prefix notes');
  }

  Future<void> capture(WidgetTester tester) async {
    final button = find.byKey(const Key('capture-button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button.hitTestable());
    await tester.pump();
  }

  FilledButton captureButton(WidgetTester tester) {
    return tester.widget<FilledButton>(find.byKey(const Key('capture-button')));
  }

  String fieldText(WidgetTester tester, Key key) {
    return tester.widget<TextFormField>(find.byKey(key)).controller!.text;
  }

  Future<void> dispose() async {
    showForm.dispose();
    projectId.dispose();
    await database.close();
  }
}

class _ControlledCaptureWorkflow extends CaptureWorkflow {
  factory _ControlledCaptureWorkflow({
    required AppDatabase database,
    required PlatformServices platform,
  }) {
    return _ControlledCaptureWorkflow._(
      database: database,
      platform: platform,
      scheduler: _NoopCaptureScheduler(),
      images: RustImagePipeline(),
      outputPaths: AppCaptureOutputPaths(),
      locationCoordinator: CaptureLocationCoordinator(
        database: database,
        platform: platform,
        scheduler: _NoopCaptureScheduler(),
      ),
    );
  }

  _ControlledCaptureWorkflow._({
    required super.database,
    required super.platform,
    required super.scheduler,
    required super.images,
    required super.outputPaths,
    required super.locationCoordinator,
  });

  final List<CaptureDraft> drafts = [];
  final List<Completer<CaptureWorkflowResult>> _results = [];

  @override
  Future<CaptureWorkflowResult> capture(CaptureDraft draft) {
    drafts.add(draft);
    final result = Completer<CaptureWorkflowResult>();
    _results.add(result);
    return result.future;
  }

  void complete(
    int index,
    CaptureWorkflowOutcome outcome, {
    CaptureFailureCode? failureCode,
  }) {
    _results[index].complete(
      CaptureWorkflowResult(outcome: outcome, failureCode: failureCode),
    );
  }
}

class _NoopCaptureScheduler implements CaptureBackgroundScheduler {
  @override
  Future<void> enqueue(String captureId) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> reconcilePending() async {}

  @override
  Future<void> retry(String captureId) async {}
}
