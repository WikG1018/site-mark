import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';

void main() {
  testWidgets('dock overlays content without shortening the page', (
    tester,
  ) async {
    Future<Size> pump({required bool showDock}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 800)),
            child: Scaffold(
              body: FloatingDockLayout(
                child: const SizedBox.expand(key: Key('page-content')),
                dock: showDock
                    ? const SizedBox(
                        key: Key('test-dock'),
                        height: floatingDockHeight,
                      )
                    : null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(const Key('page-content')));
    }

    final withoutDock = await pump(showDock: false);
    final withDock = await pump(showDock: true);

    expect(withDock, withoutDock);
    final contentRect = tester.getRect(find.byKey(const Key('page-content')));
    final dockRect = tester.getRect(find.byKey(const Key('test-dock')));
    expect(dockRect.left, contentRect.left + floatingDockHorizontalInset);
    expect(dockRect.right, contentRect.right - floatingDockHorizontalInset);
  });

  testWidgets('floating action stays above the dock', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingDockLayout(
            child: const SizedBox.expand(),
            dock: const SizedBox(
              key: Key('test-dock'),
              height: floatingDockHeight,
            ),
            floatingActionButton: FloatingActionButton(
              key: const Key('test-fab'),
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fab = tester.getRect(find.byKey(const Key('test-fab')));
    final dock = tester.getRect(find.byKey(const Key('test-dock')));
    expect(fab.bottom, lessThan(dock.top));
  });

  testWidgets('reduce motion removes dock transition duration', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: FloatingDockLayout(
              child: SizedBox.expand(),
              dock: SizedBox(key: Key('test-dock'), height: floatingDockHeight),
            ),
          ),
        ),
      ),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byKey(const Key('floating-dock-slot')),
    );
    expect(switcher.duration, Duration.zero);
  });
}
