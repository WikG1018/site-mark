import 'dart:async';

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

class _CountingOutputPaths implements CaptureOutputPaths {
  int requests = 0;

  @override
  Future<String> renderedPhotoPath(String captureId) async {
    requests++;
    return '/private/rendered/$captureId.jpg';
  }
}

class _RebuildingPreview extends StatefulWidget {
  const _RebuildingPreview({
    required this.capture,
    required this.outputPaths,
    required this.fileExists,
  });

  final CaptureRecord capture;
  final CaptureOutputPaths outputPaths;
  final FutureOr<bool> Function(String path) fileExists;

  @override
  State<_RebuildingPreview> createState() => _RebuildingPreviewState();
}

class _RebuildingPreviewState extends State<_RebuildingPreview> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(onPressed: () => setState(() {}), child: const Text('重建')),
        SizedBox(
          width: 96,
          height: 96,
          child: CaptureImagePreview(
            capture: widget.capture,
            outputPaths: widget.outputPaths,
            thumbnail: true,
            fileExists: widget.fileExists,
          ),
        ),
      ],
    );
  }
}

class _DelayedOutputPaths implements CaptureOutputPaths {
  final Completer<String> renderedPath = Completer<String>();

  @override
  Future<String> renderedPhotoPath(String captureId) => renderedPath.future;
}

class _ThrowingOutputPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) =>
      Future.error(StateError('rendered path unavailable'));
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
    watermarkLocaleCode: 'zh',
    locationResolution: 'resolved',
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

Image previewImage(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image).first);

ResizeImage previewResizeImage(WidgetTester tester) =>
    previewImage(tester).image as ResizeImage;

