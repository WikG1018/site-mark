import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_fullscreen_sequence.dart';
import 'package:sitemark/features/capture/capture_fullscreen_screen.dart';
import 'package:sitemark/features/capture/capture_image_preview.dart';
import 'package:sitemark/features/capture/capture_photo_hero.dart';
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

final class _AdjacentQuerySource implements CaptureQuerySource {
  final Completer<List<CaptureSummary>> newer = Completer();
  final Completer<List<CaptureSummary>> older = Completer();
  final List<
    ({CaptureListQuery query, CapturePageCursor cursor, bool newer, int limit})
  >
  calls = [];

  @override
  Future<List<CaptureSummary>> loadAdjacent(
    CaptureListQuery query,
    CapturePageCursor cursor, {
    required bool newer,
    int limit = 10,
  }) {
    calls.add((query: query, cursor: cursor, newer: newer, limit: limit));
    return newer ? this.newer.future : older.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PagedAdjacentQuerySource implements CaptureQuerySource {
  _PagedAdjacentQuerySource({required List<List<CaptureSummary>> olderPages})
    : _olderPages = List.of(olderPages);

  final List<List<CaptureSummary>> _olderPages;
  final List<({CapturePageCursor cursor, bool newer, int limit})> calls = [];

  @override
  Future<List<CaptureSummary>> loadAdjacent(
    CaptureListQuery query,
    CapturePageCursor cursor, {
    required bool newer,
    int limit = 10,
  }) async {
    calls.add((cursor: cursor, newer: newer, limit: limit));
    if (newer || _olderPages.isEmpty) return [];
    return _olderPages.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CaptureRecord _record({
  required String id,
  required CaptureStatus status,
  String? failureReason,
  DateTime? originalDeletedAt,
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
    originalDeletedAt: originalDeletedAt,
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

Future<CaptureFullscreenScreen> openAdjacentViewer(
  WidgetTester tester, {
  required CaptureRecord current,
  required CapturePreviewSource previewSource,
  required CaptureQuerySource querySource,
  required FutureOr<bool> Function(String path) fileExists,
}) async {
  await tester.pumpWidget(
    ProviderScope(
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
          body: SizedBox(
            width: 320,
            height: 240,
            child: CaptureImagePreview(
              capture: current,
              outputPaths: _FakeOutputPaths(),
              source: previewSource,
              navigationContext: CaptureNavigationContext(
                query: const CaptureListQuery(),
                cursor: (
                  sortTime: current.capturedAt ?? current.createdAt,
                  id: current.id,
                ),
              ),
              querySource: querySource,
              fileExists: fileExists,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  tester
      .widget<GestureDetector>(
        find.byKey(Key('capture-image-open-${current.id}')),
      )
      .onTap!();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pumpAndSettle();
  return tester.widget<CaptureFullscreenScreen>(
    find.byType(CaptureFullscreenScreen),
  );
}

Image previewImage(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image).first);

ResizeImage previewResizeImage(WidgetTester tester) =>
    previewImage(tester).image as ResizeImage;

String previewFilePath(WidgetTester tester) =>
    (previewResizeImage(tester).imageProvider as FileImage).file.path;

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

  testWidgets('Hero destination reuses flight decode without a second fade', (
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
              heroDestination: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final image = previewImage(tester);
    expect((image.image as ResizeImage).width, 2048);
    expect(image.gaplessPlayback, isTrue);
    expect(
      find.descendant(
        of: find.byType(CaptureImagePreview),
        matching: find.byType(AnimatedOpacity),
      ),
      findsNothing,
    );
  });

  testWidgets('Hero thumbnail shares the high-DPI flight cache key', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1200, 2400);
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
            width: 96,
            height: 96,
            child: CaptureImagePreview(
              capture: capture,
              outputPaths: _FakeOutputPaths(),
              thumbnail: true,
              heroTag: 'capture-photo-capture-1',
              fileExists: (_) => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(previewResizeImage(tester).width, 1200);
    expect(previewResizeImage(tester).height, isNull);
    expect(previewFilePath(tester), '/private/rendered/capture-1.jpg');
  });

  testWidgets(
    'Hero destination paints the list-resolved image before async lookup',
    (tester) async {
      final capture = _record(id: 'capture-1', status: CaptureStatus.ready);
      final paths = _DelayedOutputPaths();

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
                outputPaths: paths,
                heroDestination: true,
                initialImagePath: '/private/rendered/capture-1.jpg',
                fileExists: (_) => true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('失败'), findsNothing);

      paths.renderedPath.complete('/private/rendered/capture-1.jpg');
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'same-ID handoff path update paints the new path before lookup completes',
    (tester) async {
      final capture = _record(id: 'capture-1', status: CaptureStatus.ready);
      final paths = _DelayedOutputPaths();
      var initialPath = '/private/rendered/capture-1-a.jpg';
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
                return CaptureImagePreview(
                  capture: capture,
                  outputPaths: paths,
                  heroDestination: true,
                  initialImagePath: initialPath,
                  fileExists: (_) => true,
                );
              },
            ),
          ),
        ),
      );
      expect(previewFilePath(tester), '/private/rendered/capture-1-a.jpg');

      rebuild(() => initialPath = '/private/rendered/capture-1-b.jpg');
      await tester.pump();

      expect(previewFilePath(tester), '/private/rendered/capture-1-b.jpg');
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);

      paths.renderedPath.complete('/private/rendered/capture-1-b.jpg');
      await tester.pumpAndSettle();
    },
  );

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
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: CaptureFullscreenScreen.single(path: '/rendered/capture-1.jpg'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fullscreenImage = tester.widget<Image>(
      find.descendant(
        of: find.byType(InteractiveViewer),
        matching: find.byType(Image),
      ),
    );
    expect(fullscreenImage.image, isNot(isA<ResizeImage>()));
  });

