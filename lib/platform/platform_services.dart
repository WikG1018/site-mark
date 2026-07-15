import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sitemark/platform/system_api.g.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;

abstract interface class PlatformServices {
  Future<String> createCameraTarget(String captureId);

  Future<CameraCaptureResult> launchCamera(String captureId);

  Future<RecoveredCameraCapture?> recoverCameraCapture();

  Future<void> finishCameraCapture(String captureId, bool keepOriginal);

  Future<LocationResult> requestCurrentLocation(int timeoutMillis);

  Future<String> publishJpeg(String sourcePath, String displayName);

  Future<void> deletePublishedImage(String contentUri);
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
}

abstract interface class ImagePipeline {
  Future<rust.ExportProjectResult> export(rust.ExportProjectRequest request);

  Future<String> sha256(String path);

  Future<rust.RenderPhotoResult> render(rust.RenderPhotoRequest request);
}

class RustImagePipeline implements ImagePipeline {
  @override
  Future<rust.ExportProjectResult> export(rust.ExportProjectRequest request) {
    return rust.exportProject(request: request);
  }

  @override
  Future<rust.RenderPhotoResult> render(rust.RenderPhotoRequest request) {
    return rust.renderPhoto(request: request);
  }

  @override
  Future<String> sha256(String path) {
    return rust.sha256File(path: path);
  }
}

abstract interface class CaptureOutputPaths {
  Future<String> renderedPhotoPath(String captureId);
}

class AppCaptureOutputPaths implements CaptureOutputPaths {
  @override
  Future<String> renderedPhotoPath(String captureId) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}rendered',
    );
    await directory.create(recursive: true);
    return '${directory.path}${Platform.pathSeparator}$captureId.jpg';
  }
}

abstract interface class ProjectExportPaths {
  Future<String> projectZipPath(String projectId);
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
  Future<void> deleteIfExists(String path);
}

class DartIoPrivateFileStore implements PrivateFileStore {
  @override
  Future<void> deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
