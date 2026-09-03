import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'packages/sitemark_system_api/lib/src/system_api.g.dart',
    dartPackageName: 'sitemark_system_api',
    dartOptions: DartOptions(),
    kotlinOut:
        'packages/sitemark_system_api/android/src/main/kotlin/io/github/wikg1018/sitemark/system/SystemApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'io.github.wikg1018.sitemark.system'),
    swiftOut: 'packages/sitemark_system_api/ios/Classes/SystemApi.g.swift',
  ),
)
enum CameraOutcome { captured, cancelled, failed }

enum ArchiveSaveOutcome { saved, cancelled }

enum LocationOutcome {
  precise,
  approximate,
  permissionDenied,
  servicesDisabled,
  timeout,
  unavailable,
}

enum LocationPermissionState { granted, denied, permanentlyDenied }

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

class ImageMetadataResult {
  ImageMetadataResult({
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.mimeType,
    this.latitude,
    this.longitude,
  });

  int width;
  int height;
  int fileSizeBytes;
  String mimeType;
  double? latitude;
  double? longitude;
}

class MediaPublishResult {
  MediaPublishResult({required this.contentUri, this.supersededUris});

  String contentUri;

  /// Every prior MediaStore URI explicitly owned by this stable capture and
  /// superseded by the new content, including leftovers folded from an
  /// interrupted publish journal. Native code does not delete these rows;
  /// the caller must durably queue reference-checked, delete-only cleanup and
  /// must never re-publish or report failure because this list is non-empty.
  List<String>? supersededUris;
}

/// A natively persisted publish intent that survived a process death before
/// the caller committed the new URI to its database.
class RecoveredPublishJournal {
  RecoveredPublishJournal({
    required this.captureId,
    required this.contentUri,
    required this.supersededUris,
  });

  /// The stable capture identity the publish was keyed by. Callers
  /// reconcile their database row by this ID — NEVER by photo number,
  /// which a backup restore can duplicate across projects.
  String captureId;

  /// The finalized new MediaStore URI. It is already visible in the gallery.
  String contentUri;

  /// Every superseded candidate URI the publisher intended to delete. Some
  /// may already be gone — deletes are idempotent, so re-queuing them is
  /// safe and converges.
  List<String> supersededUris;
}

@HostApi()
abstract class SiteMarkSystemApi {
  String createCameraTarget(String captureId);

  @async
  CameraCaptureResult launchCamera(String captureId);

  RecoveredCameraCapture? recoverCameraCapture();

  void finishCameraCapture(String captureId, bool keepOriginal);

  LocationPermissionState getLocationPermissionState();

  @async
  LocationPermissionState requestLocationPermission();

  /// Android 17 LAN NAS (ACCESS_LOCAL_NETWORK). Older Android and iOS
  /// report [LocationPermissionState.granted] — iOS prompts via Info.plist
  /// on first local-network use.
  LocationPermissionState getLocalNetworkPermissionState();

  @async
  LocationPermissionState requestLocalNetworkPermission();

  void openApplicationSettings();

  @async
  ImageMetadataResult inspectImage(String path);

  @async
  LocationResult requestCurrentLocation(int timeoutMillis);

  /// Publishes [sourcePath] into the system gallery under [displayName].
  ///
  /// [captureId] is the caller's stable identity for the capture: it keys
  /// the durable publish journal and disambiguates records that share a
  /// photo number after a backup restore. [publishedUri] is the exact
  /// previously published URI this publish replaces — the native side
  /// reports ONLY that URI (plus any leftover journaled URI of the same
  /// capture) as a pending cleanup candidate; it never deletes gallery
  /// rows itself, because a legacy upgrade can leave TWO records sharing
  /// one URI and only the caller can check cross-record references.
  @async
  MediaPublishResult publishJpeg(
    String sourcePath,
    String displayName,
    String captureId,
    String? publishedUri,
  );

  List<RecoveredPublishJournal>? recoverPublishJournals();

  /// Clears the capture's publish journal ONLY when it still records
  /// [expectedContentUri]. An older operation whose newer same-capture
  /// publish already overwrote the journal must NOT clear the newer
  /// entry, or the newer publish would become unrecoverable.
  void clearPublishJournal(String captureId, String expectedContentUri);

  @async
  ArchiveSaveOutcome saveArchive(String sourcePath, String suggestedName);

  @async
  void deletePublishedImage(String contentUri);
}
