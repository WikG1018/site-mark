import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/shared/ui/adaptive_sheet.dart';

void main() {
  testWidgets('material branch shows a bottom sheet and pops with results', (
    tester,
  ) async {
    Object? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                result = await showAppActionSheet<String>(
                  context: context,
                  title: '选择操作',
                  message: '不可撤销',
                  actions: [
                    AppSheetAction(
                      key: const Key('action-first'),
                      label: '编辑',
                      icon: Icons.edit_outlined,
                      result: 'edit',
                    ),
                    AppSheetAction(
                      key: const Key('action-disabled'),
                      label: '置灰项',
                      enabled: false,
                      result: 'disabled',
                    ),
                    AppSheetAction(
                      key: const Key('action-delete'),
                      label: '删除',
                      icon: Icons.delete_outline,
                      isDestructive: true,
                      result: 'delete',
                    ),
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('选择操作'), findsOneWidget);
    expect(find.text('不可撤销'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await tester.tap(find.byKey(const Key('action-disabled')));
    await tester.pump();
    expect(result, isNull);
    expect(find.text('编辑'), findsOneWidget);

    await tester.tap(find.byKey(const Key('action-delete')));
    await tester.pumpAndSettle();
    expect(result, 'delete');
  });

  testWidgets('material branch runs onPressed before popping', (tester) async {
    var pressed = false;
    Object? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                result = await showAppActionSheet<String>(
                  context: context,
                  actions: [
                    AppSheetAction(
                      key: const Key('action-first'),
                      label: '编辑',
                      result: 'edit',
                      onPressed: () => pressed = true,
                    ),
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-first')));
    await tester.pumpAndSettle();
    expect(pressed, isTrue);
    expect(result, 'edit');
  });

  testWidgets('ios branch renders a CupertinoActionSheet with cancel row', (
    tester,
  ) async {
    Object? result;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showAppActionSheet<String>(
                    context: context,
                    title: '选择操作',
                    actions: [
                      AppSheetAction(
                        key: const Key('action-first'),
                        label: '编辑',
                        result: 'edit',
                      ),
                      AppSheetAction(
                        key: const Key('action-delete'),
                        label: '删除',
                        isDestructive: true,
                        result: 'delete',
                      ),
                    ],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.text('选择操作'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      await tester.tap(find.byKey(const Key('action-first')));
      await tester.pumpAndSettle();
      expect(result, 'edit');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('ios branch disabled rows are dimmed and inert', (tester) async {
    Object? result;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showAppActionSheet<String>(
                    context: context,
                    actions: [
                      AppSheetAction(
                        key: const Key('action-disabled'),
                        label: '置灰项',
                        enabled: false,
                        result: 'disabled',
                      ),
                    ],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-disabled')));
      await tester.pumpAndSettle();
      expect(result, isNull);
      // The sheet stays open; the cancel row remains reachable.
      expect(find.text('取消'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
