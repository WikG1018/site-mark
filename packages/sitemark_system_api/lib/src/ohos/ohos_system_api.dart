import 'package:flutter/services.dart';

const MethodChannel ohosSystemChannel = MethodChannel('sitemark.system.ohos');

class OhosSystemApi {
  OhosSystemApi({MethodChannel? channel})
    : _channel = channel ?? ohosSystemChannel;

  final MethodChannel _channel;

  Future<T> _invoke<T>(String method, [dynamic args]) async {
    try {
      final result = await _channel.invokeMethod<T>(method, args);
      return result as T;
    } on MissingPluginException {
      throw PlatformException(code: 'ohos_not_ready', message: method);
    }
  }

  Future<String> createCameraTarget(String captureId) =>
      _invoke('createCameraTarget', {'captureId': captureId});

  Future<Map<Object?, Object?>> launchCamera(String captureId) =>
      _invoke('launchCamera', {'captureId': captureId});

  Future<Map<Object?, Object?>?> recoverCameraCapture() =>
      _invoke('recoverCameraCapture');

  Future<void> finishCameraCapture(String captureId, bool keepOriginal) =>
      _invoke('finishCameraCapture', {
        'captureId': captureId,
        'keepOriginal': keepOriginal,
      });

  Future<int> getLocationPermissionState() =>
      _invoke('getLocationPermissionState');

  Future<int> requestLocationPermission() =>
      _invoke('requestLocationPermission');

  Future<void> openApplicationSettings() => _invoke('openApplicationSettings');

  Future<Map<Object?, Object?>> inspectImage(String path) =>
      _invoke('inspectImage', {'path': path});

  Future<Map<Object?, Object?>> requestCurrentLocation(int timeoutMillis) =>
      _invoke('requestCurrentLocation', {'timeoutMillis': timeoutMillis});

  Future<Map<Object?, Object?>> publishJpeg(
    String sourcePath,
    String displayName,
    String captureId,
    String? publishedUri,
  ) => _invoke('publishJpeg', {
    'sourcePath': sourcePath,
    'displayName': displayName,
    'captureId': captureId,
    'publishedUri': publishedUri,
  });

  Future<List<Object?>?> recoverPublishJournals() =>
      _invoke('recoverPublishJournals');

  Future<void> clearPublishJournal(
    String captureId,
    String expectedContentUri,
  ) => _invoke('clearPublishJournal', {
    'captureId': captureId,
    'expectedContentUri': expectedContentUri,
  });

  Future<int> saveArchive(String sourcePath, String suggestedName) => _invoke(
    'saveArchive',
    {'sourcePath': sourcePath, 'suggestedName': suggestedName},
  );

  Future<void> deletePublishedImage(String contentUri) =>
      _invoke('deletePublishedImage', {'contentUri': contentUri});

  Future<String> detectGalleryAccess() => _invoke('detectGalleryAccess');
}
