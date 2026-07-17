import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/capture/capture_detail_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_media_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  late AppDatabase database;
  late _DetailFiles files;
  late _DetailPlatform platform;
  late _DetailPaths paths;
  late CaptureMediaService media;

  Future<void> pumpReadyDetail(
    WidgetTester tester, {
    required bool originalExists,
  }) async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.createProject(id: 'project-1', name: '东区厂房改造');
    final pending = await database.createPendingCapture(
      id: 'capture-1',
      projectId: 'project-1',
      originalPath: '/private/original.jpg',
      workLocation: 'A 区',
      workContent: '风管检查',
      photographer: '张工',
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    );
    await database.markCaptured(
      captureId: pending.id,
      capturedAt: DateTime(2026, 7, 16, 9),
    );
    await database.markRendering(
      captureId: pending.id,
      originalSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await database.markReady(
      captureId: pending.id,
      publishedUri: 'content://media/site-mark/1',
    );

    files = _DetailFiles();
    if (originalExists) files.existing.add('/private/original.jpg');
    files.existing.add('/rendered/capture-1.jpg');
    platform = _DetailPlatform()
      ..metadataByPath['/private/original.jpg'] = ImageMetadataResult(
        width: 4000,
        height: 3000,
        fileSizeBytes: 5_000_000,
        mimeType: 'image/jpeg',
      )
      ..metadataByPath['/rendered/capture-1.jpg'] = ImageMetadataResult(
        width: 4000,
        height: 3000,
        fileSizeBytes: 3_200_000,
        mimeType: 'image/jpeg',
      );
    paths = _DetailPaths();
    media = CaptureMediaService(
      database: database,
      platform: platform,
      outputPaths: paths,
      files: files,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          captureOutputPathsProvider.overrideWithValue(paths),
          captureMediaServiceProvider.overrideWithValue(media),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const CaptureDetailScreen(
            projectId: 'project-1',
            captureId: 'capture-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Disposes the widget tree by replacing it with an empty widget, then
  /// pumps a frame so the StreamBuilder subscription is cancelled before
  /// addTearDown closes the database. This avoids pending-timer assertions.
  Future<void> disposeDetail(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('detail shows both file sizes and original toggle', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    expect(find.text('4.8 MB'), findsOneWidget);
    expect(find.text('3.1 MB'), findsOneWidget);
    expect(find.byKey(const Key('show-original')), findsOneWidget);
    expect(find.byKey(const Key('delete-original')), findsOneWidget);
    expect(find.byKey(const Key('delete-all')), findsOneWidget);
    await disposeDetail(tester);
  });

  testWidgets('deleting original keeps detail and disables original preview', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    await tester.tap(find.byKey(const Key('delete-original')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除原图'));
    await tester.pumpAndSettle();
    expect(find.text('原图已清理'), findsOneWidget);
    expect(find.byKey(const Key('show-original')), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(await database.captureById('capture-1'), isNotNull);
    await disposeDetail(tester);
  });

  testWidgets('missing original is explicit and disables original actions', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: false);

    expect(find.text('原图缺失'), findsOneWidget);
    expect(find.byKey(const Key('show-original')), findsNothing);
    expect(find.byKey(const Key('delete-original')), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    await disposeDetail(tester);
  });

  testWidgets('failed original deletion reports failure instead of success', (
    tester,
  ) async {
    await pumpReadyDetail(tester, originalExists: true);
    files.deleteError = StateError('delete blocked');

    await tester.tap(find.byKey(const Key('delete-original')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除原图'));
    await tester.pumpAndSettle();

    expect(find.text('原图已清理'), findsNothing);
    expect(find.textContaining('delete blocked'), findsOneWidget);
    expect(
      (await database.captureById('capture-1'))?.originalDeletedAt,
      isNull,
    );

    await disposeDetail(tester);
  });
}

class _DetailFiles implements PrivateFileStore {
  final Set<String> existing = {};
  Object? deleteError;
  @override
  Future<bool> exists(String path) async => existing.contains(path);
  @override
  Future<void> deleteIfExists(String path) async {
    final error = deleteError;
    if (error != null) throw error;
    existing.remove(path);
  }
}

class _DetailPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/rendered/$captureId.jpg';
}

class _DetailPlatform implements PlatformServices {
  final Map<String, ImageMetadataResult> metadataByPath = {};
  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      metadataByPath[path]!;
  @override
  Future<void> deletePublishedImage(String contentUri) async {}
  @override
  Future<String> publishJpeg(String sourcePath, String displayName) async =>
      'content://media/site-mark/1';
  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      LocationPermissionState.denied;
  @override
  Future<LocationPermissionState> requestLocationPermission() async =>
      LocationPermissionState.denied;
  @override
  Future<void> openApplicationSettings() async {}
  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async =>
      LocationResult(outcome: LocationOutcome.permissionDenied);
  @override
  Future<String> createCameraTarget(String captureId) =>
      throw UnsupportedError('camera not used');
  @override
  Future<CameraCaptureResult> launchCamera(String captureId) =>
      throw UnsupportedError('camera not used');
  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;
  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}
}
