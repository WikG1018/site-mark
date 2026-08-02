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
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/capture_form_draft_store.dart';
import 'package:sitemark/platform/memory_pressure_coordinator.dart';
import 'package:sitemark/platform/memory_pressure_service.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_location_coordinator.dart';
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

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          captureFormDraftStoreProvider.overrideWithValue(drafts),
          memoryPressureControllerProvider.overrideWithValue(memory),
          platformServicesProvider.overrideWithValue(platform),
          captureWorkflowProvider.overrideWithValue(workflow),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: ValueListenableBuilder<String>(
            valueListenable: projectId,
            builder: (context, value, child) {
              return CaptureFormScreen(projectId: value);
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
