import 'package:sitemark/domain/nas_sync.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

/// Runtime local-network permission for Android 17 LAN NAS (D-023).
///
/// iOS prompts via `NSLocalNetworkUsageDescription` on first use; HarmonyOS
/// has no equivalent runtime gate. Implementations must never throw into the
/// settings UI — map platform errors to [LocationPermissionState.denied].
abstract interface class LocalNetworkPermission {
  Future<LocationPermissionState> current();

  Future<LocationPermissionState> request();
}

/// Default: the system prompt is not available (tests, or hosts that are
/// not Android 17). Treated as granted so public-NAS and unit tests proceed.
class GrantingLocalNetworkPermission implements LocalNetworkPermission {
  const GrantingLocalNetworkPermission();

  @override
  Future<LocationPermissionState> current() async =>
      LocationPermissionState.granted;

  @override
  Future<LocationPermissionState> request() async =>
      LocationPermissionState.granted;
}

/// Host-api backed permission. Android 17 returns the real nearby-devices
/// state; older Android and iOS report granted.
class PigeonLocalNetworkPermission implements LocalNetworkPermission {
  PigeonLocalNetworkPermission({SiteMarkSystemApi? api})
    : _api = api ?? SiteMarkSystemApi();

  final SiteMarkSystemApi _api;

  @override
  Future<LocationPermissionState> current() async {
    try {
      return await _api.getLocalNetworkPermissionState();
    } on Object {
      return LocationPermissionState.denied;
    }
  }

  @override
  Future<LocationPermissionState> request() async {
    try {
      return await _api.requestLocalNetworkPermission();
    } on Object {
      return LocationPermissionState.denied;
    }
  }
}

/// Decides whether a NAS host may be contacted given the current permission.
class LocalNetworkAccess {
  const LocalNetworkAccess(this._permission);

  final LocalNetworkPermission _permission;

  /// Public destinations only need INTERNET. LAN destinations on Android 17
  /// need ACCESS_LOCAL_NETWORK; if the user refuses, the call is blocked so
  /// we do not record a misleading `connection_failed`.
  Future<bool> ensureForHost(String host) async {
    if (!isLanNasHost(host)) return true;
    var state = await _permission.current();
    if (state == LocationPermissionState.granted) return true;
    if (state == LocationPermissionState.denied) {
      state = await _permission.request();
    }
    return state == LocationPermissionState.granted;
  }
}
