import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/shared/ui/press_scale.dart';

Widget _harness({required VoidCallback? onPressed, double? scaleDown}) {
  return MaterialApp(
    home: Scaffold(
      body: PressScale(
        onPressed: onPressed,
        scaleDown: scaleDown ?? 0.96,
        child: const SizedBox(key: Key('press-me'), width: 80, height: 80),
      ),
    ),
  );
}

double pressScale(WidgetTester tester) {
  final box = tester.widget<Transform>(
    find.ancestor(
      of: find.byKey(const Key('press-me')),
      matching: find.byType(Transform),
    ),
  );
  // Transform.scale leaves z at 1, so getMaxScaleOnAxis() is always 1.0;
  // read the x-scale straight off the matrix instead.
  return box.transform.storage[0];
}

void main() {
  testWidgets('scales down while pressed and springs back on release', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_harness(onPressed: () => taps++));

    expect(pressScale(tester), 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    // The response starts with the finger — no tap deadline involved. The
    // first frame only arms the ticker clock (elapsed 0); the second one
    // moves the value.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(pressScale(tester), lessThan(1));

    await gesture.up();
    await tester.pump();
    // The release spring settles back to exactly 1.
    await tester.pumpAndSettle();
    expect(pressScale(tester), 1);
    expect(taps, 1);
  });

  testWidgets('fires the optional haptic once per press', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PressScale(
            onPressed: () => taps++,
            haptic: HapticFeedback.lightImpact,
            child: const SizedBox(key: Key('press-me'), width: 80, height: 80),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PressScale));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(
      calls.where((call) => call.method == 'HapticFeedback.vibrate').length,
      1,
    );
  });

  testWidgets('disabled surface does not react to presses', (tester) async {
    await tester.pumpWidget(_harness(onPressed: null));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(pressScale(tester), 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(pressScale(tester), 1);
  });

  testWidgets('dragging past the touch slop hands the gesture away', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PressScaleView(
            child: const SizedBox(key: Key('press-me'), width: 80, height: 80),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('press-me'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(pressScale(tester), lessThan(1));

    await gesture.moveBy(const Offset(0, 40));
    await tester.pumpAndSettle();
    // Cancelled press: back to full size while the finger is still down.
    expect(pressScale(tester), 1);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('reduce motion keeps the press functional without movement', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: PressScale(
              onPressed: () => taps++,
              child: const SizedBox(
                key: Key('press-me'),
                width: 80,
                height: 80,
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(pressScale(tester), 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(pressScale(tester), 1);
  });
}
