import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/design_tokens.dart';

void main() {
  test('radius scale is strictly increasing with tight steps', () {
    final steps = <double>[
      AppRadius.xs.x,
      AppRadius.sm.x,
      AppRadius.md.x,
      AppRadius.lg.x,
      AppRadius.xl.x,
      AppRadius.pill.x,
    ];
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i], greaterThan(steps[i - 1]), reason: 'step $i increases');
    }
    // Neighbouring steps differ by at most 4px so the app reads as one
    // shape family (the pill is a different class of shape and jumps last).
    for (var i = 1; i < 5; i++) {
      expect(steps[i] - steps[i - 1], lessThanOrEqualTo(4), reason: 'step $i');
    }
  });

  testWidgets('chrome shadow is one soft drop in both brightnesses', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      late List<BoxShadow> shadows;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Builder(
            builder: (context) {
              shadows = AppShadow.chrome(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(shadows, hasLength(1), reason: '$brightness');
      expect(shadows.single.offset, const Offset(0, 3));
      expect(shadows.single.blurRadius, greaterThanOrEqualTo(12));
    }
  });
}
