import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

/// Immutable snapshot of the location-permission UI state derived from the
/// current platform permission and the persisted "prompt dismissed" flag.
///
/// The capture form and global settings screen read [permission] to decide
/// whether to attempt a location read, and [showExplanation] to decide whether
/// to render the non-blocking explanation card. The card itself uses
/// [openSettings] to swap its call-to-action label once the platform no longer
/// allows an in-app permission request.
class LocationPermissionViewState {
  const LocationPermissionViewState({
    required this.permission,
    required this.showExplanation,
  });

  final LocationPermissionState permission;
  final bool showExplanation;

  bool get locationEnabled => permission == LocationPermissionState.granted;
  bool get openSettings =>
      permission == LocationPermissionState.permanentlyDenied;
}

/// Coordinates the non-blocking location-permission UX between the platform
/// bridge, the persisted `app_settings` row, and the screens that surface the
/// explanation card.
///
/// The capture button path never calls into this service: it only reads the
/// cached [LocationPermissionViewState] to decide whether the workflow may
/// attempt a location read. Runtime permission requests happen exclusively
/// through [request] (the "Enable location" call-to-action) or
/// [openSettings] (when the platform reports `permanentlyDenied`).
class LocationPermissionService {
  const LocationPermissionService({
    required this.database,
    required this.platform,
  });

  final AppDatabase database;
  final PlatformServices platform;

  /// Reads the current permission state and the persisted dismissal flag, then
  /// returns the derived view state. Granted permission always hides the
  /// explanation regardless of the dismissal flag.
  Future<LocationPermissionViewState> load() async {
    final permission = await platform.getLocationPermissionState();
    final settings = await database.getAppSettings();
    return LocationPermissionViewState(
      permission: permission,
      showExplanation:
          permission != LocationPermissionState.granted &&
          !settings.locationPermissionPromptDismissed,
    );
  }

  /// Triggers the in-app runtime permission request. If the user does not
  /// grant permission, the dismissal flag is persisted so the explanation card
  /// does not reappear on the next [load]. The returned view state always
  /// hides the explanation: the user has now interacted with the prompt.
  Future<LocationPermissionViewState> request() async {
    final result = await platform.requestLocationPermission();
    if (result != LocationPermissionState.granted) {
      await database.updateAppSettings(locationPermissionPromptDismissed: true);
    }
    return LocationPermissionViewState(
      permission: result,
      showExplanation: false,
    );
  }

  /// Persists the dismissal flag so the explanation card stays hidden across
  /// reloads without issuing a runtime permission request.
  Future<void> dismiss() => database
      .updateAppSettings(locationPermissionPromptDismissed: true)
      .then((_) {});

  /// Opens the host OS application-settings page so the user can grant a
  /// permission the platform reports as `permanentlyDenied`.
  Future<void> openSettings() => platform.openApplicationSettings();
}
