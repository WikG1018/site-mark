import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/original_photo_state.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_media_service.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

void main() {
  testWidgets('parent rebuild keeps the original-state result cached', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final media = _CountingMediaService(database);
    final summary = CaptureSummary(capture: _record(), projectName: '东区厂房改造');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          captureMediaServiceProvider.overrideWithValue(media),
          captureOutputPathsProvider.overrideWithValue(_CardOutputPaths()),
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
          home: Scaffold(body: _RebuildingCard(summary: summary)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('原图已保留'), findsOneWidget);
    expect(media.originalStateCalls, 1);

    await tester.tap(find.text('重建'));
    await tester.pumpAndSettle();

    expect(find.text('原图已保留'), findsOneWidget);
    expect(media.originalStateCalls, 1);
  });
}

class _RebuildingCard extends StatefulWidget {
  const _RebuildingCard({required this.summary});

  final CaptureSummary summary;

  @override
  State<_RebuildingCard> createState() => _RebuildingCardState();
}

class _RebuildingCardState extends State<_RebuildingCard> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(onPressed: () => setState(() {}), child: const Text('重建')),
        CaptureRecordCard(summary: widget.summary, onTap: () {}),
      ],
    );
  }
}

CaptureRecord _record() {
  return CaptureRecord(
    id: 'capture-1',
    projectId: 'project-1',
    photoNumber: 'SM-20260716-001',
    workLocation: 'A 区三层',
    workContent: '风管安装检查',
    photographer: '张工',
    originalPath: '/private/capture-1.jpg',
    status: CaptureStatus.ready,
    createdAt: DateTime(2026, 7, 16, 9, 30),
    capturedAt: DateTime(2026, 7, 16, 9, 32),
    processingAttempts: 0,
    watermarkLocaleCode: 'zh',
    locationResolution: 'resolved',
  );
}

class _CountingMediaService extends CaptureMediaService {
  _CountingMediaService(AppDatabase database)
    : super(
        database: database,
        platform: _CardPlatform(),
        outputPaths: _CardOutputPaths(),
        files: _CardFiles(),
      );

  int originalStateCalls = 0;

  @override
  Future<OriginalPhotoState> originalState(CaptureRecord record) async {
    originalStateCalls++;
    return OriginalPhotoState.retained;
  }
}

class _CardOutputPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/private/rendered/$captureId.jpg';
}

class _CardFiles implements PrivateFileStore {
  @override
  Future<void> deleteIfExists(String path) async {}

  @override
  Future<bool> exists(String path) async => true;
}

class _CardPlatform implements PlatformServices {
  @override
  Future<String> createCameraTarget(String captureId) =>
      throw UnsupportedError('not used');
  @override
  Future<void> deletePublishedImage(String contentUri) async {}
  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) async {}
  @override
  Future<LocationPermissionState> getLocationPermissionState() async =>
      LocationPermissionState.denied;
  @override
  Future<ImageMetadataResult> inspectImage(String path) =>
      throw UnsupportedError('not used');
  @override
  Future<CameraCaptureResult> launchCamera(String captureId) =>
      throw UnsupportedError('not used');
  @override
  Future<void> openApplicationSettings() async {}
  @override
  Future<String> publishJpeg(String sourcePath, String displayName) =>
      throw UnsupportedError('not used');
  @override
  Future<LocationPermissionState> requestLocationPermission() async =>
      LocationPermissionState.denied;
  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async =>
      LocationResult(outcome: LocationOutcome.permissionDenied);
  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async => null;
}
