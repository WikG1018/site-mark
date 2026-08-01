// test/features/settings/sections/notification_section_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/features/settings/sections/notification_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';
import 'package:sitemark/platform/notification_service.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required CompletionNotificationService notifications,
  }) async {
    await database.getAppSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          completionNotificationServiceProvider.overrideWithValue(
            notifications,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const NotificationSectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('completion notification switch persists when permission is '
      'granted', (tester) async {
    final notifications = _FakeCompletionNotificationService(
      permissionResult: true,
    );
    await pumpScreen(tester, notifications: notifications);
    final toggle = find.byKey(const Key('completion-notification-switch'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(notifications.requestPermissionCount, 1);
    expect(
      (await database.getAppSettings()).completionNotificationsEnabled,
      isTrue,
    );
  });

  testWidgets('completion notification switch stays off and shows a snackbar '
      'when permission is denied', (tester) async {
    final notifications = _FakeCompletionNotificationService(
      permissionResult: false,
    );
    await pumpScreen(tester, notifications: notifications);
    final toggle = find.byKey(const Key('completion-notification-switch'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(notifications.requestPermissionCount, 1);
    expect(
      (await database.getAppSettings()).completionNotificationsEnabled,
      isFalse,
    );
    expect(find.text('通知权限被拒绝，可在系统设置中开启'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });
}

class _FakeCompletionNotificationService
    implements CompletionNotificationService {
  _FakeCompletionNotificationService({this.permissionResult = true});

  bool permissionResult;
  int requestPermissionCount = 0;

  @override
  Future<void> initialize(
    void Function(String deepLinkPath) onTapDeepLink,
  ) async {}

  @override
  Future<bool> requestPermission() async {
    requestPermissionCount++;
    return permissionResult;
  }

  @override
  Future<void> showCaptureReady({
    required String projectId,
    required String captureId,
    required String photoNumber,
  }) async {}

  @override
  Future<void> setEnabled(bool enabled) async {}
}
