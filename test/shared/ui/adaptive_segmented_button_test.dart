import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/shared/ui/adaptive_segmented_button.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'segmented choices fit narrow screens and large text on $platform',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var selected = 'auto';
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(36),
                  child: StatefulBuilder(
                    builder: (context, setState) =>
                        AdaptiveSegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'auto',
                              label: Text('Automatic'),
                            ),
                            ButtonSegment(
                              value: 'official',
                              label: Text('Official only'),
                            ),
                            ButtonSegment(
                              value: 'mirror',
                              label: Text('Mirror first'),
                            ),
                          ],
                          selected: {selected},
                          onSelectionChanged: (value) =>
                              setState(() => selected = value.single),
                        ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (platform == TargetPlatform.android) {
            final control = tester.widget<SegmentedButton<String>>(
              find.byType(SegmentedButton<String>),
            );
            expect(control.direction, Axis.vertical);
            expect(
              control.style?.shape?.resolve({}),
              isA<RoundedRectangleBorder>(),
            );
            expect(
              tester.getSize(find.byType(SegmentedButton<String>)).width,
              248,
            );
          }
          for (final label in ['Automatic', 'Official only', 'Mirror first']) {
            final rect = tester.getRect(find.text(label));
            expect(rect.left, greaterThanOrEqualTo(36));
            expect(rect.right, lessThanOrEqualTo(284));
          }
          await tester.tap(find.text('Official only'));
          await tester.pumpAndSettle();
          expect(selected, 'official');
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
