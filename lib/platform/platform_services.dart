import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;
import 'package:sitemark/src/rust/frb_generated.dart';

Future<void>? _foregroundRustInitialization;

/// Initializes the foreground Rust bridge once per isolate.
///
/// The first call is started after [runApp] so it cannot extend Android's
/// system splash. Every foreground image operation also awaits this same
/// future, keeping immediate user actions safe.
Future<void> initializeForegroundRust() {
  final cached = _foregroundRustInitialization;
  if (cached != null) return cached;

  final created = RustLib.init();
  _foregroundRustInitialization = created;
  created.then<void>(
    (_) {},
    onError: (Object error, StackTrace stackTrace) {
      if (identical(_foregroundRustInitialization, created)) {
        _foregroundRustInitialization = null;
      }
    },
  );
  return created;
}

abstract interface class PlatformServices {
  Future<String> createCameraTarget(String captureId);

  Future<CameraCaptureResult> launchCamera(String captureId);

  Future<RecoveredCameraCapture?> recoverCameraCapture();

  Future<void> finishCameraCapture(String captureId, bool keepOriginal);

  Future<LocationResult> requestCurrentLocation(int timeoutMillis);

  Future<String> publishJpeg(String sourcePath, String displayName);

  Future<void> deletePublishedImage(String contentUri);

  Future<LocationPermissionState> getLocationPermissionState();

  Future<LocationPermissionState> requestLocationPermission();

  Future<void> openApplicationSettings();

  Future<ImageMetadataResult> inspectImage(String path);
}

class PigeonPlatformServices implements PlatformServices {
  PigeonPlatformServices({SiteMarkSystemApi? api})
    : _api = api ?? SiteMarkSystemApi();

  final SiteMarkSystemApi _api;

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
  Future<CameraCaptureResult> launchCamera(String captureId) {
    return _api.launchCamera(captureId);
  }

  @override
  Future<String> publishJpeg(String sourcePath, String displayName) async {
    final result = await _api.publishJpeg(sourcePath, displayName);
    return result.contentUri;
  }

  @override
  Future<RecoveredCameraCapture?> recoverCameraCapture() {
    return _api.recoverCameraCapture();
  }

  @override
  Future<LocationResult> requestCurrentLocation(int timeoutMillis) {
    return _api.requestCurrentLocation(timeoutMillis);
  }

  @override
  Future<LocationPermissionState> getLocationPermissionState() {
    return _api.getLocationPermissionState();
  }

  @override
  Future<LocationPermissionState> requestLocationPermission() {
    return _api.requestLocationPermission();
  }

  @override
  Future<void> openApplicationSettings() {
    return _api.openApplicationSettings();
  }

  @override
  Future<ImageMetadataResult> inspectImage(String path) {
    return _api.inspectImage(path);
  }
}

abstract interface class ImagePipeline {
  Future<rust.ExportProjectResult> export(rust.ExportProjectRequest request);

  Future<rust.ExportProjectResult> exportSelection(
    rust.ExportSelectionRequest request,
  );

  Future<rust.ProjectArchivePreview> readProjectArchive(String zipPath);

  Future<rust.ExtractedArchivePhoto> extractArchivePhoto(
    rust.ExtractArchivePhotoRequest request,
  );

  Future<String> sha256(String path);

  Future<rust.RenderPhotoResult> render(rust.RenderPhotoRequest request);
}

abstract interface class ProjectBundlePipeline {
  Future<rust.ExportProjectResult> exportBundle(
    rust.ExportProjectBundleRequest request,
  );

  Future<rust.ProjectBundlePreview> readBundle(String zipPath);

  Future<void> extractBundleEntry(
    rust.ExtractProjectBundleEntryRequest request,
  );
}

enum ImagePipelineFailureKind { notFound, transientIo, invalidData }

class ImagePipelineException implements Exception {
  const ImagePipelineException(this.kind, this.message);

  final ImagePipelineFailureKind kind;
  final String message;

  static ImagePipelineException? tryParseRustError(Object error) {
    final message = error.toString();
    const prefixes = <String, ImagePipelineFailureKind>{
      'not_found:': ImagePipelineFailureKind.notFound,
      'io:': ImagePipelineFailureKind.transientIo,
      'invalid_data:': ImagePipelineFailureKind.invalidData,
    };
    for (final entry in prefixes.entries) {
      if (message.startsWith(entry.key)) {
        return ImagePipelineException(
          entry.value,
          message.substring(entry.key.length),
        );
      }
    }
    return null;
  }

