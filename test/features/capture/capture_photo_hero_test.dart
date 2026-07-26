import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/capture/capture_photo_hero.dart';

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
                    transitionDuration: const Duration(milliseconds: 300),
                    reverseTransitionDuration: const Duration(
                      milliseconds: 300,
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
}