void main() {
  testWidgets('thumbnail preview keeps a 192 pixel cache dimension', (
    tester,
  ) async {
    final capture = _record(id: 'capture-1', status: CaptureStatus.ready);

    await pumpPreview(
      tester,
      capture: capture,
      renderedExists: true,
      thumbnail: true,
    );

    final image = previewResizeImage(tester);
    expect(image.width, 192);
    expect(image.height, 192);
  });

  testWidgets('detail preview bounds cache width to layout width and DPR', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = _record(id: 'capture-1', status: CaptureStatus.ready);

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
          body: SizedBox(
            width: 360,
            height: 240,
            child: CaptureImagePreview(
              capture: capture,
              outputPaths: _FakeOutputPaths(),
              fileExists: (path) => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final image = previewResizeImage(tester);
    expect(image.width, 900);
    expect(image.height, isNull);
  });

  testWidgets('detail preview caps its cache width at 2048 pixels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = _record(id: 'capture-1', status: CaptureStatus.ready);

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
          body: SizedBox(
            width: 1000,
            height: 240,
            child: CaptureImagePreview(
              capture: capture,
              outputPaths: _FakeOutputPaths(),
              fileExists: (path) => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(previewResizeImage(tester).width, 2048);
  });

  testWidgets('detail preview uses media width for an unbounded layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final capture = _record(id: 'capture-1', status: CaptureStatus.ready);

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
          body: UnconstrainedBox(
            child: SizedBox(
              height: 240,
              child: CaptureImagePreview(
                capture: capture,
                outputPaths: _FakeOutputPaths(),
                fileExists: (path) => true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(previewResizeImage(tester).width, 800);
  });

  testWidgets('detail preview uses media width for a zero-width layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final capture = _record(id: 'capture-1', status: CaptureStatus.ready);

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
          body: SizedBox(
            width: 0,
            height: 240,
            child: CaptureImagePreview(
              capture: capture,
              outputPaths: _FakeOutputPaths(),
              fileExists: (path) => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(previewResizeImage(tester).width, 800);
  });

  testWidgets('fullscreen preview keeps full-resolution decoding', (
    tester,
  ) async {
    final capture = _record(id: 'capture-1', status: CaptureStatus.ready);
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
          body: SizedBox(
            width: 360,
            height: 240,
            child: CaptureImagePreview(
              capture: capture,
              outputPaths: _FakeOutputPaths(),
              fileExists: (path) => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rendered-preview-capture-1')));
    await tester.pumpAndSettle();

    final fullscreenImage = tester.widget<Image>(
      find.descendant(
        of: find.byType(InteractiveViewer),
        matching: find.byType(Image),
      ),
    );
    expect(fullscreenImage.image, isNot(isA<ResizeImage>()));
  });

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

  testWidgets('parent rebuild keeps the resolved preview without re-reading', (
    tester,
  ) async {
    final capture = _record(id: 'capture-1', status: CaptureStatus.ready);
    final paths = _CountingOutputPaths();
    var fileChecks = 0;

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
          body: _RebuildingPreview(
            capture: capture,
            outputPaths: paths,
            fileExists: (path) {
              fileChecks++;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rendered-preview-capture-1')), findsOneWidget);
    expect(paths.requests, 1);
    expect(fileChecks, 2);

    await tester.tap(find.text('重建'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rendered-preview-capture-1')), findsOneWidget);
    expect(paths.requests, 1);
    expect(fileChecks, 2);
  });

  testWidgets('loading async file checks shows a stable placeholder', (
    tester,
  ) async {
    final originalExists = Completer<bool>();
    final renderedExists = Completer<bool>();
    final capture = _record(id: 'capture-1', status: CaptureStatus.ready);

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
            thumbnail: true,
            fileExists: (path) => path == capture.originalPath
                ? originalExists.future
                : renderedExists.future,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);

    originalExists.complete(true);
    renderedExists.complete(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rendered-preview-capture-1')), findsOneWidget);
  });

  testWidgets(
    'source change hides the previous image until delayed resolution',
    (tester) async {
      final paths = _DelayedOutputPaths();
      final capture = _record(id: 'capture-1', status: CaptureStatus.ready);
      var source = CapturePreviewSource.original;
      late StateSetter rebuild;

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
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return SizedBox(
                  width: 96,
                  height: 96,
                  child: CaptureImagePreview(
                    capture: capture,
                    outputPaths: paths,
                    thumbnail: true,
                    source: source,
                    fileExists: (path) => true,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('original-preview-capture-1')),
        findsOneWidget,
      );

      rebuild(() => source = CapturePreviewSource.watermarked);
      await tester.pump();

      expect(find.byKey(const Key('original-preview-capture-1')), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);

      paths.renderedPath.complete('/private/rendered/capture-1.jpg');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('rendered-preview-capture-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'capture change hides the previous image until delayed resolution',
    (tester) async {
      final paths = _DelayedOutputPaths();
      var capture = _record(id: 'capture-1', status: CaptureStatus.failed);
      late StateSetter rebuild;

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
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return SizedBox(
                  width: 96,
                  height: 96,
                  child: CaptureImagePreview(
                    capture: capture,
                    outputPaths: paths,
                    thumbnail: true,
                    fileExists: (path) => true,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('original-preview-capture-1')),
        findsOneWidget,
      );

      rebuild(
        () => capture = _record(id: 'capture-2', status: CaptureStatus.ready),
      );
      await tester.pump();

      expect(find.byKey(const Key('original-preview-capture-1')), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);

      paths.renderedPath.complete('/private/rendered/capture-2.jpg');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('rendered-preview-capture-2')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ready preview falls back to original when rendered resolution throws',
    (tester) async {
      final capture = _record(id: 'capture-1', status: CaptureStatus.ready);
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
              outputPaths: _ThrowingOutputPaths(),
              thumbnail: true,
              fileExists: (path) => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('original-preview-capture-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('explicit sources convert errors into existing placeholders', (
    tester,
  ) async {
    final capture = _record(id: 'capture-1', status: CaptureStatus.ready);
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
            outputPaths: _ThrowingOutputPaths(),
            thumbnail: true,
            source: CapturePreviewSource.watermarked,
            fileExists: (path) => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('成片尚未生成'), findsOneWidget);

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
            thumbnail: true,
            source: CapturePreviewSource.original,
            fileExists: (path) => Future<bool>.error(StateError('read failed')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('原图缺失'), findsOneWidget);
  });
}
