import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sitemark/platform/notification_service.dart';

/// Production [CompletionNotificationService] backed by
/// `flutter_local_notifications`.
///
/// The service lives below the widget tree and is also constructed inside
/// the WorkManager background isolate, so no `BuildContext` (and therefore
/// no [AppStrings] lookup) is available for the channel name/description or
/// the notification title/body. Copy is instead resolved from the persisted
/// `AppSetting.localeCode`, pushed in via [setLocale] from both isolates;
/// when the user has not picked an explicit language (null), it falls back
/// to [WidgetsBinding.instance.platformDispatcher.locale]. SiteMark only
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

  /// In-memory copy of the persisted `AppSetting.localeCode`; null means the
  /// user did not pick an explicit language and the device locale decides.
  String? _localeCode;

  static const String _channelId = 'capture_ready';
  static const String _nasChannelId = 'nas_sync';
  static const int _nasNotificationId = 0x4e4153; // 'NAS'

  @override
  Future<void> setLocale(String? localeCode) async {
    _localeCode = localeCode;
  }

  bool get _isZh => switch (_localeCode) {
    'zh' => true,
    'en' => false,
    _ => WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh',
  };

  AndroidNotificationChannel get _channel => AndroidNotificationChannel(
    _channelId,
    _isZh ? '照片处理' : 'Photo processing',
    description: _isZh
        ? '后台照片处理完成时通知'
        : 'Notifies when background photo processing completes',
    importance: Importance.high,
  );

  AndroidNotificationChannel get _nasChannel => AndroidNotificationChannel(
    _nasChannelId,
    _isZh ? 'NAS 同步' : 'NAS sync',
    description: _isZh ? 'NAS 上传失败时通知' : 'Notifies when NAS uploads fail',
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
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_nasChannel);
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
    if (granted != null) return granted;
    // iOS authorizes at the settings toggle (parity with Android's timing)
    // instead of implicitly at the first notification post.
    final iosGranted = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    return iosGranted ?? true;
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
  Future<void> showNasSyncFailed({
    required int failedCount,
    required String? failureCode,
  }) async {
    // NAS failures are always worth surfacing while sync itself is on; they
    // are not gated by the photo-completion switch.
    if (failedCount <= 0) return;
    final channel = _nasChannel;
    final body = switch (failureCode) {
      'auth_failed' =>
        _isZh
            ? '用户名或密码不正确，请到设置中修改'
            : 'Incorrect username or password. Update it in settings.',
      'config_invalid' =>
        _isZh
            ? '配置不完整，请检查服务器与密码'
            : 'Configuration is incomplete. Check server and password.',
      'host_key_changed' =>
        _isZh
            ? '服务器指纹已变化，请重新测试连接'
            : 'Server fingerprint changed. Run the connection test again.',
      'quota_insufficient' =>
        _isZh ? 'NAS 存储空间不足' : 'The NAS is out of storage space.',
      _ =>
        _isZh
            ? '$failedCount 张照片上传失败，点击查看'
            : '$failedCount photo(s) failed to upload. Tap to review.',
    };
    await _plugin.show(
      id: _nasNotificationId,
      title: _isZh ? 'NAS 同步失败' : 'NAS sync failed',
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: nasSettingsDeepLink,
    );
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
  }
}
