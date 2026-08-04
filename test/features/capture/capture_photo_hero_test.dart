import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/data/capture_query_repository.dart';
import 'package:sitemark/domain/capture_list_query.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/features/capture/capture_image_preview.dart';
import 'package:sitemark/features/capture/capture_photo_hero.dart';
import 'package:sitemark/features/capture/capture_record_card.dart';
import 'package:sitemark/features/capture/capture_fullscreen_sequence.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/capture_media_service.dart';

final class _RouteOutputPaths implements CaptureOutputPaths {
  _RouteOutputPaths(this.initialPath);

  final String initialPath;
  final Completer<String> detailPath = Completer<String>();
  int calls = 0;

  @override
  Future<String> renderedPhotoPath(String captureId) {
    calls++;
    return calls == 1 ? Future.value(initialPath) : detailPath.future;
  }
}

final class _HeroFiles implements PrivateFileStore {
  const _HeroFiles(this.existingPath);

  final String existingPath;

  @override
  Future<bool> exists(String path) async => path == existingPath;

  @override
  Future<void> deleteIfExists(String path) async {}
}

final class _HeroPlatform implements PlatformServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NoAdjacentQuerySource implements CaptureQuerySource {
  @override
  Future<List<CaptureSummary>> loadAdjacent(
    CaptureListQuery query,
    CapturePageCursor cursor, {
    required bool newer,
    int limit = 10,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CaptureRecord _readyRecord(String path) => CaptureRecord(
  id: 'capture-1',
  projectId: 'project-1',
  photoNumber: 'SM-20260804-001',
  workLocation: 'A 区三层',
  workContent: '风管安装检查',
  photographer: '张工',
  originalPath: path,
  status: CaptureStatus.ready,
  createdAt: DateTime(2026, 8, 4, 9, 30),
  capturedAt: DateTime(2026, 8, 4, 9, 32),
  processingAttempts: 0,
  watermarkLocaleCode: 'zh',
  locationResolution: 'resolved',
);

bool hasDecodedImage(WidgetTester tester, Finder ancestor) => tester
    .widgetList<RawImage>(
      find.descendant(of: ancestor, matching: find.byType(RawImage)),
    )
    .any((image) => image.image != null);

Future<void> pumpDecodedFileFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory temporaryDirectory;
  late String photoPath;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'sitemark-photo-hero-',
    );
    final file = File('${temporaryDirectory.path}/photo.png');
    await file.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    photoPath = file.path;
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> pumpHeroPair(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                key: const Key('open-hero-detail'),
                onTap: () => Navigator.of(context).push(
                  PageRouteBuilder<void>(
                    transitionDuration: const Duration(milliseconds: 240),
                    reverseTransitionDuration: const Duration(
                      milliseconds: 240,
                    ),
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        Scaffold(
                          appBar: AppBar(),
                          body: Center(
                            child: SizedBox(
                              width: 320,
                              height: 240,
                              child: CapturePhotoHero(
                                tag: 'capture-photo-test',
                                path: photoPath,
                                child: Image.file(
                                  File(photoPath),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
                child: SizedBox(
                  key: const Key('record-thumbnail'),
                  width: 96,
                  height: 96,
                  child: CapturePhotoHero(
                    tag: 'capture-photo-test',
                    path: photoPath,
                    child: KeyedSubtree(
                      key: const Key('record-thumbnail-content'),
                      child: Image.file(File(photoPath), fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<
    ({
      GoRouter router,
      _RouteOutputPaths paths,
      CaptureNavigationContext navigationContext,
    })
  >
  pumpRecordToDetailRoute(WidgetTester tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final capture = _readyRecord(photoPath);
    final paths = _RouteOutputPaths(photoPath);
    final navigationContext = CaptureNavigationContext(
      query: const CaptureListQuery(),
      cursor: (sortTime: capture.capturedAt!, id: capture.id),
    );
    final media = CaptureMediaService(
      database: database,
      platform: _HeroPlatform(),
      outputPaths: paths,
      files: _HeroFiles(photoPath),
    );
    final querySource = _NoAdjacentQuerySource();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: CaptureRecordCard(
              key: const Key('record-card'),
              summary: CaptureSummary(capture: capture, projectName: '东区厂房改造'),
              onTap: (initialImagePath) =>
                  context.push('/detail', extra: initialImagePath),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) => Scaffold(
            appBar: AppBar(),
            body: Center(
              child: SizedBox(
                width: 320,
                height: 240,
                child: Hero(
                  tag: 'capture-photo-${capture.id}',
                  child: CaptureImagePreview(
                    key: const Key('detail-preview'),
                    capture: capture,
                    outputPaths: paths,
                    heroDestination: true,
                    initialImagePath: state.extra as String?,
                    fileExists: (_) => true,
                    navigationContext: navigationContext,
                    querySource: querySource,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          captureOutputPathsProvider.overrideWithValue(paths),
          captureMediaServiceProvider.overrideWithValue(media),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pumpDecodedFileFrames(tester);
    expect(
      hasDecodedImage(tester, find.byKey(const Key('record-card'))),
      isTrue,
    );
    return (router: router, paths: paths, navigationContext: navigationContext);
  }

  testWidgets('hero flight uses a gapless stable image without frame fade', (
    tester,
  ) async {
    await pumpHeroPair(tester);
    await tester.tap(find.byKey(const Key('open-hero-detail')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final flight = find.byKey(const Key('capture-photo-hero-flight'));
    expect(flight, findsOneWidget);
    final images = tester.widgetList<Image>(
      find.descendant(of: flight, matching: find.byType(Image)),
    );
    expect(images, isNotEmpty);
    expect(images.every((image) => image.gaplessPlayback), isTrue);
    expect(
      find.descendant(of: flight, matching: find.byType(AnimatedOpacity)),
      findsNothing,
    );
    expect(
      find.descendant(of: flight, matching: find.byType(AnimatedSwitcher)),
      findsNothing,
    );
  });

  testWidgets('record route keeps decoded pixels through forward handoff', (
    tester,
  ) async {
    final harness = await pumpRecordToDetailRoute(tester);
    await tester.tap(find.byKey(const Key('record-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final flight = find.byKey(const Key('capture-photo-hero-flight'));
    expect(flight, findsOneWidget);
    expect(hasDecodedImage(tester, flight), isTrue);

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capture-photo-hero-flight')), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    final detail = find.byKey(const Key('detail-preview'));
    expect(detail, findsOneWidget);
    expect(hasDecodedImage(tester, detail), isTrue);
    expect(
      find.descendant(of: detail, matching: find.byType(AnimatedOpacity)),
      findsNothing,
    );
    final preview = tester.widget<CaptureImagePreview>(detail);
    expect(preview.initialImagePath, photoPath);
    expect(preview.navigationContext, same(harness.navigationContext));

    harness.paths.detailPath.complete(photoPath);
    await tester.pump();
  });

  testWidgets('rapid detail return restores decoded record pixels', (
    tester,
  ) async {
    final harness = await pumpRecordToDetailRoute(tester);
    await tester.tap(find.byKey(const Key('record-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    harness.router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final flight = find.byKey(const Key('capture-photo-hero-flight'));
    expect(flight, findsOneWidget);
    expect(hasDecodedImage(tester, flight), isTrue);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    await tester.pumpAndSettle();
    final record = find.byKey(const Key('record-card'));
    expect(record, findsOneWidget);
    expect(hasDecodedImage(tester, record), isTrue);

    harness.paths.detailPath.complete(photoPath);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero remains in the overlay until reverse flight completes', (
    tester,
  ) async {
    await pumpHeroPair(tester);
    await tester.tap(find.byKey(const Key('open-hero-detail')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byKey(const Key('capture-photo-hero-flight')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('record-thumbnail')), findsOneWidget);
  });

  testWidgets('record thumbnail stays painted under the reverse flight', (
    tester,
  ) async {
    await pumpHeroPair(tester);
    await tester.tap(find.byKey(const Key('open-hero-detail')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byKey(const Key('record-thumbnail-content')), findsOneWidget);
  });

  testWidgets('reduce animations keeps the child without creating a Hero', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: CapturePhotoHero(
            tag: 'capture-photo-test',
            path: photoPath,
            child: Image.file(File(photoPath)),
          ),
        ),
      ),
    );

    expect(find.byType(Hero), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });
}
