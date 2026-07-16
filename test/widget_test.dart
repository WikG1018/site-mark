import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/main.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_processor.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';
import 'package:sitemark/src/rust/api/image_core.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('shows the project-first empty state', (tester) async {
    await tester.pumpWidget(
      MyApp(database: database, initialLocale: const Locale('zh')),
    );
    await tester.pumpAndSettle();

    expect(find.text('工程印记'), findsOneWidget);
    expect(find.text('还没有项目'), findsOneWidget);
    expect(find.text('新建项目'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('creates a project and returns to the project list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MyApp(database: database, initialLocale: const Locale('zh')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();

    expect(find.text('创建项目'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('project-name')), '东区厂房改造');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('东区厂房改造'), findsOneWidget);
    expect(find.text('还没有项目'), findsNothing);
    await disposeApp(tester);
  });

  testWidgets('ships an English interface', (tester) async {
    await tester.pumpWidget(
      MyApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    expect(find.text('SiteMark'), findsOneWidget);
    expect(find.text('No projects yet'), findsOneWidget);
    expect(find.text('New project'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('edits constrained project watermark settings', (tester) async {
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    await tester.pumpWidget(
      MyApp(database: database, initialLocale: const Locale('zh')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('东区厂房改造'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();

    expect(find.text('水印设置'), findsOneWidget);
    await tester.tap(find.text('右下'));
    await tester.tap(find.byKey(const Key('accent-blue')));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final project = await database.projectById('project-1');
    expect(project?.watermarkPosition, 'bottomRight');
    expect(project?.watermarkAccentColorArgb, 0xff1565c0);
    await disposeApp(tester);
  });

  testWidgets('captures a project record through the system camera workflow', (
    tester,
  ) async {
    final images = _WidgetTestImagePipeline();
    final share = _WidgetTestShareService();
    final platform = _WidgetTestPlatformServices();
    final outputPaths = _WidgetTestOutputPaths();
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    // A scheduler that runs the real CaptureProcessor inline so the widget test
    // observes the ready transition without a real WorkManager isolate.
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
        projectExportPaths: _WidgetTestProjectExportPaths(),
        shareService: share,
        privateFileStore: _WidgetTestPrivateFileStore(),
        backgroundScheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('东区厂房改造'));
    await tester.pumpAndSettle();
    expect(find.text('拍摄记录'), findsOneWidget);

    await tester.tap(find.text('拍摄'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('work-location')), 'A 区三层');
    await tester.enterText(find.byKey(const Key('work-content')), '风管安装检查');
    await tester.enterText(find.byKey(const Key('photographer')), '张工');
    await tester.tap(find.text('调用系统相机'));
    await tester.pumpAndSettle();

    expect(find.textContaining('SM-'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.archive_outlined));
    await tester.pumpAndSettle();
    expect(find.text('导出项目资料'), findsOneWidget);
    await tester.tap(find.text('生成并分享'));
    await tester.pumpAndSettle();
    expect(share.lastPath, '/exports/project-1.zip');

    await tester.tap(find.textContaining('SM-'));
    await tester.pumpAndSettle();
    expect(find.text('原图 SHA-256'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-work-location')),
      'B 区屋面',
    );
    await tester.enterText(
      find.byKey(const Key('edit-work-content')),
      '保温整改复查',
    );
    await tester.enterText(find.byKey(const Key('edit-photographer')), '李工');
    await tester.tap(find.text('重新生成水印'));
    await tester.pumpAndSettle();
    expect(find.textContaining('B 区屋面'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除记录'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(platform.deletedUri, 'content://media/site-mark/1');
    expect(find.text('暂无拍摄记录'), findsOneWidget);
    await disposeApp(tester);
  });
}

class _WidgetTestPlatformServices implements PlatformServices {
  String? deletedUri;

  @override
  Future<String> createCameraTarget(String captureId) async =>
      '/private/$captureId.jpg';

  @override
  Future<void> deletePublishedImage(String contentUri) async {
    deletedUri = contentUri;
  }

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
      'content://media/site-mark/1';

  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;

  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async {
    return LocationResult(outcome: LocationOutcome.permissionDenied);
  }
}

class _WidgetTestImagePipeline implements ImagePipeline {
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

class _WidgetTestOutputPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/private/rendered/$captureId.jpg';
}

class _WidgetTestProjectExportPaths implements ProjectExportPaths {
  @override
  Future<String> projectZipPath(String projectId) async =>
      '/exports/$projectId.zip';
}

class _WidgetTestShareService implements ShareFileService {
  String? lastPath;

  @override
  Future<void> shareFile(String path) async {
    lastPath = path;
  }
}

class _WidgetTestPrivateFileStore implements PrivateFileStore {
  @override
  Future<void> deleteIfExists(String path) async {}
}

/// A [CaptureBackgroundScheduler] that runs the real [CaptureProcessor] inline
/// on each enqueue/retry, simulating immediate WorkManager completion so widget
/// tests can observe the `ready` transition without a background isolate.
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
