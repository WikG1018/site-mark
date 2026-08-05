import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';

void main() {
  test('root dock uses the compact 68dp height', () {
    expect(floatingDockHeight, 68);
  });

  testWidgets('reserved content space includes safe area and FAB clearance', (
    tester,
  ) async {
    late double dockOnly;
    late double dockAndFab;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
          child: Builder(
            builder: (context) {
              dockOnly = floatingDockReservedSpaceOf(context);
              dockAndFab = floatingDockReservedSpaceOf(
                context,
                avoidFloatingActionButton: true,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(dockOnly, floatingDockReservedSpace + 34);
    expect(dockAndFab, floatingDockFabReservedSpace + 34);
    expect(dockAndFab, greaterThan(dockOnly));
  });

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
                dock: showDock
                    ? const SizedBox(
                        key: Key('test-dock'),
                        height: floatingDockHeight,
                      )
                    : null,
                child: const SizedBox.expand(key: Key('page-content')),
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
            dock: const SizedBox(
              key: Key('test-dock'),
              height: floatingDockHeight,
            ),
            floatingActionButton: FloatingActionButton(
              key: const Key('test-fab'),
              onPressed: () {},
            ),
            child: const SizedBox.expand(),
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
              dock: SizedBox(key: Key('test-dock'), height: floatingDockHeight),
              child: SizedBox.expand(),
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

  testWidgets('dock animation can be disabled for synchronized replacement', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FloatingDockLayout(
            animateDock: false,
            dock: SizedBox(key: Key('test-dock'), height: floatingDockHeight),
            child: SizedBox.expand(),
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
