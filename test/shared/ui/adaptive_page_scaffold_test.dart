import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/shared/ui/adaptive_page_scaffold.dart';

void main() {
  Future<void> pumpScaffold(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptivePageScaffold(title: '页面标题', body: Text('正文')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Material platforms keep the AppBar over a padded list', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpScaffold(tester);

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(CupertinoSliverNavigationBar), findsNothing);
      expect(find.text('页面标题'), findsOneWidget);
      expect(find.text('正文'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS renders the collapsing large-title nav bar', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpScaffold(tester);

      expect(find.byType(CupertinoSliverNavigationBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      // The collapsing bar keeps both the collapsed and large title in the
      // tree, cross-fading on scroll.
      expect(find.text('页面标题'), findsNWidgets(2));
      expect(find.text('正文'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('raw variant uses the body as-is on Material platforms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: AdaptivePageScaffold.raw(
            title: '标题',
            body: Scaffold(body: Center(child: Text('自管滚动'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No outer content list: the body is the direct Scaffold body.
      expect(find.byType(ListView), findsNothing);
      expect(find.text('自管滚动'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
