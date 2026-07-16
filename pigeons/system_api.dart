import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'packages/sitemark_system_api/lib/src/system_api.g.dart',
    dartPackageName: 'sitemark_system_api',
    dartOptions: DartOptions(),
    kotlinOut:
        'packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/SystemApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'io.github.wikg1018.sitemark.system'),
  ),
)
enum CameraOutcome { captured, cancelled, failed }

enum LocationOutcome {
  precise,
  approximate,
  permissionDenied,
  servicesDisabled,
  timeout,
  unavailable,
}

class CameraCaptureResult {
  CameraCaptureResult({
    required this.outcome,
    required this.outputPath,
    this.errorMessage,
  });

  CameraOutcome outcome;
  String outputPath;
  String? errorMessage;
}

class RecoveredCameraCapture {
  RecoveredCameraCapture({
    required this.captureId,
    required this.outputPath,
    required this.hasContent,
  });

  String captureId;
  String outputPath;
  bool hasContent;
}

class LocationResult {
  LocationResult({
    required this.outcome,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.address,
    this.errorMessage,
  });

  LocationOutcome outcome;
  double? latitude;
  double? longitude;
  double? accuracyMeters;
  String? address;
  String? errorMessage;
}

class MediaPublishResult {
  MediaPublishResult({required this.contentUri});

  String contentUri;
}

@HostApi()
abstract class SiteMarkSystemApi {
  String createCameraTarget(String captureId);

  @async
  CameraCaptureResult launchCamera(String captureId);

  RecoveredCameraCapture? recoverCameraCapture();

  void finishCameraCapture(String captureId, bool keepOriginal);

  @async
  LocationResult requestCurrentLocation(int timeoutMillis);

  @async
  MediaPublishResult publishJpeg(String sourcePath, String displayName);

  @async
  void deletePublishedImage(String contentUri);
}
