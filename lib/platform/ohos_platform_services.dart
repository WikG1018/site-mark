import 'dart:ui';

import 'package:sitemark/platform/notification_service.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

class OhosPlatformServices implements PlatformServices {
  OhosPlatformServices({OhosSystemApi? api}) : _api = api ?? OhosSystemApi();

  final OhosSystemApi _api;

  @override
  Future<String> createCameraTarget(String captureId) {
    return _api.createCameraTarget(captureId);
  }

  @override
  Future<void> deletePublishedImage(String contentUri) {
    return _api.deletePublishedImage(contentUri);
  }

  @override
  Future<void> finishCameraCapture(String captureId, bool keepOriginal) {
    return _api.finishCameraCapture(captureId, keepOriginal);
  }

  @override
  Future<CameraCaptureResult> launchCamera(String captureId) async {
    return _decodeCameraCaptureResult(await _api.launchCamera(captureId));
  }

  @override
  Future<PublishJpegOutcome> publishJpeg(
    String sourcePath,
    String displayName,
    String captureId,
    String? publishedUri,
  ) async {
    final result = _asStringKeyedMap(
      await _api.publishJpeg(sourcePath, displayName, captureId, publishedUri),
    );
    return PublishJpegOutcome(
      contentUri: result['contentUri']! as String,
      supersededUris: _stringList(result['supersededUris']),
    );
  }

  @override
  Future<List<RecoveredPublishJournalEntry>> recoverPublishJournals() async {
    final journals = await _api.recoverPublishJournals();
    if (journals == null) return const [];
    return [
      for (final journal in journals)
        _decodeRecoveredPublishJournalEntry(journal),
    ];
  }

  @override
  Future<void> clearPublishJournal(
    String captureId,
    String expectedContentUri,
  ) {
    return _api.clearPublishJournal(captureId, expectedContentUri);
  }

  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() async {
    final result = await _api.recoverCameraCapture();
    if (result == null) return null;
    return _decodeRecoveredCameraCapture(result);
  }

  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) async {
    return _decodeLocationResult(
      await _api.requestCurrentLocation(timeoutMillis),
    );
  }

  @override
  Future<LocationPermissionState> getLocationPermissionState() async {
    return LocationPermissionState.values[await _api
        .getLocationPermissionState()];
  }

  @override
  Future<LocationPermissionState> requestLocationPermission() async {
    return LocationPermissionState.values[await _api
        .requestLocationPermission()];
  }

  @override
  Future<void> openApplicationSettings() {
    return _api.openApplicationSettings();
  }

  @override
  Future<ImageMetadataResult> inspectImage(String path) async {
    return _decodeImageMetadataResult(await _api.inspectImage(path));
  }
}

class OhosArchiveSaveService implements ArchiveSaveService {
  OhosArchiveSaveService({OhosSystemApi? api}) : _api = api ?? OhosSystemApi();

  final OhosSystemApi _api;

  @override
  Future<ArchiveSaveOutcome> saveArchive(String sourcePath) async {
    final suggestedName = Uri.file(sourcePath).pathSegments.last;
    final outcome = await _api.saveArchive(sourcePath, suggestedName);
    return ArchiveSaveOutcome.values[outcome];
  }
}

class OhosArchivePickService implements ArchivePickService {
  OhosArchivePickService({OhosSystemApi? api}) : _api = api ?? OhosSystemApi();

  final OhosSystemApi _api;

  @override
  Future<String?> pickArchive() async {
    final path = await _api.pickArchive();
    if (path.isEmpty) return null;
    return path;
  }
}

class OhosShareFileService implements ShareFileService {
  OhosShareFileService({OhosSystemApi? api}) : _api = api ?? OhosSystemApi();

  final OhosSystemApi _api;

  @override
  Future<void> shareFile(String path) {
    return _api.shareFile(path);
  }
}

class OhosCompletionNotificationService implements CompletionNotificationService {
  OhosCompletionNotificationService({OhosSystemApi? api})
    : _api = api ?? OhosSystemApi();

  final OhosSystemApi _api;
  bool _enabled = false;

  @override
  Future<void> initialize(void Function(String deepLinkPath) onTapDeepLink) {
    return _api.listenNotificationTap(onTapDeepLink);
  }

  @override
  Future<bool> requestPermission() {
    return _api.requestEnableNotification();
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
  }

  @override
  Future<void> showCaptureReady({
    required String projectId,
    required String captureId,
    required String photoNumber,
  }) async {
    if (!_enabled) {
      return;
    }
    final zh = PlatformDispatcher.instance.locale.languageCode == 'zh';
    await _api.publishCaptureReady(
      title: zh ? '照片处理完成' : 'Photo ready',
      text: zh
          ? '照片 $photoNumber 已完成处理，点击查看'
          : 'Photo $photoNumber is ready. Tap to view.',
      deepLink: captureReadyDeepLink(projectId, captureId),
    );
  }
}

CameraCaptureResult _decodeCameraCaptureResult(Map<Object?, Object?> raw) {
  final result = _asStringKeyedMap(raw);
  return CameraCaptureResult(
    outcome: CameraOutcome.values[result['outcome']! as int],
    outputPath: result['outputPath']! as String,
    errorMessage: result['errorMessage'] as String?,
  );
}

RecoveredCameraCapture _decodeRecoveredCameraCapture(
  Map<Object?, Object?> raw,
) {
  final result = _asStringKeyedMap(raw);
  return RecoveredCameraCapture(
    captureId: result['captureId']! as String,
    outputPath: result['outputPath']! as String,
    hasContent: result['hasContent']! as bool,
  );
}

LocationResult _decodeLocationResult(Map<Object?, Object?> raw) {
  final result = _asStringKeyedMap(raw);
  return LocationResult(
    outcome: LocationOutcome.values[result['outcome']! as int],
    latitude: (result['latitude'] as num?)?.toDouble(),
    longitude: (result['longitude'] as num?)?.toDouble(),
    accuracyMeters: (result['accuracyMeters'] as num?)?.toDouble(),
    address: result['address'] as String?,
    errorMessage: result['errorMessage'] as String?,
  );
}

RecoveredPublishJournalEntry _decodeRecoveredPublishJournalEntry(Object? raw) {
  final result = _asStringKeyedMap(raw);
  return RecoveredPublishJournalEntry(
    captureId: result['captureId']! as String,
    contentUri: result['contentUri']! as String,
    supersededUris: _stringList(result['supersededUris']),
  );
}

ImageMetadataResult _decodeImageMetadataResult(Map<Object?, Object?> raw) {
  final result = _asStringKeyedMap(raw);
  return ImageMetadataResult(
    width: result['width']! as int,
    height: result['height']! as int,
    fileSizeBytes: result['fileSizeBytes']! as int,
    mimeType: result['mimeType']! as String,
    latitude: (result['latitude'] as num?)?.toDouble(),
    longitude: (result['longitude'] as num?)?.toDouble(),
  );
}

Map<String, Object?> _asStringKeyedMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  throw FormatException('expected map, got ${value.runtimeType}');
}

List<String> _stringList(Object? value) {
  if (value == null) return const [];
  if (value is List) {
    return [for (final item in value) item! as String];
  }
  throw FormatException('expected list, got ${value.runtimeType}');
}
