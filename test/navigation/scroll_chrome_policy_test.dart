import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/navigation/scroll_chrome.dart';

void main() {
  group('ScrollChromePolicy', () {
    test('starts visible', () {
      expect(ScrollChromePolicy().visible, isTrue);
    });

    test('ignores jitter smaller than the hide threshold', () {
      final policy = ScrollChromePolicy();

      expect(
        policy.apply(delta: ScrollChromePolicy.hideThreshold - 1, offset: 80),
        isFalse,
      );
      expect(policy.visible, isTrue);
    });

    test('hides after downward deltas accumulate past the threshold', () {
      final policy = ScrollChromePolicy();
      final half = ScrollChromePolicy.hideThreshold / 2;

      expect(policy.apply(delta: half, offset: 80), isFalse);
      expect(policy.visible, isTrue);
      expect(policy.apply(delta: half, offset: 80 + half), isTrue);
      expect(policy.visible, isFalse);
    });

    test('hides on a single downward delta at or above the threshold', () {
      final policy = ScrollChromePolicy();

      expect(
        policy.apply(delta: ScrollChromePolicy.hideThreshold, offset: 120),
        isTrue,
      );
      expect(policy.visible, isFalse);
    });

    test('shows again after an upward delta past the show threshold', () {
      final policy = ScrollChromePolicy();
      policy.apply(delta: 40, offset: 200);

      expect(
        policy.apply(delta: -ScrollChromePolicy.showThreshold, offset: 160),
        isTrue,
      );
      expect(policy.visible, isTrue);
    });

    test('reversing direction resets the accumulator before hiding', () {
      final policy = ScrollChromePolicy();
      final almost = ScrollChromePolicy.hideThreshold - 1;

      expect(policy.apply(delta: almost, offset: 80), isFalse);
      expect(policy.apply(delta: -almost, offset: 80 - almost), isFalse);
      expect(policy.visible, isTrue);
      expect(policy.apply(delta: almost, offset: 80), isFalse);
      expect(policy.visible, isTrue);
    });

    test(
      'stays visible while forceVisible even on a large downward scroll',
      () {
        final policy = ScrollChromePolicy();

        expect(
          policy.apply(delta: 80, offset: 400, forceVisible: true),
          isFalse,
        );
        expect(policy.visible, isTrue);
      },
    );

    test('forceVisible reveals chrome that was already hidden', () {
      final policy = ScrollChromePolicy();
      policy.apply(delta: 80, offset: 400);

      expect(policy.apply(delta: 20, offset: 420, forceVisible: true), isTrue);
      expect(policy.visible, isTrue);
    });

    test('stays visible near the top of the list', () {
      final policy = ScrollChromePolicy();
      policy.apply(delta: 80, offset: 400);

      expect(
        policy.apply(delta: 20, offset: ScrollChromePolicy.topRevealExtent),
        isTrue,
      );
      expect(policy.visible, isTrue);
    });

    test('reset shows chrome and clears a pending hide', () {
      final policy = ScrollChromePolicy();
      policy.apply(delta: ScrollChromePolicy.hideThreshold - 1, offset: 80);
      policy.apply(delta: 40, offset: 200);

      expect(policy.reset(), isTrue);
      expect(policy.visible, isTrue);
      expect(
        policy.apply(delta: ScrollChromePolicy.hideThreshold - 1, offset: 80),
        isFalse,
      );
      expect(policy.visible, isTrue);
    });

    test('ignores non-finite deltas and offsets', () {
      final policy = ScrollChromePolicy();

      expect(policy.apply(delta: double.nan, offset: 80), isFalse);
      expect(policy.apply(delta: 40, offset: double.infinity), isFalse);
      expect(policy.visible, isTrue);
    });
  });
}
