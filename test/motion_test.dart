import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/motion.dart';

void main() {
  test('spring curves hit their endpoints exactly', () {
    for (final curve in <Curve>[
      AppMotion.springSnapBack,
      AppMotion.springScaleSettle,
      AppMotion.springSlideRise,
    ]) {
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
    }
  });

  test('settle and rise springs carry a small overshoot', () {
    // The "life" of spring motion: a visible but restrained overshoot past
    // the target before settling.
    for (final curve in <Curve>[
      AppMotion.springScaleSettle,
      AppMotion.springSlideRise,
    ]) {
      var peak = 0.0;
      for (var step = 0; step <= 100; step++) {
        final value = curve.transform(step / 100);
        expect(value, greaterThan(-0.01), reason: '$curve $step');
        if (value > peak) peak = value;
      }
      expect(peak, greaterThan(1.0), reason: '$curve should overshoot');
      expect(peak, lessThan(1.25), reason: '$curve overshoot stays restrained');
    }
  });

  test('snap spring settles without visible overshoot', () {
    var peak = 0.0;
    for (var step = 0; step <= 100; step++) {
      final value = AppMotion.springSnapBack.transform(step / 100);
      if (value > peak) peak = value;
    }
    // Near-critical damping: a whisper of settle at most, never a bounce.
    expect(peak, greaterThanOrEqualTo(1));
    expect(peak, lessThan(1.02));
  });

  testWidgets('reduce-motion collapses durations to zero', (tester) async {
    late Duration resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolved = AppMotion.durationOf(context, AppMotion.long2);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(resolved, Duration.zero);
  });
}
