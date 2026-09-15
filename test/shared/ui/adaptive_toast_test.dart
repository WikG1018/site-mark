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
  testWidgets('shows a floating glass capsule, not a Material SnackBar', (
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
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(actionPressed, isTrue);
    expect(find.text('已删除原图'), findsNothing);
  });

  testWidgets('replace clears the visible capsule first', (tester) async {
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
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('auto-dismisses after the duration', (tester) async {
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

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('已删除原图'), findsNothing);
  });

  testWidgets('uses the glass capsule on Android too', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        _harness(
          (context) => Center(
            child: FilledButton(
              onPressed: () => showAppToast(context, '项目已删除'),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('项目已删除'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('hideAppToast removes the capsule immediately', (tester) async {
    await tester.pumpWidget(
      _harness(
        (context) => Column(
          children: [
            FilledButton(
              onPressed: () => showAppToast(context, '第一条'),
              child: const Text('first'),
            ),
            FilledButton(
              onPressed: () => showAppToast(context, '第二条', replace: true),
              child: const Text('second'),
            ),
            FilledButton(onPressed: hideAppToast, child: const Text('hide')),
          ],
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
  });

  testWidgets('keeps working without a ScaffoldMessenger', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showAppToast(context, '无 Scaffold 也能提示'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('无 Scaffold 也能提示'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
