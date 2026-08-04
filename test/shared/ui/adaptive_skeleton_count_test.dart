import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/shared/ui/adaptive_skeleton_count.dart';

void main() {
  test('uses ceil before clamping the skeleton count', () {
    expect(adaptiveSkeletonCount(viewportHeight: 640, itemExtent: 118), 6);
    expect(adaptiveSkeletonCount(viewportHeight: 220, itemExtent: 118), 2);
    expect(adaptiveSkeletonCount(viewportHeight: 237, itemExtent: 118), 3);
  });

  test('clamps the skeleton count to the configured bounds', () {
    expect(adaptiveSkeletonCount(viewportHeight: 1, itemExtent: 118), 2);
    expect(adaptiveSkeletonCount(viewportHeight: 2000, itemExtent: 118), 8);
    expect(
      adaptiveSkeletonCount(
        viewportHeight: 900,
        itemExtent: 118,
        min: 3,
        max: 5,
      ),
      5,
    );
  });

  test('falls back to min for non-finite and non-positive dimensions', () {
    for (final viewportHeight in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
      0,
      -1,
    ]) {
      expect(
        adaptiveSkeletonCount(
          viewportHeight: viewportHeight,
          itemExtent: 118,
          min: 3,
        ),
        3,
      );
    }
    for (final itemExtent in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
      0,
      -1,
    ]) {
      expect(
        adaptiveSkeletonCount(
          viewportHeight: 640,
          itemExtent: itemExtent,
          min: 3,
        ),
        3,
      );
    }
  });
}
