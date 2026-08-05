import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/capture_failure.dart';
import 'package:sitemark/features/capture/capture_image_preview.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_media_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

/// Standalone harness for [CaptureRecordCard]: a real [CaptureMediaService]
/// backed by an in-memory database and a fake file store, mirroring the
/// detail-screen test setup. The card is pumped as the home body so taps and
/// long presses resolve without a surrounding list.
Future<void> pumpCard(
  WidgetTester tester, {
  required CaptureRecord capture,
  bool selectionMode = false,
  bool selected = false,
  bool selectable = true,
  ValueChanged<bool>? onSelectedChanged,
  ValueChanged<String?>? onTap,
  Locale locale = const Locale('zh'),
}) async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  final files = _CardFiles()..existing.add(capture.originalPath);
  final media = CaptureMediaService(
    database: database,
    platform: _CardPlatform(),
    outputPaths: _CardPaths(),
    files: files,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        captureOutputPathsProvider.overrideWithValue(_CardPaths()),
        captureMediaServiceProvider.overrideWithValue(media),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: CaptureRecordCard(
            summary: CaptureSummary(capture: capture, projectName: '东区厂房改造'),
            onTap: onTap ?? (_) {},
            selectionMode: selectionMode,
            selected: selected,
            selectable: selectable,
            onSelectedChanged: onSelectedChanged,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

CaptureRecord record({
  required String id,
  required CaptureStatus status,
  String? failureReason,
}) {
  return CaptureRecord(
    id: id,
    projectId: 'project-1',
    photoNumber: 'SM-20260716-001',
    workLocation: 'A 区三层',
    workContent: '风管安装检查',
    photographer: '张工',
    originalPath: '/private/$id.jpg',
    status: status,
    createdAt: DateTime(2026, 7, 16, 9, 30),
    capturedAt: DateTime(2026, 7, 16, 9, 32),
    processingAttempts: 0,
    watermarkLocaleCode: 'zh',
    locationResolution: 'resolved',
    failureReason: failureReason,
  );
}

void main() {
  testWidgets('ready card passes its photo tag to the preview', (tester) async {
    await pumpCard(
      tester,
      capture: record(id: 'capture-1', status: CaptureStatus.ready),
    );
    final preview = tester.widget<CaptureImagePreview>(
      find.byType(CaptureImagePreview),
    );
    expect(preview.heroTag, 'capture-photo-capture-1');
  });

  testWidgets('non-ready card does not pass a photo tag to the preview', (
    tester,
  ) async {
    await pumpCard(
      tester,
      capture: record(id: 'capture-1', status: CaptureStatus.rendering),
    );
    final preview = tester.widget<CaptureImagePreview>(
      find.byType(CaptureImagePreview),
    );
    expect(preview.heroTag, isNull);
  });

  testWidgets('failed card translates codes and hides legacy exception text', (
    tester,
  ) async {
    await pumpCard(
      tester,
      capture: record(
        id: 'capture-1',
        status: CaptureStatus.failed,
        failureReason: CaptureFailureCode.originalMissing.storageCode,
      ),
    );
    expect(find.textContaining('原图已缺失'), findsOneWidget);
    expect(find.textContaining('打开记录查看可用操作'), findsOneWidget);
    expect(find.textContaining('重试处理'), findsNothing);
    expect(find.textContaining('右上角菜单'), findsNothing);

    await pumpCard(
      tester,
      capture: record(
        id: 'capture-modified',
        status: CaptureStatus.failed,
        failureReason: CaptureFailureCode.originalModified.storageCode,
      ),
    );
    expect(find.textContaining('校验值不一致'), findsOneWidget);
    expect(find.textContaining('打开记录查看可用操作'), findsOneWidget);

    await pumpCard(
      tester,
      capture: record(
        id: 'capture-2',
        status: CaptureStatus.failed,
        failureReason: 'Bad state: native bridge exploded',
      ),
    );
    expect(find.textContaining('处理失败'), findsOneWidget);
    expect(find.textContaining('打开记录查看可用操作'), findsOneWidget);
    expect(find.textContaining('native bridge'), findsNothing);
  });

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets('failed card is actionable at 360dp and 2x text in '
        '${locale.languageCode}', (tester) async {
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      String? openedPath;

      await pumpCard(
        tester,
        locale: locale,
        capture: record(
          id: 'capture-failed',
          status: CaptureStatus.failed,
          failureReason: CaptureFailureCode.processingFailed.storageCode,
        ),
        onTap: (path) => openedPath = path,
      );

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining(
          locale.languageCode == 'zh'
              ? '打开记录查看可用操作'
              : 'Open the record to see available actions',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          locale.languageCode == 'zh' ? '点击“重新处理”' : 'Select Retry processing',
        ),
        findsNothing,
      );

      await tester.tap(find.byType(Card));
      expect(openedPath, '/private/capture-failed.jpg');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tap forwards the exact image path already shown by the card', (
    tester,
  ) async {
    String? tappedPath;
    await pumpCard(
      tester,
      capture: record(id: 'capture-1', status: CaptureStatus.ready),
      onTap: (path) => tappedPath = path,
    );

    await tester.tap(find.byType(Card));
    expect(tappedPath, '/private/capture-1.jpg');
  });

  testWidgets(
    'status area cross-fades and exposes one merged semantics label',
    (tester) async {
      await pumpCard(
        tester,
        capture: record(id: 'capture-1', status: CaptureStatus.ready),
      );
      final switchers = tester.widgetList<AnimatedSwitcher>(
        find.descendant(
          of: find.byType(CaptureRecordCard),
          matching: find.byType(AnimatedSwitcher),
        ),
      );
      expect(
        switchers.any(
          (switcher) =>
              switcher.child?.key == const ValueKey(CaptureStatus.ready),
        ),
        isTrue,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '状态: 已完成',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '照片 SM-20260716-001',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('long press enters selection and selects the card', (
    tester,
  ) async {
    final selections = <bool>[];
    await pumpCard(
      tester,
      capture: record(id: 'capture-1', status: CaptureStatus.ready),
      onSelectedChanged: selections.add,
    );
    await tester.longPress(find.byType(CaptureRecordCard));
    await tester.pump();
    expect(selections, [true]);
  });

  testWidgets('long press onLongPress is null in selection mode', (
    tester,
  ) async {
    await pumpCard(
      tester,
      capture: record(id: 'capture-1', status: CaptureStatus.ready),
      selectionMode: true,
    );
    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.onLongPress, isNull);
  });

  testWidgets('selection mode overlays the checkbox without shifting preview', (
    tester,
  ) async {
    final selections = <bool>[];
    final capture = record(id: 'capture-1', status: CaptureStatus.ready);
    await pumpCard(tester, capture: capture);
    final normalPreviewLeft = tester
        .getTopLeft(find.byType(CaptureImagePreview))
        .dx;

    await pumpCard(
      tester,
      capture: capture,
      selectionMode: true,
      onSelectedChanged: selections.add,
    );
    expect(find.byKey(const Key('capture-selection-overlay')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(CaptureImagePreview)).dx,
      normalPreviewLeft,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(selections, [true]);
  });
}

class _CardFiles implements PrivateFileStore {
  final Set<String> existing = {};
  @override
  Future<bool> exists(String path) async => existing.contains(path);
  @override
  Future<void> deleteIfExists(String path) async {
    existing.remove(path);
  }
}

class _CardPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/private/$captureId.jpg';
}

class _CardPlatform implements PlatformServices {
  @override
  Future<ImageMetadataResult> inspectImage(String path) async =>
      ImageMetadataResult(
        width: 4000,
        height: 3000,
        fileSizeBytes: 1_000_000,
        mimeType: 'image/jpeg',
      );
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
