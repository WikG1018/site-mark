import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/release_check.dart';
import 'package:sitemark/features/settings/sections/app_update_panel.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/app_update_controller.dart';

void main() {
  final asset = ReleaseDownload(
    tag: 'v1.0.32',
    variant: ReleaseApkVariant.arm64,
    sizeBytes: 100,
    sha256: 'a' * 64,
  );
  Future<void> pump(WidgetTester tester, AppUpdateController controller) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppUpdatePanel(
              controller: controller,
              mode: ReleaseCheckMode.auto,
              available: asset,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('progress is visible and can be cancelled on narrow screens', (
    tester,
  ) async {
    final c = AppUpdateController()
      ..download = asset
      ..phase = AppUpdatePhase.downloading
      ..receivedBytes = 50;
    addTearDown(c.dispose);
    await pump(tester, c);
    expect(find.textContaining('50%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('cancel-update-download')));
    await tester.pump();
    expect(c.phase, AppUpdatePhase.cancelled);
    expect(find.text('下载已取消。'), findsOneWidget);
  });
  testWidgets(
    'install permission is explained without opening settings automatically',
    (tester) async {
      var settingsOpened = 0;
      final c =
          AppUpdateController(
              openPermissionSettings: () async {
                settingsOpened++;
              },
            )
            ..download = asset
            ..phase = AppUpdatePhase.permissionRequired
            ..readyPath = '/test.apk';
      addTearDown(c.dispose);
      await pump(tester, c);
      expect(find.textContaining('Android 要求'), findsOneWidget);
      expect(settingsOpened, 0);
      final allow = find.byKey(const Key('allow-update-installation'));
      await tester.ensureVisible(allow);
      await tester.tap(allow);
      await tester.pump();
      expect(settingsOpened, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
