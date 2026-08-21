/// Public API for the SiteMark system bridge plugin.
///
/// Exposes the Pigeon-generated [SiteMarkSystemApi] Dart host bindings and the
/// associated DTOs so that foreground Activities and headless FlutterEngines can
/// share the same MediaStore/camera/location bridge.
library;

export 'src/system_api.g.dart';
export 'src/ohos/capture_session_store.dart';
export 'src/ohos/capture_target_policy.dart';
export 'src/ohos/gallery_access.dart';
export 'src/ohos/gallery_store.dart';
export 'src/ohos/ohos_system_api.dart';
export 'src/ohos/publish_fallback_policy.dart';
export 'src/ohos/publish_journal_store.dart';
export 'src/ohos/share_cancel_policy.dart';
