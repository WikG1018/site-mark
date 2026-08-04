import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/capture/capture_fullscreen_sequence.dart';
import 'package:sitemark/features/capture/capture_fullscreen_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// Host page that pushes [CaptureFullscreenScreen] the same way the detail
/// preview does, so pop-based dismissal lands back on a stable route. The
/// photo path intentionally does not exist: the viewer's errorBuilder renders
/// the broken-image placeholder while every gesture under test still targets
/// the surrounding viewer chrome.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CaptureFullscreenScreen.single(
                path: '/nonexistent-photo.jpg',
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

Future<void> pumpHost(WidgetTester tester) async {
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
        home: const _Host(),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.byType(CaptureFullscreenScreen), findsOneWidget);
}

double viewerScale(WidgetTester tester) {
  return tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();
}

Future<void> doubleTapViewer(WidgetTester tester) async {
  final target = find.byType(InteractiveViewer);
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tap(target);
  await tester.pumpAndSettle();
}

List<String> paintedFilePaths(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((image) => image.image)
    .whereType<FileImage>()
    .map((provider) => provider.file.path)
    .toList(growable: false);

void main() {
  testWidgets('fullscreen paints preview on its first black frame', (
    tester,
  ) async {
    final resolvedPath = Completer<String?>();
    final preview = MemoryImage(
      Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
          'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
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
          home: CaptureFullscreenScreen(
            photos: [
              CaptureFullscreenPhoto(
                id: 'capture-1',
                previewImage: preview,
                resolvePath: () => resolvedPath.future,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && identical(widget.image, preview),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);

    resolvedPath.completeError(StateError('resolution failed'));
    await tester.pump();
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && identical(widget.image, preview),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });

  testWidgets('deleted target file keeps preview instead of broken icon', (
    tester,
  ) async {
    final preview = MemoryImage(
      Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
          'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
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
          home: CaptureFullscreenScreen.single(
            path: '/deleted-after-open.jpg',
            previewImage: preview,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && identical(widget.image, preview),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });

  testWidgets('missing icon appears only without preview and resolved path', (
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
          home: CaptureFullscreenScreen(
            photos: [
              CaptureFullscreenPhoto(
                id: 'capture-1',
                resolvePath: () async => null,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows current immediately and prefetches both directions', (
    tester,
  ) async {
    final newer = Completer<List<CaptureFullscreenPhoto>>();
    final older = Completer<List<CaptureFullscreenPhoto>>();
    final calls = <CaptureFullscreenDirection>[];
    final sequence = CaptureFullscreenSequence(
      current: CaptureFullscreenPhoto.resolved(path: '/current.jpg'),
      loader: (direction, anchorId) {
        calls.add(direction);
        expect(anchorId, '/current.jpg');
        return direction == CaptureFullscreenDirection.newer
            ? newer.future
            : older.future;
      },
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
          home: CaptureFullscreenScreen.sequence(sequence: sequence),
        ),
      ),
    );

    expect(sequence.photos.map((photo) => photo.id), ['/current.jpg']);
    expect(
      find.byKey(const Key('fullscreen-photo-id-/current.jpg')),
      findsOneWidget,
    );
    expect(calls.toSet(), {
      CaptureFullscreenDirection.newer,
      CaptureFullscreenDirection.older,
    });

    newer.complete([]);
    older.complete([]);
    await tester.pump();
  });

  testWidgets('prepend preserves the exact visible page offset', (
    tester,
  ) async {
    final newer = Completer<List<CaptureFullscreenPhoto>>();
    final sequence = CaptureFullscreenSequence(
      current: CaptureFullscreenPhoto(
        id: 'current',
        initialPath: '/current.jpg',
        resolvePath: () async => '/current.jpg',
      ),
      loader: (direction, anchorId) {
        if (direction == CaptureFullscreenDirection.newer) {
          return newer.future;
        }
        return Future.value([
          for (var index = 0; index < 10; index++)
            CaptureFullscreenPhoto.resolved(path: '/older-$index.jpg'),
        ]);
      },
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
          home: CaptureFullscreenScreen.sequence(sequence: sequence),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(sequence.photos.length, 11);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    final pageBefore = controller.page!;
    expect(pageBefore, greaterThan(0));
    expect(pageBefore, lessThan(1));

    newer.complete([
      CaptureFullscreenPhoto.resolved(path: '/newer-2.jpg'),
      CaptureFullscreenPhoto.resolved(path: '/newer-1.jpg'),
    ]);
    await tester.pump();

    expect(controller.page, closeTo(pageBefore + 2, 0.001));
    expect(sequence.currentId, 'current');
    expect(
      find.byKey(const Key('fullscreen-photo-id-current')),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('ballistic prepend freezes the corrected visible photo', (
    tester,
  ) async {
    final newer = Completer<List<CaptureFullscreenPhoto>>();
    final sequence = CaptureFullscreenSequence(
      current: CaptureFullscreenPhoto(
        id: 'current',
        initialPath: '/current.jpg',
        resolvePath: () async => '/current.jpg',
      ),
      loader: (direction, anchorId) {
        if (direction == CaptureFullscreenDirection.newer) {
          return newer.future;
        }
        return Future.value([
          for (var index = 0; index < 10; index++)
            CaptureFullscreenPhoto(
              id: 'older-$index',
              resolvePath: () async => '/older-$index.jpg',
            ),
        ]);
      },
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
          home: CaptureFullscreenScreen.sequence(sequence: sequence),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final pageController = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    final currentTransform = tester
        .widget<InteractiveViewer>(
          find.descendant(
            of: find.byKey(const Key('fullscreen-photo-id-current')),
            matching: find.byType(InteractiveViewer),
          ),
        )
        .transformationController!;
    final transformBefore = List<double>.of(currentTransform.value.storage);

    await tester.fling(find.byType(PageView), const Offset(-180, 0), 1000);
    final pageBeforePrepend = pageController.page!;
    expect(pageBeforePrepend, greaterThan(0));
    expect(pageBeforePrepend, lessThan(1));
    final visibleIdBefore = sequence.currentId;

    newer.complete([
      CaptureFullscreenPhoto(
        id: 'newer-2',
        resolvePath: () async => '/newer-2.jpg',
      ),
      CaptureFullscreenPhoto(
        id: 'newer-1',
        resolvePath: () async => '/newer-1.jpg',
      ),
    ]);
    await tester.pump();
    final correctedPage = pageBeforePrepend + 2;
    expect(pageController.page, closeTo(correctedPage, 0.001));
    expect(sequence.currentId, visibleIdBefore);
    expect(currentTransform.value.storage, orderedEquals(transformBefore));

    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(pageController.page, closeTo(correctedPage, 0.001));
      expect(sequence.currentId, visibleIdBefore);
      expect(currentTransform.value.storage, orderedEquals(transformBefore));
    }
  });

  testWidgets('an edge failure exposes only that edge retry', (tester) async {
    var olderAttempts = 0;
    final sequence = CaptureFullscreenSequence(
      current: CaptureFullscreenPhoto.resolved(path: '/current.jpg'),
      loader: (direction, anchorId) async {
        if (direction == CaptureFullscreenDirection.newer) return [];
        olderAttempts++;
        if (olderAttempts == 1) throw StateError('temporary failure');
        return [CaptureFullscreenPhoto.resolved(path: '/older.jpg')];
      },
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
          home: CaptureFullscreenScreen.sequence(sequence: sequence),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('fullscreen-older-retry')), findsOneWidget);
    expect(find.byKey(const Key('fullscreen-newer-retry')), findsNothing);
    expect(sequence.photos.map((photo) => photo.id), ['/current.jpg']);

    await tester.tap(find.byKey(const Key('fullscreen-older-retry')));
    await tester.pump();
    expect(olderAttempts, 2);
    expect(sequence.photos.map((photo) => photo.id), [
      '/current.jpg',
      '/older.jpg',
    ]);
  });

  testWidgets('requests another batch at two photos from the older edge', (
    tester,
  ) async {
    final nextOlder = Completer<List<CaptureFullscreenPhoto>>();
    var olderCalls = 0;
    final anchors = <String>[];
    final sequence = CaptureFullscreenSequence(
      current: CaptureFullscreenPhoto.resolved(path: '/current.jpg'),
      loader: (direction, anchorId) {
        if (direction == CaptureFullscreenDirection.newer) {
          return Future.value([]);
        }
        olderCalls++;
        anchors.add(anchorId);
        if (olderCalls == 1) {
          return Future.value([
            for (var index = 0; index < 10; index++)
              CaptureFullscreenPhoto.resolved(path: '/older-$index.jpg'),
          ]);
        }
        return nextOlder.future;
      },
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
          home: CaptureFullscreenScreen.sequence(sequence: sequence),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;

    controller.jumpToPage(7);
    await tester.pump();
    expect(olderCalls, 1);

    controller.jumpToPage(8);
    await tester.pump();
    expect(olderCalls, 2);
    expect(anchors.last, '/older-9.jpg');

    controller.jumpToPage(9);
    controller.jumpToPage(10);
    await tester.pump();
    expect(olderCalls, 2);

    nextOlder.complete([]);
    await tester.pump();
  });

  testWidgets('continues past a full batch of skipped adjacent rows', (
    tester,
  ) async {
    var olderCalls = 0;
    final sequence = CaptureFullscreenSequence(
      current: CaptureFullscreenPhoto(
        id: 'current',
        resolvePath: () async => '/current.jpg',
      ),
      loader: (direction, anchorId) async {
        if (direction == CaptureFullscreenDirection.newer) return [];
        olderCalls++;
        if (olderCalls == 1) {
          return [
            for (var index = 0; index < 10; index++)
              CaptureFullscreenPhoto(
                id: 'deleted-$index',
                includeInSequence: false,
                resolvePath: () async => null,
              ),
          ];
        }
        return [CaptureFullscreenPhoto.resolved(path: '/older.jpg')];
      },
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
          home: CaptureFullscreenScreen.sequence(sequence: sequence),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(olderCalls, 2);
    expect(sequence.photos.map((photo) => photo.id), ['current', '/older.jpg']);
  });

  testWidgets('replacing the sequence ignores the old query completion', (
    tester,
  ) async {
    final oldNewer = Completer<List<CaptureFullscreenPhoto>>();
    final oldOlder = Completer<List<CaptureFullscreenPhoto>>();
    final oldSequence = CaptureFullscreenSequence(
      current: CaptureFullscreenPhoto(
        id: 'old-current',
        resolvePath: () async => '/old-current.jpg',
      ),
      loader: (direction, anchorId) =>
          direction == CaptureFullscreenDirection.newer
          ? oldNewer.future
          : oldOlder.future,
    );
    final newSequence = CaptureFullscreenSequence(
      current: CaptureFullscreenPhoto(
        id: 'new-current',
        resolvePath: () async => '/new-current.jpg',
      ),
      loader: (direction, anchorId) async => [],
    );
    final selected = ValueNotifier(oldSequence);
    addTearDown(selected.dispose);

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
          home: ValueListenableBuilder<CaptureFullscreenSequence>(
            valueListenable: selected,
            builder: (context, sequence, _) => CaptureFullscreenScreen.sequence(
              key: const Key('dynamic-viewer'),
              sequence: sequence,
            ),
          ),
        ),
      ),
    );
    selected.value = newSequence;
    await tester.pump();

    oldNewer.complete([CaptureFullscreenPhoto.resolved(path: '/stale.jpg')]);
    oldOlder.complete([]);
    await tester.pump();

    expect(oldSequence.photos.map((photo) => photo.id), ['old-current']);
    expect(
      find.byKey(const Key('fullscreen-photo-id-new-current')),
      findsOneWidget,
    );
  });

  testWidgets('same-ID sequence replacement resets path and zoom state', (
    tester,
  ) async {
    final oldPath = Completer<String?>();
    final newPath = Completer<String?>();
    final oldSequence = CaptureFullscreenSequence(
      current: CaptureFullscreenPhoto(
        id: 'same-id',
        initialPath: '/source-a.jpg',
        resolvePath: () => oldPath.future,
      ),
      loader: (direction, anchorId) async => [],
    );
    final newSequence = CaptureFullscreenSequence(
      current: CaptureFullscreenPhoto(
        id: 'same-id',
        resolvePath: () => newPath.future,
      ),
      loader: (direction, anchorId) async => [],
    );
    final selected = ValueNotifier(oldSequence);
    addTearDown(selected.dispose);

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
          home: ValueListenableBuilder<CaptureFullscreenSequence>(
            valueListenable: selected,
            builder: (context, sequence, _) => CaptureFullscreenScreen.sequence(
              key: const Key('same-id-viewer'),
              sequence: sequence,
            ),
          ),
        ),
      ),
    );
    final oldController = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    oldController.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );

    selected.value = newSequence;
    await tester.pump();

    final newController = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    expect(newController, isNot(same(oldController)));
    expect(
      newController.value.storage,
      orderedEquals(Matrix4.identity().storage),
    );
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<PageScrollPhysics>(),
    );
    expect(paintedFilePaths(tester), isNot(contains('/source-a.jpg')));

    oldPath.complete('/source-a-late.jpg');
    await tester.pump();
    expect(
      paintedFilePaths(tester),
      isNot(anyOf(contains('/source-a.jpg'), contains('/source-a-late.jpg'))),
    );

    newPath.complete('/source-b.jpg');
    await tester.pump();
    await tester.pump();
    expect(paintedFilePaths(tester), contains('/source-b.jpg'));
    expect(
      paintedFilePaths(tester),
      isNot(anyOf(contains('/source-a.jpg'), contains('/source-a-late.jpg'))),
    );
  });

  testWidgets('disposing the viewer ignores pending adjacent results', (
    tester,
  ) async {
    final newer = Completer<List<CaptureFullscreenPhoto>>();
    final older = Completer<List<CaptureFullscreenPhoto>>();
    final sequence = CaptureFullscreenSequence(
      current: CaptureFullscreenPhoto(
        id: 'current',
        resolvePath: () async => '/current.jpg',
      ),
      loader: (direction, anchorId) =>
          direction == CaptureFullscreenDirection.newer
          ? newer.future
          : older.future,
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
          home: CaptureFullscreenScreen.sequence(sequence: sequence),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    newer.complete([CaptureFullscreenPhoto.resolved(path: '/stale.jpg')]);
    older.complete([]);
    await tester.pump();

    expect(sequence.photos.map((photo) => photo.id), ['current']);
  });

  testWidgets('cached detail preview remains behind full-resolution decode', (
    tester,
  ) async {
    final preview = MemoryImage(
      Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
          'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
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
          home: CaptureFullscreenScreen.single(
            path: '/nonexistent-photo.jpg',
            previewImage: preview,
          ),
        ),
      ),
    );

    final previewImages = tester.widgetList<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && identical(widget.image, preview),
      ),
    );
    expect(previewImages, hasLength(1));
    expect(previewImages.single.gaplessPlayback, isTrue);

    final fullImage = tester
        .widgetList<Image>(find.byType(Image))
        .firstWhere((image) => !identical(image.image, preview));
    expect(fullImage.frameBuilder, isNotNull);
  });

  testWidgets('opens at the requested photo and swipes to the next one', (
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
          home: CaptureFullscreenScreen.fromPaths(
            paths: ['/first.jpg', '/second.jpg', '/third.jpg'],
            initialIndex: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller!.page, 1);
    expect(find.byKey(const Key('fullscreen-photo-1')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('fullscreen-photo-1')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    expect(pageView.controller!.page, 2);
    expect(find.byKey(const Key('fullscreen-photo-2')), findsOneWidget);
  });

  testWidgets('double tap zooms to 2x and back to 1x', (tester) async {
    await pumpHost(tester);
    expect(viewerScale(tester), closeTo(1, 0.001));
    expect(find.bySemanticsLabel('全屏查看照片'), findsOneWidget);

    await doubleTapViewer(tester);
    expect(viewerScale(tester), closeTo(2, 0.001));

    await doubleTapViewer(tester);
    expect(viewerScale(tester), closeTo(1, 0.001));
  });

  testWidgets('reduce motion applies double-tap zoom without animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: CaptureFullscreenScreen.single(path: '/photo.jpg'),
        ),
      ),
    );

    final target = find.byType(InteractiveViewer);
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(target);
    await tester.pump();

    expect(viewerScale(tester), closeTo(2, 0.001));
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('vertical drag past the threshold dismisses the viewer', (
    tester,
  ) async {
    await pumpHost(tester);
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureFullscreenScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('fast fling below the distance threshold still dismisses', (
    tester,
  ) async {
    await pumpHost(tester);
    await tester.fling(
      find.byType(InteractiveViewer),
      const Offset(0, 80),
      1500,
    );
    await tester.pumpAndSettle();
    expect(find.byType(CaptureFullscreenScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('short drag animates back instead of dismissing', (tester) async {
    await pumpHost(tester);
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureFullscreenScreen), findsOneWidget);
  });

  testWidgets('tap toggles chrome and the close button pops', (tester) async {
    await pumpHost(tester);
    final chrome = find.byKey(const Key('fullscreen-chrome'));
    expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);

    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(chrome).opacity, 1);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureFullscreenScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
