import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/release_check.dart';
import 'package:sitemark/features/settings/automatic_update_host.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/automatic_update_controller.dart';
import 'package:sitemark/platform/github_release_client.dart';
import 'package:sitemark/platform/release_check_mode_store.dart';
import 'package:sitemark/shared/ui/floating_dock_layout.dart';

void main() {
  late _Lookup lookup;
  late AutomaticUpdateController controller;
  setUp(() {
    lookup = _Lookup();
    controller = AutomaticUpdateController(
      store: _Store(),
      lookup: lookup,
      modes: MemoryReleaseCheckModeStore(),
      version: () async => '1.0.33',
    );
  });
  tearDown(() => controller.dispose());

  Future<void> pump(
    WidgetTester tester, {
    bool active = true,
    double keyboard = 0,
    VoidCallback? onOpen,
    double textScale = 1,
    Locale locale = const Locale('zh'),
    bool withFab = false,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MediaQuery(
          data: MediaQueryData(
            viewInsets: EdgeInsets.only(bottom: keyboard),
            textScaler: TextScaler.linear(textScale),
          ),
          child: AutomaticUpdateHost(
            controller: controller,
            active: active,
            onOpen: onOpen ?? () {},
            avoidFloatingActionButton: withFab,
            child: Scaffold(
              body: FloatingDockLayout(
                floatingActionButton: withFab
                    ? FloatingActionButton(
                        key: const Key('new-project-fab'),
                        onPressed: () {},
                        child: const Icon(Icons.add),
                      )
                    : null,
                child: const Text('page'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('defers while nested and offers an explicit update action', (
    tester,
  ) async {
    var opened = 0;
    await pump(tester, active: false);
    expect(lookup.calls, 1);
    expect(find.byKey(const Key('automatic-update-notice')), findsNothing);
    await pump(tester, onOpen: () => opened++);
    expect(find.text('发现新版本 1.0.34'), findsOneWidget);
    await tester.tap(find.byKey(const Key('view-automatic-update')));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.byKey(const Key('automatic-update-notice')), findsNothing);
    await pump(tester);
    expect(find.byKey(const Key('automatic-update-notice')), findsNothing);
    expect(lookup.calls, 1);
  });

  testWidgets('does not cover the keyboard, and is dismissible', (
    tester,
  ) async {
    await pump(tester, keyboard: 280);
    expect(find.byKey(const Key('automatic-update-notice')), findsNothing);
    await pump(tester);
    expect(find.byKey(const Key('automatic-update-notice')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dismiss-automatic-update')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('automatic-update-notice')), findsNothing);
  });

  testWidgets('reminder leaves the new-project button visible and tappable', (
    tester,
  ) async {
    await pump(tester, withFab: true);
    final notice = tester.getRect(
      find.byKey(const Key('automatic-update-notice')),
    );
    final fab = tester.getRect(find.byKey(const Key('new-project-fab')));
    expect(notice.bottom, lessThan(fab.top));
    await tester.tap(find.byKey(const Key('dismiss-automatic-update')));
    await tester.pumpAndSettle();
  });

  testWidgets('background completion cannot display a reminder', (
    tester,
  ) async {
    final pending = Completer<ReleaseCheckOutcome>();
    lookup.pending = pending.future;
    await pump(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    pending.complete(_Lookup.update);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('automatic-update-notice')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('automatic-update-notice')), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(find.byKey(const Key('automatic-update-notice')), findsNothing);
    expect(lookup.calls, 1);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets('notice fits 320dp with 2x text in $locale', (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, textScale: 2, locale: locale);
      expect(tester.takeException(), isNull);
      final notice = tester.getRect(
        find.byKey(const Key('automatic-update-notice')),
      );
      expect(notice.left, greaterThanOrEqualTo(0));
      expect(notice.right, lessThanOrEqualTo(320));
      expect(notice.bottom, lessThanOrEqualTo(620));
      await tester.tap(find.byKey(const Key('dismiss-automatic-update')));
      await tester.pumpAndSettle();
    });
  }
}

class _Store implements AutomaticUpdateStore {
  AutomaticUpdateState state = const AutomaticUpdateState();
  @override
  Future<AutomaticUpdateState> read() async => state;
  @override
  Future<void> write(AutomaticUpdateState value) async {
    state = value;
  }
}

class _Lookup implements ReleaseLookup {
  static const update = ReleaseCheckOutcome(
    status: ReleaseCheckStatus.updateAvailable,
    versionLabel: '1.0.34',
    tag: 'v1.0.34',
    source: ReleaseSource.official,
  );
  int calls = 0;
  Future<ReleaseCheckOutcome>? pending;
  @override
  Future<ReleaseCheckOutcome> check({
    required String localVersion,
    required ReleaseCheckMode mode,
  }) async {
    calls++;
    return pending ?? update;
  }

  @override
  Future<Uri?> resolveReleasePage(ReleaseCheckOutcome outcome) async => null;
}