  @override
  String toString() => message;
}

class RustImagePipeline implements ImagePipeline {
  @override
  Future<rust.ExportProjectResult> export(rust.ExportProjectRequest request) {
    return _translateRustError(() => rust.exportProject(request: request));
  }

  @override
  Future<rust.ExportProjectResult> exportSelection(
    rust.ExportSelectionRequest request,
  ) {
    return _translateRustError(() => rust.exportSelection(request: request));
  }

  @override
  Future<rust.ProjectArchivePreview> readProjectArchive(String zipPath) {
    return _translateRustError(() => rust.readProjectArchive(zipPath: zipPath));
  }

  @override
  Future<rust.ExtractedArchivePhoto> extractArchivePhoto(
    rust.ExtractArchivePhotoRequest request,
  ) {
    return _translateRustError(
      () => rust.extractArchivePhoto(request: request),
    );
  }

  @override
  Future<rust.RenderPhotoResult> render(rust.RenderPhotoRequest request) {
    return _translateRustError(() => rust.renderPhoto(request: request));
  }

  @override
  Future<String> sha256(String path) {
    return _translateRustError(() => rust.sha256File(path: path));
  }

  Future<T> _translateRustError<T>(Future<T> Function() operation) async {
    try {
      await initializeForegroundRust();
      return await operation();
    } catch (error) {
      final translated = ImagePipelineException.tryParseRustError(error);
      if (translated != null) throw translated;
      rethrow;
    }
  }
}

class RustProjectBundlePipeline implements ProjectBundlePipeline {
  @override
  Future<rust.ExportProjectResult> exportBundle(
    rust.ExportProjectBundleRequest request,
  ) {
    return _translateRustError(
      () => rust.exportProjectBundle(request: request),
    );
  }

  @override
  Future<void> extractBundleEntry(
    rust.ExtractProjectBundleEntryRequest request,
  ) {
    return _translateRustError(
      () => rust.extractProjectBundleEntry(request: request),
    );
  }

  @override
  Future<rust.ProjectBundlePreview> readBundle(String zipPath) {
    return _translateRustError(() => rust.readProjectBundle(zipPath: zipPath));
  }

  Future<T> _translateRustError<T>(Future<T> Function() operation) async {
    try {
      await initializeForegroundRust();
      return await operation();
    } catch (error) {
      final translated = ImagePipelineException.tryParseRustError(error);
      if (translated != null) throw translated;
      rethrow;
    }
  }
}

abstract interface class CaptureOutputPaths {
  Future<String> renderedPhotoPath(String captureId);
}

class AppCaptureOutputPaths implements CaptureOutputPaths {
  AppCaptureOutputPaths({Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;
  Future<Directory>? _renderedDirectory;

  @override
  Future<String> renderedPhotoPath(String captureId) async {
    final directory = await _resolveRenderedDirectory();
    return '${directory.path}${Platform.pathSeparator}$captureId.jpg';
  }

  Future<Directory> _resolveRenderedDirectory() {
    final cached = _renderedDirectory;
    if (cached != null) return cached;

    final created = _createRenderedDirectory();
    _renderedDirectory = created;
    created.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_renderedDirectory, created)) {
          _renderedDirectory = null;
        }
      },
    );
    return created;
  }

  Future<Directory> _createRenderedDirectory() async {
    final root = await _documentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}rendered',
    );
    await directory.create(recursive: true);
    return directory;
  }
}

abstract interface class ProjectExportPaths {
  Future<String> projectZipPath(String projectId);
}

/// Resolves app-private original photo paths for captures created outside
/// the system-camera flow (e.g. restored from a backup archive). Mirrors the
/// `<filesDir>/originals/<captureId>.jpg` layout the Android host uses for
/// camera originals; on Android, `getApplicationSupportDirectory()` maps to
/// the app `filesDir`.
abstract interface class OriginalPhotoPaths {
  Future<String> originalPhotoPath(String captureId);
}

