import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sitemark/platform/notification_service.dart';

/// Production [CompletionNotificationService] backed by
/// `flutter_local_notifications`.
///
/// The service lives below the widget tree and is also constructed inside
/// the WorkManager background isolate, so no `BuildContext` (and therefore
/// no [AppStrings] lookup) is available for the channel name/description or
/// the notification title/body. Copy is instead resolved from
/// [WidgetsBinding.instance.platformDispatcher.locale]: SiteMark only
/// supports zh/en, so a language-code switch with English as the fallback
/// is sufficient.
final class LocalNotificationService implements CompletionNotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// In-memory send gate driven by the persisted
  /// `AppSetting.completionNotificationsEnabled` switch; defaults to off so
  /// nothing is posted before the settings stream delivers the first value.
  bool _enabled = false;

  static const String _channelId = 'capture_ready';

  static bool get _isZh =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh';

  static AndroidNotificationChannel get _channel => AndroidNotificationChannel(
    _channelId,
    _isZh ? '照片处理' : 'Photo processing',
    description: _isZh
        ? '后台照片处理完成时通知'
        : 'Notifies when background photo processing completes',
    importance: Importance.high,
  );

  @override
  Future<void> initialize(
    void Function(String deepLinkPath) onTapDeepLink,
  ) async {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    void handlePayload(String? payload) {
      if (payload != null && payload.isNotEmpty) {
        onTapDeepLink(payload);
      }
    }

    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) =>
          handlePayload(response.payload),
    );
    // The channel must exist on Android 8+ before the first notification is
    // posted; creating it is idempotent.
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    // Cold start: when the app was launched by tapping a notification, the
    // response does not go through `onDidReceiveNotificationResponse` and
    // must be read back here instead.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    handlePayload(launchDetails?.notificationResponse?.payload);
  }

  @override
  Future<bool> requestPermission() async {
    // Only Android 13+ has a runtime notification permission; other
    // platforms resolve to null and are treated as already granted.
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    return granted ?? true;
  }

  @override
  Future<void> showCaptureReady({
    required String projectId,
    required String captureId,
    required String photoNumber,
  }) async {
    if (!_enabled) return;
    final channel = _channel;
    await _plugin.show(
      id: captureId.hashCode,
      title: _isZh ? '照片处理完成' : 'Photo ready',
      body: _isZh
          ? '照片 $photoNumber 已完成处理，点击查看'
          : 'Photo $photoNumber is ready. Tap to view.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: captureReadyDeepLink(projectId, captureId),
    );
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
  }
}
