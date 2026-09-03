import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/navigation/scroll_chrome.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';

void main() {
  Future<void> pumpProbe(
    WidgetTester tester, {
    Object resetKey = 0,
    Widget? extra,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: ScrollChromeHost(
            resetKey: resetKey,
            child: extra ?? const _ChromeProbe(),
          ),
        ),
      ),
    );
  }

  testWidgets('scrolling down hides chrome and scrolling up shows it', (
    tester,
  ) async {
    await pumpProbe(tester);
    await tester.pump();
    expect(find.text('shown'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('probe-list')),
      const Offset(0, -300),
    );
    await tester.pump();
    expect(find.text('hidden'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('probe-list')),
      const Offset(0, 300),
    );
    await tester.pump();
    expect(find.text('shown'), findsOneWidget);
  });

  testWidgets('force reason keeps chrome visible while scrolling down', (
    tester,
  ) async {
    await pumpProbe(tester, extra: const _ForceProbe());
    await tester.pump();

    await tester.tap(find.byKey(const Key('force-on')));
    await tester.pump();

    await tester.drag(
      find.byKey(const Key('probe-list')),
      const Offset(0, -300),
    );
    await tester.pump();
    expect(find.text('shown'), findsOneWidget);

    await tester.tap(find.byKey(const Key('force-off')));
    await tester.pump();
    expect(find.text('shown'), findsOneWidget);
  });

  testWidgets('changing resetKey shows chrome again', (tester) async {
    await pumpProbe(tester, resetKey: 0);
    await tester.drag(
      find.byKey(const Key('probe-list')),
      const Offset(0, -300),
    );
    await tester.pump();
    expect(find.text('hidden'), findsOneWidget);

    await pumpProbe(tester, resetKey: 1);
    await tester.pump();
    expect(find.text('shown'), findsOneWidget);
  });

  testWidgets('hidden chrome slides the overlay dock off-screen', (
    tester,
  ) async {
    await pumpProbe(tester, extra: const _DockProbe());
    await tester.pumpAndSettle();

    final shown = tester.getRect(find.byKey(const Key('probe-dock')));
    final viewportBottom = tester.getRect(find.byType(Scaffold)).bottom;
    expect(shown.bottom, lessThanOrEqualTo(viewportBottom));

    await tester.drag(
      find.byKey(const Key('probe-list')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    final hidden = tester.getRect(find.byKey(const Key('probe-dock')));
    expect(hidden.top, greaterThan(shown.top));
    expect(hidden.top, greaterThanOrEqualTo(viewportBottom - 1));
  });
}

class _ChromeProbe extends StatelessWidget {
  const _ChromeProbe();

  @override
  Widget build(BuildContext context) {
    final visible = ScrollChromeScope.visibleOf(context);
    return Scaffold(
      body: Column(
        children: [
          Text(visible ? 'shown' : 'hidden', key: const Key('chrome-state')),
          Expanded(child: _probeList()),
        ],
      ),
    );
  }
}

class _ForceProbe extends StatelessWidget {
  const _ForceProbe();

  @override
  Widget build(BuildContext context) {
    final visible = ScrollChromeScope.visibleOf(context);
    final controller = ScrollChromeScope.maybeOf(context);
    return Scaffold(
      body: Column(
        children: [
          Text(visible ? 'shown' : 'hidden', key: const Key('chrome-state')),
          Row(
            children: [
              TextButton(
                key: const Key('force-on'),
                onPressed: () => controller?.setForce('search', true),
                child: const Text('force'),
              ),
              TextButton(
                key: const Key('force-off'),
                onPressed: () => controller?.setForce('search', false),
                child: const Text('release'),
              ),
            ],
          ),
          Expanded(child: _probeList()),
        ],
      ),
    );
  }
}

class _DockProbe extends StatelessWidget {
  const _DockProbe();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FloatingDockLayout(
        dock: const SizedBox(
          key: Key('probe-dock'),
          height: floatingDockHeight,
        ),
        child: _probeList(),
      ),
    );
  }
}

Widget _probeList() {
  return ListView(
    key: const Key('probe-list'),
    children: [
      for (var i = 0; i < 40; i++) SizedBox(height: 80, child: Text('row $i')),
    ],
  );
}
