import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitemark/background/capture_background_scheduler.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/release_check.dart';
import 'package:sitemark/features/settings/sections/about_section_screen.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/features/capture/capture_fullscreen_screen.dart';
import 'package:sitemark/features/settings/global_settings_screen.dart';
import 'package:sitemark/main.dart';
import 'package:sitemark/platform/notification_service.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/platform/app_update_controller.dart';

/// Synthetic local fixtures only. Exercises real Flutter navigation and image
/// decoding; it does not claim to test a manufacturer's camera or frame rate.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('visual navigation audit with real synthetic image bytes', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final directory = await Directory.systemTemp.createTemp(
      'sitemark-ui-audit-',
    );
    final image = await _fixtureImage(directory);
    await database.createProject(id: 'audit-project', name: '界面验收示例项目');
    await database.createProject(id: 'audit-empty', name: '空项目示例');
    for (var i = 0; i < 16; i++) {
      await database
          .into(database.captureRecords)
          .insert(
            CaptureRecordsCompanion.insert(
              id: 'audit-$i',
              projectId: 'audit-project',
              photoNumber: Value(
                '示例-SM-20261021-${(i + 1).toString().padLeft(3, '0')}',
              ),
              workLocation: '示例施工区域',
              workContent: '现场验收记录',
              photographer: '测试人员',
              originalPath: image,
              status: CaptureStatus.ready,
              createdAt: DateTime(2026, 10, 21, 10, i),
              capturedAt: Value(DateTime(2026, 10, 21, 10, i)),
            ),
          );
    }
    try {
      await tester.pumpWidget(
        MyApp(
          database: database,
          initialLocale: const Locale('zh'),
          outputPaths: _AuditOutputPaths(image),
          backgroundScheduler: _NoopScheduler(),
          completionNotificationService: _NoopNotifications(),
        ),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      Future<void> shot(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot(name);
      }

      await shot('01-projects');
      await tester.tap(find.byKey(const Key('root-destination-records')));
      await tester.pumpAndSettle();
      await shot('02-records');
      await tester.tap(find.byKey(const Key('edit-captures')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select-all-captures')));
      await tester.pumpAndSettle();
      await shot('03-selection');
      await tester.tap(find.byKey(const Key('select-all-captures')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-captures')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CaptureRecordCard).first);
      await shot('04-photo-detail');
      await tester.tap(find.byKey(const Key('capture-image-open-audit-15')));
      await shot('04a-fullscreen');
      expect(find.byType(CaptureFullscreenScreen), findsOneWidget);
      // Fullscreen deliberately starts without chrome; a photo tap shows it.
      await tester.tap(find.byType(CaptureFullscreenScreen));
      // Wait for the single/double-tap recognizer's decision, not just frames.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      expect(find.byType(CaptureFullscreenScreen), findsNothing);
      await tester.tap(find.byTooltip('返回').first);
      await tester.pumpAndSettle();
      expect(find.byType(CaptureRecordCard), findsWidgets);
      await tester.tap(find.byKey(const Key('root-destination-projects')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('界面验收示例项目'));
      await shot('05-project-detail');
      await tester.tap(find.byTooltip('返回').first);
      await shot('06-project-return');
      expect(find.byType(CaptureRecordCard), findsNothing);
      await tester.tap(find.byKey(const Key('root-destination-settings')));
      await tester.pumpAndSettle();
      final about = find.byKey(const Key('settings-entry-about'));
      await tester.scrollUntilVisible(
        about,
        300,
        scrollable: find.descendant(
          of: find.byType(GlobalSettingsScreen),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(about);
      await shot('07-about');
      final updates = ProviderScope.containerOf(
        tester.element(find.byType(AboutSectionScreen)),
      ).read(appUpdateControllerProvider);
      updates.download = ReleaseDownload(
        tag: 'v1.0.33',
        variant: ReleaseApkVariant.universal,
        sizeBytes: 80000000,
        sha256: 'a' * 64,
      );
      // Drive the real panel through its public cancellation action after
      // assigning synthetic progress. No network or installation is started.
      updates.phase = AppUpdatePhase.downloading;
      updates.receivedBytes = 40000000;
      await tester.tap(find.byTooltip('返回').first);
      await tester.pumpAndSettle();
      await tester.tap(about);
      await tester.pumpAndSettle();
      await shot('08-update-progress');
      await tester.tap(find.byKey(const Key('cancel-update-download')));
      await shot('09-update-cancelled');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}

Future<String> _fixtureImage(Directory directory) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 900, 600),
    Paint()..color = const Color(0xffd9e8e0),
  );
  for (var i = 0; i < 6; i++) {
    canvas.drawRect(
      Rect.fromLTWH(60 + i * 140, 80, 80, 360),
      Paint()..color = Color(0xff3a7262 + i * 0x060606),
    );
  }
  canvas.drawRect(
    const Rect.fromLTWH(30, 460, 360, 110),
    Paint()..color = const Color(0xbb12382c),
  );
  final text = TextPainter(
    text: const TextSpan(
      text: 'SiteMark · UI TEST\n2026-10-21 · synthetic fixture',
      style: TextStyle(color: Colors.white, fontSize: 22),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, const Offset(45, 480));
  text.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(900, 600);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${directory.path}/fixture.png');
  await file.writeAsBytes(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return file.path;
}

class _AuditOutputPaths implements CaptureOutputPaths {
  const _AuditOutputPaths(this.image);
  final String image;
  @override
  Future<String> renderedPhotoPath(String captureId) async => image;
}

class _NoopScheduler implements CaptureBackgroundScheduler {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> enqueue(String captureId) async {}
  @override
  Future<void> reconcilePending() async {}
  @override
  Future<void> retry(String captureId) async {}
}

class _NoopNotifications implements CompletionNotificationService {
  @override
  Future<void> initialize(void Function(String) onTapDeepLink) async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> setEnabled(bool enabled) async {}
  @override
  Future<void> setLocale(String? localeCode) async {}
  @override
  Future<void> showCaptureReady({
    required String projectId,
    required String captureId,
    required String photoNumber,
  }) async {}
  @override
  Future<void> showNasSyncFailed({
    required int failedCount,
    required String? failureCode,
  }) async {}
}
