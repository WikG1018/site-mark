import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_image_preview.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';

/// Fake [CaptureOutputPaths] that resolves a deterministic rendered path used by
/// every preview test. The widget then asks [fileExists] whether that path (or
/// the original path) actually points at a file on disk.
class _FakeOutputPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async =>
      '/private/rendered/$captureId.jpg';
}

CaptureRecord _record({
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
    failureReason: failureReason,
    createdAt: DateTime(2026, 7, 16, 9, 30),
    capturedAt: DateTime(2026, 7, 16, 9, 32),
    processingAttempts: 0,
  );
}

/// Pumps [CaptureImagePreview] inside a [MaterialApp] with a controlled
/// [fileExists] predicate so tests do not depend on real disk files.
Future<void> pumpPreview(
  WidgetTester tester, {
  required CaptureRecord capture,
  required bool renderedExists,
  bool originalExists = true,
  bool thumbnail = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: CaptureImagePreview(
          capture: capture,
          outputPaths: _FakeOutputPaths(),
          thumbnail: thumbnail,
          fileExists: (path) {
            if (path == '/private/rendered/${capture.id}.jpg') {
              return renderedExists;
            }
            if (path == capture.originalPath) {
              return originalExists;
            }
            return false;
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ready preview uses rendered image and rendering uses original', (
    tester,
  ) async {
    final readyCapture = _record(id: 'capture-1', status: CaptureStatus.ready);
    await pumpPreview(tester, capture: readyCapture, renderedExists: true);
    expect(find.byKey(const Key('rendered-preview-capture-1')), findsOneWidget);
    expect(find.byKey(const Key('original-preview-capture-1')), findsNothing);

    final renderingCapture = _record(
      id: 'capture-1',
      status: CaptureStatus.rendering,
    );
    await pumpPreview(tester, capture: renderingCapture, renderedExists: true);
    expect(find.byKey(const Key('original-preview-capture-1')), findsOneWidget);
    expect(find.byKey(const Key('rendered-preview-capture-1')), findsNothing);
    expect(find.text('处理中'), findsOneWidget);
  });

  testWidgets('ready preview falls back to original when render missing', (
    tester,
  ) async {
    final readyCapture = _record(id: 'capture-1', status: CaptureStatus.ready);
    await pumpPreview(tester, capture: readyCapture, renderedExists: false);
    expect(find.byKey(const Key('original-preview-capture-1')), findsOneWidget);
    expect(find.byKey(const Key('rendered-preview-capture-1')), findsNothing);
  });

  testWidgets('failed capture shows original with failure overlay', (
    tester,
  ) async {
    final failedCapture = _record(
      id: 'capture-1',
      status: CaptureStatus.failed,
      failureReason: '渲染超时',
    );
    await pumpPreview(tester, capture: failedCapture, renderedExists: true);
    expect(find.byKey(const Key('original-preview-capture-1')), findsOneWidget);
    expect(find.text('失败'), findsOneWidget);
  });

  testWidgets('missing original shows a placeholder', (tester) async {
    final failedCapture = _record(
      id: 'capture-1',
      status: CaptureStatus.failed,
    );
    await pumpPreview(
      tester,
      capture: failedCapture,
      renderedExists: false,
      originalExists: false,
    );
    expect(find.byKey(const Key('original-preview-capture-1')), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });
}
