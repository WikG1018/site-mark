import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/shared/ui/adaptive_toast.dart';

Widget _harness(WidgetBuilder builder) {
  return MaterialApp(
    home: Scaffold(body: Builder(builder: builder)),
  );
}

void main() {
  testWidgets('material branch delegates to a floating snackbar', (
    tester,
  ) async {
    var actionPressed = false;
    await tester.pumpWidget(
      _harness(
        (context) => Center(
          child: FilledButton(
            onPressed: () => showAppToast(
              context,
              '已删除原图',
              action: AppToastAction(
                label: '撤销',
                onPressed: () => actionPressed = true,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('已删除原图'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(actionPressed, isTrue);
  });

  testWidgets('material branch replace clears the visible snackbar first', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        (context) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: () => showAppToast(context, '第一条'),
                child: const Text('first'),
              ),
              FilledButton(
                onPressed: () => showAppToast(context, '第二条', replace: true),
                child: const Text('second'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('first'));
    await tester.pump();
    expect(find.text('第一条'), findsOneWidget);

    await tester.tap(find.text('second'));
    await tester.pumpAndSettle();
    expect(find.text('第二条'), findsOneWidget);
    expect(find.text('第一条'), findsNothing);
  });

  testWidgets('ios branch shows a glass capsule overlay that auto-dismisses', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        _harness(
          (context) => Center(
            child: FilledButton(
              onPressed: () => showAppToast(context, '已删除原图'),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('已删除原图'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('已删除原图'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('ios branch action runs and dismisses the capsule', (
    tester,
  ) async {
    var actionPressed = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        _harness(
          (context) => Center(
            child: FilledButton(
              onPressed: () => showAppToast(
                context,
                '已删除原图',
                action: AppToastAction(
                  label: '撤销',
                  onPressed: () => actionPressed = true,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(actionPressed, isTrue);
      expect(find.text('已删除原图'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('ios branch hideAppToast removes the capsule immediately', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        _harness(
          (context) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () => showAppToast(context, '第一条'),
                  child: const Text('first'),
                ),
                FilledButton(
                  onPressed: () => showAppToast(context, '第二条'),
                  child: const Text('second'),
                ),
                FilledButton(
                  onPressed: hideAppToast,
                  child: const Text('hide'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('first'));
      await tester.pumpAndSettle();
      expect(find.text('第一条'), findsOneWidget);

      await tester.tap(find.text('second'));
      await tester.pumpAndSettle();
      expect(find.text('第二条'), findsOneWidget);
      expect(find.text('第一条'), findsNothing);

      await tester.tap(find.text('hide'));
      await tester.pumpAndSettle();
      expect(find.text('第二条'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
