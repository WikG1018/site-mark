import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sitemark/platform/local_notification_service.dart';

/// Records the iOS permission request so the toggle-time authorization
/// contract can be asserted without a real Darwin platform channel.
class _FakeIOSNotificationsPlugin extends IOSFlutterLocalNotificationsPlugin {
  int calls = 0;
  bool? lastAlert;
  bool? lastBadge;
  bool? lastSound;
  bool? lastProvisional;
  bool granted = true;

  @override
  Future<bool?> requestPermissions({
    bool sound = false,
    bool alert = false,
    bool badge = false,
    bool provisional = false,
    bool critical = false,
    bool carPlay = false,
    bool providesAppNotificationSettings = false,
  }) async {
    calls++;
    lastAlert = alert;
    lastBadge = badge;
    lastSound = sound;
    lastProvisional = provisional;
    return granted;
  }
}

/// Records the Android permission request so the existing toggle-time
/// contract keeps a regression test once the iOS branch lands beside it.
class _FakeAndroidNotificationsPlugin
    extends AndroidFlutterLocalNotificationsPlugin {
  int calls = 0;
  bool granted = true;

  @override
  Future<bool?> requestNotificationsPermission() async {
    calls++;
    return granted;
  }
}

void main() {
  // The platform-interface instance is `late` and only endorsed on real
  // platforms, so every test installs the fake it needs explicitly.
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'requests alert, badge, and sound permissions when enabled on iOS',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final fake = _FakeIOSNotificationsPlugin();
      FlutterLocalNotificationsPlatform.instance = fake;

      final granted = await LocalNotificationService().requestPermission();

      expect(granted, isTrue);
      expect(fake.calls, 1);
      expect(fake.lastAlert, isTrue);
      expect(fake.lastBadge, isTrue);
      expect(fake.lastSound, isTrue);
      // Provisional would deliver quietly without a real prompt; the
      // toggle-time request must be a real authorization like Android's.
      expect(fake.lastProvisional, isFalse);
    },
  );

  test('reports denial from the iOS permission request', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final fake = _FakeIOSNotificationsPlugin()..granted = false;
    FlutterLocalNotificationsPlatform.instance = fake;

    final granted = await LocalNotificationService().requestPermission();

    expect(granted, isFalse);
  });

  test(
    'Android keeps requesting notifications permission when enabled',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final fake = _FakeAndroidNotificationsPlugin();
      FlutterLocalNotificationsPlatform.instance = fake;

      final granted = await LocalNotificationService().requestPermission();

      expect(granted, isTrue);
      expect(fake.calls, 1);
    },
  );

  test('resolves to granted when no platform implementation matches', () async {
    // An Android override with an iOS-only fake mirrors environments where
    // the concrete plugin cannot answer: no prompt is possible, so the gate
    // stays open exactly like the pre-existing behavior.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance = _FakeIOSNotificationsPlugin();

    final granted = await LocalNotificationService().requestPermission();

    expect(granted, isTrue);
  });
}
