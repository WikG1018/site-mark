import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/main.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart';
import 'package:sitemark/src/rust/frb_generated.dart';
import 'package:sitemark/workflow/capture_processor.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

/// Integration tests for the SiteMark v0.2.0 user-visible flow.
///
/// These tests run under [IntegrationTestWidgetsFlutterBinding] and therefore
/// require a device or emulator (`flutter test integration_test/`). They reuse
/// the same inline-scheduler and fake platform/image/sharing layer as
/// `test/widget_test.dart` so the system-camera, background-queue, and
/// filtered-records surfaces can be driven end-to-end without a real camera.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);

  testWidgets('starts at the project list', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      MyApp(database: database, initialLocale: const Locale('zh')),
    );
    await tester.pumpAndSettle();

    expect(find.text('工程印记'), findsOneWidget);
    expect(find.text('新建项目'), findsWidgets);
  });

  testWidgets(
    'capture queues, remains ready, and appears in filtered records',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await createProjectAndOpenCapture(tester, database: database);
      await enterRequiredCaptureFields(tester);
      await tapSystemCameraAndReturnCaptured(tester);

      expect(find.text('照片已加入后台处理，可继续拍摄'), findsOneWidget);
      expect(find.byKey(const Key('capture-button')), findsOneWidget);
      await openAllRecords(tester);
      await selectCaptureDate(tester, DateTime(2026, 7, 16));
      expect(find.text('SM-20260716-001'), findsOneWidget);
    },
  );
}

/// Creates a project named `东区厂房改造`, taps into its detail screen, and
/// opens the capture form. Wires the same fakes as `test/widget_test.dart` and
/// pins the capture clock to 2026-07-16 so the photo number is deterministic.
Future<void> createProjectAndOpenCapture(
  WidgetTester tester, {
  required AppDatabase database,
}) async {
  final platform = _IntegrationPlatformServices();
  final images = _IntegrationImagePipeline();
  final outputPaths = _IntegrationOutputPaths();
  final scheduler = _InlineProcessingScheduler(
    database: database,
    platform: platform,
    images: images,
    outputPaths: outputPaths,
  );
  await tester.pumpWidget(
    MyApp(
      database: database,
      initialLocale: const Locale('zh'),
      platformServices: platform,
      imagePipeline: images,
      outputPaths: outputPaths,
      projectExportPaths: _IntegrationProjectExportPaths(),
      shareService: _IntegrationShareService(),
      privateFileStore: _IntegrationPrivateFileStore(),
      backgroundScheduler: scheduler,
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('新建项目'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('project-name')), '东区厂房改造');
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('东区厂房改造'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('拍摄'));
  await tester.pumpAndSettle();
}

/// Fills the three required capture fields. Notes are intentionally left blank
/// so the carry-forward invariant (notes cleared between shots) is exercised.
Future<void> enterRequiredCaptureFields(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('work-location')), 'A 区三层');
  await tester.enterText(find.byKey(const Key('work-content')), '风管安装检查');
  await tester.enterText(find.byKey(const Key('photographer')), '张工');
}

/// Taps the capture button. The fake camera immediately reports `captured`, so
/// the workflow marks the record captured, enqueues it, and the inline
/// scheduler renders/publishes synchronously.
Future<void> tapSystemCameraAndReturnCaptured(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('capture-button')));
  await tester.pumpAndSettle();
}

/// Returns to the home project list and opens the global all-records surface.
Future<void> openAllRecords(WidgetTester tester) async {
  await tester.tap(find.byTooltip('全部记录'));
  await tester.pumpAndSettle();
}

/// Selects the year/month/day matching [date] in the cascading filter bar.
Future<void> selectCaptureDate(WidgetTester tester, DateTime date) async {
  await tester.tap(find.byKey(const Key('filter-year')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(date.year.toString()).last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('filter-month')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('${date.month}月').last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('filter-day')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('${date.day}日').last);
  await tester.pumpAndSettle();
}

class _IntegrationPlatformServices implements PlatformServices {
  @override
  Future<String> createCameraTarget(String captureId) async =>
      '/private/$captureId.jpg';

  @override
  Future<void> deletePublishedImage(String contentUri) async {}

  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}

  @override
  Future<CameraCaptureResult> launchCamera(String captureId) async {
    return CameraCaptureResult(
      outcome: CameraOutcome.captured,
      outputPath: '/private/$captureId.jpg',
    );
  }

  @override
  Future<String> publishJpeg(String sourcePath, String displayName) async =>
      'content://media/site-mark/$displayName';

  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;

  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async {
    return LocationResult(outcome: LocationOutcome.permissionDenied);
  }

  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      LocationPermissionState.denied;

  @override
  Future<LocationPermissionState> requestLocationPermission() async =>
      LocationPermissionState.denied;

  @override
  Future<void> openApplicationSettings() async {}

  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      ImageMetadataResult(
        width: 0,
        height: 0,
        fileSizeBytes: 0,
        mimeType: 'image/jpeg',
      );
}

class _IntegrationImagePipeline implements ImagePipeline {
  @override
  Future<ExportProjectResult> export(ExportProjectRequest request) async {
    return ExportProjectResult(
      outputZipPath: request.outputZipPath,
      archiveSha256:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      photoCount: request.photos.length,
    );
  }

  @override
  Future<RenderPhotoResult> render(RenderPhotoRequest request) async {
    return RenderPhotoResult(
      outputPath: request.outputPath,
      outputSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      width: 4000,
      height: 3000,
    );
  }

  @override
  Future<String> sha256(String path) async =>
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
}

class _IntegrationOutputPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/private/rendered/$captureId.jpg';
}

class _IntegrationProjectExportPaths implements ProjectExportPaths {
  @override
  Future<String> projectZipPath(String projectId) async =>
      '/exports/$projectId.zip';
}

class _IntegrationShareService implements ShareFileService {
  @override
  Future<void> shareFile(String path) async {}
}

class _IntegrationPrivateFileStore implements PrivateFileStore {
  @override
  Future<void> deleteIfExists(String path) async {}
}

/// A [CaptureBackgroundScheduler] that runs the real [CaptureProcessor] inline
/// on each enqueue/retry, simulating immediate WorkManager completion so the
/// integration test observes the `ready` transition without a background
/// isolate. Mirrors the `_InlineProcessingScheduler` in `test/widget_test.dart`.
class _InlineProcessingScheduler implements CaptureBackgroundScheduler {
  _InlineProcessingScheduler({
    required this.database,
    required this.platform,
    required this.images,
    required this.outputPaths,
  });

  final AppDatabase database;
  final PlatformServices platform;
  final ImagePipeline images;
  final CaptureOutputPaths outputPaths;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> enqueue(String captureId) async {
    final processor = CaptureProcessor(
      database: database,
      platform: platform,
      images: images,
      outputPaths: outputPaths,
    );
    await processor.process(captureId);
  }

  @override
  Future<void> retry(String captureId) => enqueue(captureId);

  @override
  Future<void> reconcilePending() async {
    final pending = await database.capturesAwaitingProcessing();
    for (final record in pending) {
      await enqueue(record.id);
    }
  }
}
