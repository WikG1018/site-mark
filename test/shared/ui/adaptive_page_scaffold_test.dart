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

  testWidgets('iOS raw scaffold renders floatingActionButton', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: AdaptivePageScaffold.raw(
            title: '标题',
            body: Text('正文'),
            floatingActionButton: FloatingActionButton(
              key: Key('probe-fab'),
              onPressed: null,
              child: Icon(Icons.add),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('probe-fab')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS raw scaffold lays out a fill-style stack body', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptivePageScaffold.raw(
            title: '标题',
            iosBodyPadding: EdgeInsets.zero,
            body: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: ListView(children: const [Text('内容')])),
                const Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Text('悬浮 Dock'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('内容'), findsOneWidget);
      expect(find.text('悬浮 Dock'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS raw inner list scroll collapses the large title', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptivePageScaffold.raw(
            title: '大标题',
            iosBodyPadding: EdgeInsets.zero,
            body: ListView(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 80, child: Text('item-$i')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.text('item-0'), const Offset(0, -800));
      await tester.pumpAndSettle();

      final nested = tester.state<NestedScrollViewState>(
        find.byType(NestedScrollView),
      );
      expect(nested.outerController.offset, greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('nested inner controller is the primary under NestedScrollView', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      ScrollController? found;
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptivePageScaffold.raw(
            title: '标题',
            iosBodyPadding: EdgeInsets.zero,
            body: Builder(
              builder: (context) {
                found = nestedInnerScrollControllerOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(found, isNotNull);
      expect(
        found,
        same(
          tester
              .state<NestedScrollViewState>(find.byType(NestedScrollView))
              .innerController,
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('nested inner controller is null on Material platforms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      ScrollController? found;
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptivePageScaffold.raw(
            title: '标题',
            body: Builder(
              builder: (context) {
                found = nestedInnerScrollControllerOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(found, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'iOS boxed scaffold keeps CustomScrollView not NestedScrollView',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          const MaterialApp(
            home: AdaptivePageScaffold(title: '页面标题', body: Text('正文')),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CustomScrollView), findsOneWidget);
        expect(find.byType(NestedScrollView), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('iOS raw explicit inner controller collapses the large title', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptivePageScaffold.raw(
            title: '大标题',
            iosBodyPadding: EdgeInsets.zero,
            body: Builder(
              builder: (context) {
                return ListView(
                  controller: nestedInnerScrollControllerOf(context),
                  children: [
                    for (var i = 0; i < 40; i++)
                      SizedBox(height: 80, child: Text('item-$i')),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.text('item-0'), const Offset(0, -800));
      await tester.pumpAndSettle();

      final nested = tester.state<NestedScrollViewState>(
        find.byType(NestedScrollView),
      );
      expect(nested.outerController.offset, greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('jumpNestedScrollViewsToTop expands the large title', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptivePageScaffold.raw(
            title: '大标题',
            iosBodyPadding: EdgeInsets.zero,
            body: Builder(
              builder: (context) {
                return ListView(
                  children: [
                    for (var i = 0; i < 40; i++)
                      SizedBox(height: 80, child: Text('item-$i')),
                    TextButton(
                      onPressed: () => jumpNestedScrollViewsToTop(context),
                      child: const Text('回顶'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.text('item-0'), const Offset(0, -800));
      await tester.pumpAndSettle();
      final nested = tester.state<NestedScrollViewState>(
        find.byType(NestedScrollView),
      );
      expect(nested.outerController.offset, greaterThan(0));

      jumpNestedScrollViewsToTop(tester.element(find.byType(ListView)));
      await tester.pumpAndSettle();
      expect(nested.innerController.offset, 0);
      expect(nested.outerController.offset, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
