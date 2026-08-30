import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/shared/ui/adaptive_dialog.dart';

void main() {
  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
  }

  testWidgets('android platform keeps the Material alert composition', (
    tester,
  ) async {
    await pumpHost(tester);

    final result = showAppDialog<bool>(
      context: tester.element(find.byType(Scaffold)),
      title: const Text('Title'),
      content: const Text('Content'),
      actions: [
        AppDialogAction(label: 'Cancel', result: false),
        AppDialogAction(label: 'Confirm', result: true, isDefault: true),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    // Cancel stays a TextButton and the default action a FilledButton,
    // mirroring the call-site composition this helper replaced.
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(CupertinoDialogAction), findsNothing);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('iOS platform presents a Cupertino alert with mapped actions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpHost(tester);

      final result = showAppDialog<bool>(
        context: tester.element(find.byType(Scaffold)),
        title: const Text('Title'),
        content: const Text('Content'),
        actions: [
          AppDialogAction(label: 'Cancel', result: false),
          AppDialogAction(label: 'Confirm', result: true, isDefault: true),
          AppDialogAction(label: 'Delete', result: true, isDestructive: true),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CupertinoDialogAction), findsNWidgets(3));
      final actions = find.byType(CupertinoDialogAction).evaluate().toList();
      final byLabel = {
        for (final action in actions)
          ((action.widget as CupertinoDialogAction).child as Text).data:
              action.widget as CupertinoDialogAction,
      };
      expect(byLabel['Confirm']!.isDefaultAction, isTrue);
      expect(byLabel['Delete']!.isDestructiveAction, isTrue);
      expect(byLabel['Cancel']!.isDefaultAction, isFalse);
      expect(byLabel['Cancel']!.isDestructiveAction, isFalse);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('action callback runs before the dialog pops', (tester) async {
    await pumpHost(tester);
    var callbackRuns = 0;

    final result = showAppDialog<bool>(
      context: tester.element(find.byType(Scaffold)),
      actions: [
        AppDialogAction(
          label: 'Confirm',
          result: true,
          onPressed: () => callbackRuns++,
        ),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(callbackRuns, 1);
  });

  testWidgets('cancel action pops with its result on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpHost(tester);

      final result = showAppDialog<bool>(
        context: tester.element(find.byType(Scaffold)),
        actions: [AppDialogAction(label: 'Cancel', result: false)],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