class AppOriginalPhotoPaths implements OriginalPhotoPaths {
  AppOriginalPhotoPaths({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;
  Future<Directory>? _originalsDirectory;

  @override
  Future<String> originalPhotoPath(String captureId) async {
    final directory = await _resolveOriginalsDirectory();
    return '${directory.path}${Platform.pathSeparator}$captureId.jpg';
  }

  Future<Directory> _resolveOriginalsDirectory() {
    final cached = _originalsDirectory;
    if (cached != null) return cached;

    final created = _createOriginalsDirectory();
    _originalsDirectory = created;
    created.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_originalsDirectory, created)) {
          _originalsDirectory = null;
        }
      },
    );
    return created;
  }

  Future<Directory> _createOriginalsDirectory() async {
    final root = await _supportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}originals',
    );
    await directory.create(recursive: true);
    return directory;
  }
}

class AppProjectExportPaths implements ProjectExportPaths {
  @override
  Future<String> projectZipPath(String projectId) async {
    final safeId = projectId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}exports');
    await directory.create(recursive: true);
    return '${directory.path}${Platform.pathSeparator}sitemark-$safeId.zip';
  }
}

abstract interface class SelectionExportPaths {
  Future<String> selectionZipPath();
}

class AppSelectionExportPaths implements SelectionExportPaths {
  @override
  Future<String> selectionZipPath() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}exports');
    await directory.create(recursive: true);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    return '${directory.path}${Platform.pathSeparator}'
        'sitemark-selection-$timestamp.zip';
  }
}

abstract interface class ProjectBundlePaths {
  Future<String> backupZipPath();

  Future<String> exportStagingDirectory(String bundleId);

  Future<String> restoreStagingDirectory(String bundleId);

  Future<String> projectArchivePath(String stagingDirectory, String projectId);
}

class AppProjectBundlePaths implements ProjectBundlePaths {
  AppProjectBundlePaths({
    Future<Directory> Function()? documentsDirectory,
    DateTime Function()? clock,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _documentsDirectory;
  final DateTime Function() _clock;

  @override
  Future<String> backupZipPath() async {
    final root = await _documentsDirectory();
    final exports = Directory('${root.path}${Platform.pathSeparator}exports');
    await exports.create(recursive: true);
    final timestamp = _clock().toUtc().millisecondsSinceEpoch;
    return '${exports.path}${Platform.pathSeparator}'
        'sitemark-backup-$timestamp.zip';
  }

  @override
  Future<String> exportStagingDirectory(String bundleId) async {
    final path = await _stagingPath('bundle-export', bundleId);
    await Directory(path).create(recursive: true);
    return path;
  }

  @override
  Future<String> restoreStagingDirectory(String bundleId) {
    return _stagingPath('bundle-restore', bundleId);
  }

  @override
  Future<String> projectArchivePath(
    String stagingDirectory,
    String projectId,
  ) async {
    final safeId = RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(projectId)
        ? projectId
        : 'id-${base64Url.encode(utf8.encode(projectId)).replaceAll('=', '')}';
    final projects = Directory(
      '$stagingDirectory${Platform.pathSeparator}projects',
    );
    await projects.create(recursive: true);
    return '${projects.path}${Platform.pathSeparator}$safeId.zip';
  }

  Future<String> _stagingPath(String prefix, String bundleId) async {
    final safeId = bundleId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final root = await _documentsDirectory();
    return ('${root.path}${Platform.pathSeparator}imports'
        '${Platform.pathSeparator}$prefix-$safeId');
  }
}

abstract interface class ProjectBundleFileSystem {
  Future<void> ensureDirectory(String path);

  Future<void> deleteTree(String path);
}

class DartProjectBundleFileSystem implements ProjectBundleFileSystem {
  @override
  Future<void> ensureDirectory(String path) {
    return Directory(path).create(recursive: true);
  }

  @override
  Future<void> deleteTree(String path) async {
    final directory = Directory(path);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

abstract interface class ShareFileService {
  Future<void> shareFile(String path);
}

class SystemShareFileService implements ShareFileService {
  @override
  Future<void> shareFile(String path) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: 'SiteMark project export'),
    );
  }
}

abstract interface class PrivateFileStore {
  Future<bool> exists(String path);

  Future<void> deleteIfExists(String path);
}

class DartIoPrivateFileStore implements PrivateFileStore {
  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<void> deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
