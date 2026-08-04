import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_lifecycle.dart';
import 'package:sitemark/domain/project_summary.dart';
import 'package:sitemark/features/projects/project_summary_card.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/platform_services.dart';

class _ImmediateOutputPaths implements CaptureOutputPaths {
  _ImmediateOutputPaths({required this.paths, this.errors = const {}});

  final Map<String, String> paths;
  final Set<String> errors;
  final calls = <String, int>{};

  @override
  Future<String> renderedPhotoPath(String captureId) {
    calls.update(captureId, (count) => count + 1, ifAbsent: () => 1);
    if (errors.contains(captureId)) {
      return Future.error(StateError('path unavailable'));
    }
    return Future.value(paths[captureId] ?? '');
  }
}

class _ControlledOutputPaths implements CaptureOutputPaths {
  _ControlledOutputPaths(Iterable<String> ids)
    : _completers = {for (final id in ids) id: Completer<String>()};

  final Map<String, Completer<String>> _completers;
  final calls = <String, int>{};

  @override
  Future<String> renderedPhotoPath(String captureId) {
    calls.update(captureId, (count) => count + 1, ifAbsent: () => 1);
    return _completers[captureId]!.future;
  }

  void complete(String captureId, String path) {
    _completers[captureId]!.complete(path);
  }
}