  testWidgets('fullscreen opens current-only then loads adjacent query pages', (
    tester,
  ) async {
    final current = _record(id: 'capture-1', status: CaptureStatus.ready);
    final renderedSibling = _record(
      id: 'capture-2',
      status: CaptureStatus.ready,
    );
    final originalSibling = _record(
      id: 'capture-3',
      status: CaptureStatus.failed,
    );
    final source = _AdjacentQuerySource();
    const query = CaptureListQuery(searchText: '风管');
    final cursor = (
      sortTime: current.capturedAt ?? current.createdAt,
      id: current.id,
    );

    await tester.pumpWidget(
      ProviderScope(
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
            body: Center(
              child: SizedBox(
                width: 320,
                height: 240,
                child: CaptureImagePreview(
                  capture: current,
                  outputPaths: _FakeOutputPaths(),
                  navigationContext: CaptureNavigationContext(
                    query: query,
                    cursor: cursor,
                  ),
                  querySource: source,
                  fileExists: (path) {
                    return path == '/private/rendered/capture-1.jpg' ||
                        path == '/private/rendered/capture-2.jpg' ||
                        path == '/private/capture-3.jpg';
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester
        .widget<GestureDetector>(
          find.byKey(const Key('capture-image-open-capture-1')),
        )
        .onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    final viewer = tester.widget<CaptureFullscreenScreen>(
      find.byType(CaptureFullscreenScreen),
    );
    expect(viewer.sequence, isNotNull);
    expect(viewer.photos.map((photo) => photo.id), ['capture-1']);
    expect(source.calls, hasLength(2));
    expect(source.calls.every((call) => call.query == query), isTrue);
    expect(source.calls.every((call) => call.cursor == cursor), isTrue);
    expect(source.calls.every((call) => call.limit == 10), isTrue);

    source.newer.complete([]);
    source.older.complete([
      CaptureSummary(capture: renderedSibling, projectName: '项目'),
      CaptureSummary(capture: originalSibling, projectName: '项目'),
    ]);
    await tester.pump();
    await tester.pump();

    expect(
      await Future.wait(viewer.photos.map((photo) => photo.resolvePath())),
      [
        '/private/rendered/capture-1.jpg',
        '/private/rendered/capture-2.jpg',
        '/private/capture-3.jpg',
      ],
    );
    expect(viewer.initialIndex, 0);
  });

  testWidgets(
    'fullscreen skips missing rendered batches and advances the raw cursor',
    (tester) async {
      final current = _record(id: 'current', status: CaptureStatus.ready);
      final missing = [
        for (var index = 0; index < 10; index++)
          _record(id: 'missing-$index', status: CaptureStatus.ready),
      ];
      final valid = _record(id: 'valid', status: CaptureStatus.ready);
      final querySource = _PagedAdjacentQuerySource(
        olderPages: [
          missing
              .map(
                (capture) =>
                    CaptureSummary(capture: capture, projectName: '项目'),
              )
              .toList(growable: false),
          [CaptureSummary(capture: valid, projectName: '项目')],
        ],
      );
      final existsCalls = <String, int>{};
      final existing = {
        '/private/rendered/current.jpg',
        '/private/rendered/valid.jpg',
      };

      final viewer = await openAdjacentViewer(
        tester,
        current: current,
        previewSource: CapturePreviewSource.watermarked,
        querySource: querySource,
        fileExists: (path) {
          existsCalls.update(path, (count) => count + 1, ifAbsent: () => 1);
          return existing.contains(path);
        },
      );

      final olderCalls = querySource.calls
          .where((call) => !call.newer)
          .toList(growable: false);
      expect(olderCalls, hasLength(2));
      expect(olderCalls.last.cursor.id, 'missing-9');
      expect(viewer.photos.map((photo) => photo.id), ['current', 'valid']);
      final validPhoto = viewer.photos.singleWhere(
        (photo) => photo.id == 'valid',
      );
      final checksBeforeResolve = existsCalls['/private/rendered/valid.jpg'];
      expect(await validPhoto.resolvePath(), '/private/rendered/valid.jpg');
      expect(existsCalls['/private/rendered/valid.jpg'], checksBeforeResolve);
    },
  );

  testWidgets('fullscreen skips retained originals whose file is absent', (
    tester,
  ) async {
    final current = _record(id: 'current', status: CaptureStatus.ready);
    final missing = _record(id: 'missing', status: CaptureStatus.ready);
    final valid = _record(id: 'valid', status: CaptureStatus.ready);
    final querySource = _PagedAdjacentQuerySource(
      olderPages: [
        [
          CaptureSummary(capture: missing, projectName: '项目'),
          CaptureSummary(capture: valid, projectName: '项目'),
        ],
      ],
    );
    final existsCalls = <String, int>{};
    final existing = {'/private/current.jpg', '/private/valid.jpg'};

    final viewer = await openAdjacentViewer(
      tester,
      current: current,
      previewSource: CapturePreviewSource.original,
      querySource: querySource,
      fileExists: (path) {
        existsCalls.update(path, (count) => count + 1, ifAbsent: () => 1);
        return existing.contains(path);
      },
    );

    expect(viewer.photos.map((photo) => photo.id), ['current', 'valid']);
    final validPhoto = viewer.photos.singleWhere(
      (photo) => photo.id == 'valid',
    );
    final checksBeforeResolve = existsCalls['/private/valid.jpg'];
    expect(await validPhoto.resolvePath(), '/private/valid.jpg');
    expect(existsCalls['/private/valid.jpg'], checksBeforeResolve);
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

  testWidgets(
    'best available never falls back to an original marked as deleted',
    (tester) async {
      final capture = _record(
        id: 'capture-1',
        status: CaptureStatus.ready,
        originalDeletedAt: DateTime(2026, 7, 16, 10),
      );

      await pumpPreview(
        tester,
        capture: capture,
        renderedExists: false,
        originalExists: true,
      );

      expect(find.byKey(const Key('original-preview-capture-1')), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'initial deleted-original path is rejected before the first frame',
    (tester) async {
      final capture = _record(
        id: 'capture-1',
        status: CaptureStatus.ready,
        originalDeletedAt: DateTime(2026, 8, 4, 11),
      );

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
              initialImagePath: capture.originalPath,
              fileExists: (path) => path == capture.originalPath,
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('original-preview-capture-1')), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('original-preview-capture-1')), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    },
  );

  testWidgets('deleted original still accepts a rendered initial path', (
    tester,
  ) async {
    final capture = _record(
      id: 'capture-1',
      status: CaptureStatus.ready,
      originalDeletedAt: DateTime(2026, 8, 4, 11),
    );

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
            initialImagePath: '/private/rendered/capture-1.jpg',
            fileExists: (_) => true,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('rendered-preview-capture-1')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rendered-preview-capture-1')), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });

  testWidgets('same-ID logical deletion invalidates an original handoff', (
    tester,
  ) async {
    var capture = _record(id: 'capture-1', status: CaptureStatus.ready);
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
              return CaptureImagePreview(
                capture: capture,
                outputPaths: _FakeOutputPaths(),
                source: source,
                initialImagePath: capture.originalPath,
                fileExists: (path) => path == capture.originalPath,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('original-preview-capture-1')), findsOneWidget);

    rebuild(() {
      capture = _record(
        id: 'capture-1',
        status: CaptureStatus.ready,
        originalDeletedAt: DateTime(2026, 8, 4, 12),
      );
      source = CapturePreviewSource.watermarked;
    });
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('original-preview-capture-1')), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
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
    'detail preview keeps its Hero while file resolution is pending',
    (tester) async {
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
              heroTag: 'capture-photo-capture-1',
              fileExists: (path) => path == capture.originalPath
                  ? originalExists.future
                  : renderedExists.future,
            ),
          ),
        ),
      );
      await tester.pump();

      final hero = tester.widget<Hero>(find.byType(Hero));
      expect(hero.tag, 'capture-photo-capture-1');
    },
  );

  testWidgets('Hero thumbnail skips a second decoded-image fade', (
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
            outputPaths: _FakeOutputPaths(),
            thumbnail: true,
            heroTag: 'capture-photo-capture-1',
            fileExists: (path) => true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final hero = find.byType(CapturePhotoHero);
    expect(hero, findsOneWidget);
    expect(
      find.descendant(of: hero, matching: find.byType(AnimatedOpacity)),
      findsNothing,
    );
  });

  testWidgets('source change keeps the handoff image through delayed failure', (
    tester,
  ) async {
    final paths = _DelayedOutputPaths();
    final capture = _record(id: 'capture-1', status: CaptureStatus.ready);
    final originalExists = Completer<bool>();
    var source = CapturePreviewSource.watermarked;
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
                  initialImagePath: '/private/rendered/capture-1.jpg',
                  fileExists: (path) => path == capture.originalPath
                      ? originalExists.future
                      : true,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('rendered-preview-capture-1')), findsOneWidget);

    rebuild(() => source = CapturePreviewSource.original);
    await tester.pump();

    expect(find.byKey(const Key('rendered-preview-capture-1')), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);

    originalExists.complete(false);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('rendered-preview-capture-1')), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);

    paths.renderedPath.complete('/private/rendered/capture-1.jpg');
    await tester.pump();
  });

  testWidgets('disposing preview ignores a late path result', (tester) async {
    final paths = _DelayedOutputPaths();
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
        home: CaptureImagePreview(
          capture: capture,
          outputPaths: paths,
          initialImagePath: '/private/rendered/capture-1.jpg',
          fileExists: (_) => true,
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    paths.renderedPath.complete('/private/rendered/capture-1-late.jpg');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

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
