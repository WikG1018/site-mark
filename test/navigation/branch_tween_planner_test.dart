import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/navigation/root_navigation_scaffold.dart';

/// Property tests for [RootBranchContainer.planTweens] — the pure tween
/// planner behind the dock-switch animation.
///
/// The widget tests in `root_navigation_scaffold_test.dart` sample a handful
/// of chains at a few frame offsets. The planner is pure, so here we can
/// exhaust the interruption geometry instead: arbitrary chains of tab
/// switches, interrupted at arbitrary progress, with the viewport-coverage
/// invariant checked at every sampled frame along the way.
void main() {
  const pageCount = 3;
  const epsilon = 1e-9;

  double position(Map<int, (double, double)> tweens, int index, double p) {
    final tween = tweens[index];
    if (tween == null) return 0;
    return tween.$1 + (tween.$2 - tween.$1) * p;
  }

  /// Mirrors the widget-test `assertViewportCovered`: every planned page
  /// spans [dx, dx + 1] in screen-width fractions, and the union of all spans
  /// must contain the viewport [0, 1] at any animation progress. Pages
  /// dropped from the map are offstaged by the widget, so they are excluded
  /// here exactly as in production.
  void expectViewportCovered(
    Map<int, (double, double)> tweens,
    double p, {
    required String when,
  }) {
    final intervals = <(double, double)>[];
    for (final index in tweens.keys) {
      final dx = position(tweens, index, p);
      intervals.add((dx, dx + 1));
    }
    intervals.sort((a, b) => a.$1.compareTo(b.$1));

    var coverageStart = intervals.first.$1;
    var coverageEnd = intervals.first.$2;
    for (final (start, end) in intervals.skip(1)) {
      if (start > coverageEnd) {
        // Gap between [coverageEnd, start]. Fails only if it intersects the
        // viewport and is wider than float epsilon.
        if (start > 0 && coverageEnd < 1 && start - coverageEnd > epsilon) {
          fail(
            '$when: viewport gap detected [$coverageEnd, $start]. '
            'Visible intervals: $intervals.',
          );
        }
      }
      if (end > coverageEnd) coverageEnd = end;
    }
    expect(
      coverageStart,
      lessThanOrEqualTo(0),
      reason: '$when: leftmost page must start at or before viewport left.',
    );
    expect(
      coverageEnd,
      greaterThanOrEqualTo(1),
      reason: '$when: rightmost page must end at or after viewport right.',
    );
  }

  /// Every planned page must converge to a settled end: the most recent
  /// target ends at 0, every other page ends at exactly -1 or +1 (fully
  /// exited), so the animation always finishes clean.
  void expectSettledEnd(
    Map<int, (double, double)> tweens, {
    required int targetIndex,
    required String when,
  }) {
    expect(
      tweens[targetIndex]!.$2,
      closeTo(0, epsilon),
      reason: '$when: target page must settle on center.',
    );
    for (final entry in tweens.entries) {
      if (entry.key == targetIndex) continue;
      expect(
        entry.value.$2.abs(),
        closeTo(1, epsilon),
        reason:
            '$when: page ${entry.key} must exit to exactly one screen width.',
      );
    }
  }

  group('documented scenarios', () {
    test('clean switch from rest enters edge-to-edge', () {
      final tweens = RootBranchContainer.planTweens(
        previous: const {0: (0, 0)},
        currentIndex: 0,
        targetIndex: 1,
        interruptProgress: null,
      );

      expect(tweens[0], (0.0, -1.0));
      expect(tweens[1], (1.0, 0.0));
      expectSettledEnd(tweens, targetIndex: 1, when: '0->1 clean');
      for (var k = 0; k <= 10; k++) {
        expectViewportCovered(tweens, k / 10, when: '0->1 clean at $k/10');
      }
    });

    test(
      'interrupted forward chain continues pages from their real position',
      () {
        // 0->1 interrupted halfway, then 1->2 before the first segment ends.
        final first = RootBranchContainer.planTweens(
          previous: const {0: (0, 0)},
          currentIndex: 0,
          targetIndex: 1,
          interruptProgress: null,
        );
        const halfway = 0.5;
        final oldPositions = <int, double>{
          for (final i in first.keys) i: position(first, i, halfway),
        };
        final second = RootBranchContainer.planTweens(
          previous: first,
          currentIndex: 1,
          targetIndex: 2,
          interruptProgress: halfway,
        );

        // No snap-back: page 1 continues from its mid-slide position.
        expect(second[1], isNotNull);
        expect(position(second, 1, 0), closeTo(oldPositions[1]!, epsilon));
        expect(position(second, 1, 0), isNot(closeTo(0, epsilon)));
        // Incoming page 2 starts edge-to-edge with page 1.
        expect(
          position(second, 2, 0),
          closeTo(position(second, 1, 0) + 1, epsilon),
        );
        expectSettledEnd(second, targetIndex: 2, when: '0->1->2 chain');
      },
    );

    test('reverse jump exits by index side, never across the viewport', () {
      // 0->2 half done, then 2->1: page 0 must stay on the left.
      final first = RootBranchContainer.planTweens(
        previous: const {0: (0, 0)},
        currentIndex: 0,
        targetIndex: 2,
        interruptProgress: null,
      );
      const halfway = 0.5;
      final second = RootBranchContainer.planTweens(
        previous: first,
        currentIndex: 2,
        targetIndex: 1,
        interruptProgress: halfway,
      );

      expect(position(second, 0, 0), lessThanOrEqualTo(0));
      expect(
        second[0]!.$2,
        -1.0,
        reason: 'page 0 (index < target) exits left.',
      );
      expect(
        second[2]!.$2,
        1.0,
        reason: 'page 2 (index > target) exits right.',
      );
      expectSettledEnd(second, targetIndex: 1, when: '0->2->1 reverse jump');
    });
  });

  group('property', () {
    test('random rapid chains never leave the viewport uncovered', () {
      final rng = Random(20260808);
      for (var round = 0; round < 3000; round++) {
        var current = rng.nextInt(pageCount);
        var tweens = <int, (double, double)>{current: (0, 0)};

        for (var step = 0; step < 30; step++) {
          var target = rng.nextInt(pageCount);
          while (target == current) {
            target = rng.nextInt(pageCount);
          }
          final interruptProgress = rng.nextBool() ? rng.nextDouble() : null;
          final oldPositions = <int, double>{
            for (final i in tweens.keys)
              i: position(tweens, i, interruptProgress ?? 1),
          };

          tweens = RootBranchContainer.planTweens(
            previous: tweens,
            currentIndex: current,
            targetIndex: target,
            interruptProgress: interruptProgress,
          );
          current = target;

          for (var k = 0; k <= 20; k++) {
            final p = k / 20;
            expectViewportCovered(
              tweens,
              p,
              when: 'round $round step $step sample $p',
            );
          }

          // Interrupted pages never jump: each kept page's new start equals
          // its on-screen position at the moment of the interrupt.
          if (interruptProgress != null) {
            for (final entry in tweens.entries) {
              final oldPos = oldPositions[entry.key];
              if (oldPos != null) {
                expect(
                  position(tweens, entry.key, 0),
                  closeTo(oldPos, epsilon),
                  reason:
                      'round $round step $step: page ${entry.key} snapped at '
                      'interrupt (progress $interruptProgress).',
                );
              }
            }
          }
          expectSettledEnd(
            tweens,
            targetIndex: current,
            when: 'round $round step $step',
          );
        }
      }
    });

    test('every interrupt progress value is safe for one-step chains', () {
      final rng = Random(424242);
      for (var round = 0; round < 500; round++) {
        final from = rng.nextInt(pageCount);
        final to = rng.nextInt(pageCount);
        if (from == to) continue;
        final previous = RootBranchContainer.planTweens(
          previous: {from: (0, 0)},
          currentIndex: from,
          targetIndex: to,
          interruptProgress: null,
        );
        for (var p = 0; p <= 500; p++) {
          final interrupt = p / 500;
          final tweens = RootBranchContainer.planTweens(
            previous: previous,
            currentIndex: to,
            targetIndex: from,
            interruptProgress: interrupt,
          );
          for (var k = 0; k <= 5; k++) {
            expectViewportCovered(
              tweens,
              k / 5,
              when: 'round $round interrupt $interrupt sample $k',
            );
          }
        }
      }
    });
  });
}
