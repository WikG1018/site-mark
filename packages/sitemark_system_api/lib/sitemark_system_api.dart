/// Public API for the SiteMark system bridge plugin.
///
/// Exposes the Pigeon-generated [SiteMarkSystemApi] Dart host bindings and the
/// associated DTOs so that foreground Activities and headless FlutterEngines can
/// share the same MediaStore/camera/location bridge.
library;

export 'src/system_api.g.dart';