void main() {
  late Map<String, String> photoPaths;

  setUpAll(() {
    photoPaths = {
      'one': File('assets/branding/sitemark-icon.png').absolute.path,
      'one-alt': File(
        'assets/branding/sitemark-icon-monochrome.png',
      ).absolute.path,
      'two': File('assets/branding/sitemark-icon-foreground.png').absolute.path,
      'three': File(
        'assets/branding/sitemark-icon-background.png',
      ).absolute.path,
      'four': File(
        'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
      ).absolute.path,
    };
  });

  Widget app(Widget child) => MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );

  Future<void> settleAsyncWork(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pumpAndSettle();
  }

  String renderedPath(WidgetTester tester, String captureId) {
    final image = tester.widget<Image>(
      find.byKey(Key('project-thumbnail-$captureId')),
    );
    final resized = image.image as ResizeImage;
    return (resized.imageProvider as FileImage).file.path;
  }

  testWidgets('same ids reuse resolved paths across parent rebuilds', (
    tester,
  ) async {
    final outputPaths = _ImmediateOutputPaths(
      paths: {
        'three': photoPaths['three']!,
        'two': photoPaths['two']!,
        'one': photoPaths['one']!,
      },
    );
    late StateSetter rebuild;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ProjectRecentThumbnails(
              captureIds: const ['three', 'two', 'one'],
              outputPaths: outputPaths,
            );
          },
        ),
      ),
    );
    await settleAsyncWork(tester);
    expect(outputPaths.calls, {'three': 1, 'two': 1, 'one': 1});

    rebuild(() {});
    await settleAsyncWork(tester);

    expect(outputPaths.calls, {'three': 1, 'two': 1, 'one': 1});
  });

  testWidgets('reordered ids never render a previous slot path', (
    tester,
  ) async {
    final outputPaths = _ControlledOutputPaths(['four', 'three', 'two', 'one']);
    outputPaths.complete('three', photoPaths['three']!);
    outputPaths.complete('two', photoPaths['two']!);
    outputPaths.complete('one', photoPaths['one']!);
    var captureIds = <String>['three', 'two', 'one'];
    late StateSetter update;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ProjectRecentThumbnails(
              captureIds: captureIds,
              outputPaths: outputPaths,
            );
          },
        ),
      ),
    );
    await settleAsyncWork(tester);
    expect(renderedPath(tester, 'three'), photoPaths['three']);

    update(() => captureIds = ['four', 'three', 'two']);
    await tester.pump();

    expect(find.byKey(const Key('project-thumbnail-four')), findsNothing);
    outputPaths.complete('four', photoPaths['four']!);
    await settleAsyncWork(tester);
    expect(renderedPath(tester, 'four'), photoPaths['four']);
  });

  testWidgets('changing output paths refreshes without showing stale data', (
    tester,
  ) async {
    final firstPaths = _ControlledOutputPaths(['one'])
      ..complete('one', photoPaths['one']!);
    final secondPaths = _ControlledOutputPaths(['one']);
    CaptureOutputPaths outputPaths = firstPaths;
    late StateSetter update;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ProjectRecentThumbnails(
              captureIds: const ['one'],
              outputPaths: outputPaths,
            );
          },
        ),
      ),
    );
    await settleAsyncWork(tester);
    expect(renderedPath(tester, 'one'), photoPaths['one']);

    update(() => outputPaths = secondPaths);
    await tester.pump();

    expect(secondPaths.calls['one'], 1);
    expect(find.byKey(const Key('project-thumbnail-one')), findsNothing);
    secondPaths.complete('one', photoPaths['one-alt']!);
    await settleAsyncWork(tester);
    expect(renderedPath(tester, 'one'), photoPaths['one-alt']);
  });

  testWidgets('path errors and missing files show neutral placeholders', (
    tester,
  ) async {
    final outputPaths = _ImmediateOutputPaths(
      paths: {
        'missing': File(
          'build/project-thumbnail-does-not-exist.png',
        ).absolute.path,
      },
      errors: const {'error'},
    );
    await tester.pumpWidget(
      app(
        ProjectRecentThumbnails(
          captureIds: const ['missing', 'error'],
          outputPaths: outputPaths,
        ),
      ),
    );
    await settleAsyncWork(tester);

    expect(
      find.byKey(const Key('project-thumbnail-placeholder-missing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('project-thumbnail-placeholder-error')),
      findsOneWidget,
    );
    expect(find.textContaining('fail', findRichText: true), findsNothing);
    expect(find.textContaining('失败', findRichText: true), findsNothing);
  });

  testWidgets('rendered thumbnails are decorative and bounded for caching', (
    tester,
  ) async {
    final outputPaths = _ImmediateOutputPaths(
      paths: {'one': photoPaths['one']!},
    );
    await tester.pumpWidget(
      app(
        ProjectRecentThumbnails(
          captureIds: const ['one'],
          outputPaths: outputPaths,
        ),
      ),
    );
    await settleAsyncWork(tester);

    final thumbnail = find.byKey(const Key('project-thumbnail-one'));
    final image = tester.widget<Image>(thumbnail);
    expect(image.excludeFromSemantics, isTrue);
    expect((image.image as ResizeImage).width, 192);
    expect(image.gaplessPlayback, isTrue);
    expect(
      find.ancestor(of: thumbnail, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
  });

  testWidgets('project card has one tap target and opens its destination', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final outputPaths = _ImmediateOutputPaths(paths: const {});
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => ProjectSummaryCard(
            key: const Key('summary-card'),
            summary: _summary(),
            outputPaths: outputPaths,
            onOpen: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => const Scaffold(
                  body: Text('Project destination', key: Key('destination')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleAsyncWork(tester);

    final card = find.byKey(const Key('summary-card'));
    final tapTarget = find.descendant(of: card, matching: find.byType(InkWell));
    expect(tapTarget, findsOneWidget);
    expect(
      tester
          .getSemantics(tapTarget)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(card);
    await settleAsyncWork(tester);
    expect(find.byKey(const Key('destination')), findsOneWidget);
    semantics.dispose();
  });
}

ProjectSummary _summary() {
  final timestamp = DateTime.utc(2026, 8, 4);
  return ProjectSummary(
    project: Project(
      id: 'project-1',
      name: 'Project one',
      lifecycleStatus: ProjectLifecycleStatus.active,
      isPinned: false,
      watermarkPosition: 'bottomRight',
      watermarkOpacity: .8,
      watermarkAccentColorArgb: 0xFF006C4C,
      watermarkFontScale: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
    captureCount: 0,
    lastCaptureAt: null,
  );
}
