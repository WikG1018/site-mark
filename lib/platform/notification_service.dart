import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Completion-notification abstraction.
///
/// The production implementation (backed by `flutter_local_notifications`)
/// is wired in `main.dart` via [completionNotificationServiceProvider]
/// override. Tests override the provider with fakes.
abstract class CompletionNotificationService {
  /// Wires the plugin and registers the deep-link tap callback. The callback
  /// receives an in-app path such as `/projects/{pid}/captures/{cid}`.
  Future<void> initialize(void Function(String deepLinkPath) onTapDeepLink);

  /// Requests the Android 13+ POST_NOTIFICATIONS runtime permission.
  /// Returns `true` when notifications are (or remain) allowed.
  Future<bool> requestPermission();

  /// Posts a "photo ready" local notification whose tap deep-links to the
  /// capture detail page.
  Future<void> showCaptureReady({
    required String projectId,
    required String captureId,
    required String photoNumber,
  });

  /// Persists the master on/off switch used as the send gate.
  Future<void> setEnabled(bool enabled);
}

/// Fallback when the production notification service is not wired.
/// HarmonyOS product HAP uses OhosCompletionNotificationService instead.
final class NoopCompletionNotificationService
    implements CompletionNotificationService {
  @override
  Future<void> initialize(
    void Function(String deepLinkPath) onTapDeepLink,
  ) async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showCaptureReady({
    required String projectId,
    required String captureId,
    required String photoNumber,
  }) async {}

  @override
  Future<void> setEnabled(bool enabled) async {}
}

/// Overridden in `main.dart` with the production implementation.
final completionNotificationServiceProvider =
    Provider<CompletionNotificationService>((ref) {
      throw UnimplementedError(
        'completionNotificationServiceProvider must be overridden',
      );
    });

/// Builds the in-app deep-link path carried as the notification payload.
/// Tapping a completion notification pushes this path onto the router,
/// landing on the capture detail page.
String captureReadyDeepLink(String projectId, String captureId) =>
    '/projects/$projectId/captures/$captureId';
