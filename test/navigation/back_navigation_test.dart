import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/capture/capture_form_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/capture_form_draft_store.dart';
import 'package:sitemark/platform/memory_pressure_coordinator.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_template_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  testWidgets(
    'system back closes confirmation then template sheet then capture page',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.createProject(id: 'project-1', name: 'Project');
      final template = await CaptureTemplateService(database: database).create(
        projectId: 'project-1',
        name: 'Template',
        workLocation: 'Location',
        workContent: 'Content',
        photographer: 'Photographer',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            captureFormDraftStoreProvider.overrideWithValue(
              MemoryCaptureFormDraftStore(),
            ),
            memoryPressureControllerProvider.overrideWithValue(
              MemoryPressureController(),
            ),
            platformServicesProvider.overrideWithValue(_BackPlatform()),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  key: const Key('open-capture-page'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const CaptureFormScreen(projectId: 'project-1'),
                    ),
                  ),
                  child: const Text('Origin page'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-capture-page')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('capture-template-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('capture-template-delete-${template.id}')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const Key('capture-template-sheet')), findsOneWidget);
      expect(find.byType(CaptureFormScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('capture-template-sheet')), findsOneWidget);
      expect(find.byType(CaptureFormScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('capture-template-sheet')), findsNothing);
      expect(find.byType(CaptureFormScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CaptureFormScreen), findsNothing);
      expect(find.byKey(const Key('open-capture-page')), findsOneWidget);
    },
  );
}

class _BackPlatform implements PlatformServices {
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
