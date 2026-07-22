import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
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
        locale: const Locale('zh'),
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
            onTap: () {},
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

CaptureRecord record({required String id, required CaptureStatus status}) {
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
  );
}

void main() {
  testWidgets('ready card pairs a Hero tag with the detail screen', (
    tester,
  ) async {
    await pumpCard(
      tester,
      capture: record(id: 'capture-1', status: CaptureStatus.ready),
    );
    expect(find.byType(Hero), findsOneWidget);
    expect(
      tester.widget<Hero>(find.byType(Hero)).tag,
      'capture-photo-capture-1',
    );
  });

  testWidgets('non-ready card renders no Hero', (tester) async {
    await pumpCard(
      tester,
      capture: record(id: 'capture-1', status: CaptureStatus.rendering),
    );
    expect(find.byType(Hero), findsNothing);
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

  testWidgets('selection mode expands the checkbox column with AnimatedSize', (
    tester,
  ) async {
    final selections = <bool>[];
    await pumpCard(
      tester,
      capture: record(id: 'capture-1', status: CaptureStatus.ready),
      selectionMode: true,
      onSelectedChanged: selections.add,
    );
    expect(
      find.descendant(
        of: find.byType(CaptureRecordCard),
        matching: find.byType(AnimatedSize),
      ),
      findsOneWidget,
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
      '/rendered/$captureId.jpg';
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
