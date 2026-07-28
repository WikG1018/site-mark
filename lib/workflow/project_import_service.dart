import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_name.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;
import 'package:uuid/uuid.dart';

/// Outcome of a successful project backup restore.
class ProjectImportResult {
  const ProjectImportResult({
    required this.projectId,
    required this.projectName,
    required this.photoCount,
    required this.restoredOriginals,
  });

  final String projectId;
  final String projectName;
  final int photoCount;
  final int restoredOriginals;
}

/// Restores single-project backup archives produced by
/// `ProjectExportService.exportProject`.
///
/// The archive format is versioned (`manifest.json` → `schema_version`):
/// v1 archives restore records with default watermark settings and without
/// GPS fixes; v2 archives additionally restore the project watermark
/// template and per-photo location. Selection archives are not restorable
/// and are rejected by the archive reader.
class ProjectImportService {
  ProjectImportService({
    required this.database,
    required this.images,
    required this.capturePaths,
    required this.originalPaths,
    required this.fileStore,
    Uuid? uuid,
    DateTime Function()? clock,
  }) : _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final ImagePipeline images;
  final CaptureOutputPaths capturePaths;
  final OriginalPhotoPaths originalPaths;
  final PrivateFileStore fileStore;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Reads and validates a backup archive without restoring anything.
  Future<rust.ProjectArchivePreview> inspect(String zipPath) {
    return images.readProjectArchive(zipPath);
  }

  /// Whether [name] would collide with an existing project (display-name or
  /// generated file-name key), matching `AppDatabase.createProject` rules.
  Future<bool> projectNameTaken(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final displayKey = normalizedProjectNameKey(trimmed);
    final safeKey = safeProjectFileNameKey(trimmed);
    for (final project in await database.getProjects()) {
      if (normalizedProjectNameKey(project.name) == displayKey) return true;
      if (safeProjectFileNameKey(project.name) == safeKey) return true;
    }
    return false;
  }

  /// Returns [base] itself when free, otherwise `base（导入）`,
  /// `base（导入 2）`, ... trimmed to stay within the 120-character limit.
  Future<String> suggestAvailableName(String base) async {
    const maxLength = 120;
    final trimmedBase = base.trim();
    if (trimmedBase.isNotEmpty && !await projectNameTaken(trimmedBase)) {
      return trimmedBase;
    }
    for (var attempt = 0; attempt < 100; attempt++) {
      final suffix = attempt == 0 ? '（导入）' : '（导入 ${attempt + 1}）';
      final budget = maxLength - suffix.length;
      final stem = trimmedBase.length <= budget
          ? trimmedBase
          : trimmedBase.substring(0, budget);
      final candidate = '$stem$suffix';
      if (!await projectNameTaken(candidate)) return candidate;
    }
    throw StateError('Could not find an available project name');
  }

  /// Restores [zipPath] as a new project named [projectName].
  ///
  /// Photos keep their numbers, capture times, locations, and evidence
  /// hashes. Restored rows are `ready` with a null `publishedUri`, so the
  /// existing republish flow can re-save them to the system gallery.
  ///
  /// On any failure everything is rolled back: extracted files are removed
  /// and the partially-created project (with its rows) is deleted.
  Future<ProjectImportResult> importProject({
    required String zipPath,
    required String projectName,
    void Function(int completed, int total)? onProgress,
  }) async {
    final preview = await inspect(zipPath);
    final watermark = preview.watermark;
    final projectId = _uuid.v4();
    await database.createProject(
      id: projectId,
      name: projectName,
      watermarkPosition: _validPosition(watermark?.position),
      watermarkOpacity: _validOpacity(watermark?.opacity),
      watermarkAccentColorArgb: watermark?.accentColorArgb,
      watermarkFontScale: _validFontScale(watermark?.fontScale),
    );
    final extractedPaths = <String>[];
    var restoredOriginals = 0;
    try {
      final total = preview.photos.length;
      for (var index = 0; index < total; index++) {
        final photo = preview.photos[index];
        final captureId = _uuid.v4();
        final renderedPath = await capturePaths.renderedPhotoPath(captureId);
        final originalPath = await originalPaths.originalPhotoPath(captureId);
        final extracted = await images.extractArchivePhoto(
          rust.ExtractArchivePhotoRequest(
            zipPath: zipPath,
            photoNumber: photo.photoNumber,
            renderedDestination: renderedPath,
            originalDestination: photo.hasOriginal ? originalPath : null,
          ),
        );
        extractedPaths.add(extracted.renderedPath);
        final restoredOriginal = extracted.originalPath;
        if (restoredOriginal != null) {
          extractedPaths.add(restoredOriginal);
          restoredOriginals++;
        }
        final capturedAt = parseExportedTimestamp(photo.capturedAt) ?? _clock();
        await database.insertRestoredCapture(
          id: captureId,
          projectId: projectId,
          photoNumber: photo.photoNumber,
          // An archive without the original still needs an original_path:
          // point at the canonical location and mark it cleared, the same
          // state "clear originals" produces, so the hash stays as evidence.
          originalPath: restoredOriginal ?? originalPath,
          originalDeletedAt: restoredOriginal == null ? _clock() : null,
          workLocation: photo.workLocation,
          workContent: photo.workContent,
          photographer: photo.photographer,
          notes: photo.notes,
          address: photo.address,
          latitude: photo.latitude,
          longitude: photo.longitude,
          accuracyMeters: photo.accuracyMeters,
          watermarkLocaleCode: _validLocale(photo.watermarkLocaleCode),
          originalSha256: photo.originalSha256,
          createdAt: capturedAt,
          capturedAt: capturedAt,
        );
        onProgress?.call(index + 1, total);
      }
    } catch (_) {
      for (final path in extractedPaths) {
        await fileStore.deleteIfExists(path);
      }
      await database.deleteProjectCascade(projectId);
      rethrow;
    }
    return ProjectImportResult(
      projectId: projectId,
      projectName: projectName.trim(),
      photoCount: preview.photos.length,
      restoredOriginals: restoredOriginals,
    );
  }

  static String? _validPosition(String? value) =>
      value != null && {'bottomLeft', 'bottomRight'}.contains(value)
      ? value
      : null;

  static double? _validOpacity(double? value) =>
      value != null && value >= 0.2 && value <= 0.95 ? value : null;

  static double? _validFontScale(double? value) =>
      value != null && value >= 0.80 && value <= 1.60 ? value : null;

  static String _validLocale(String? value) =>
      value != null && {'zh', 'en'}.contains(value) ? value : 'zh';
}

/// Parses the export timestamp format `yyyy-MM-dd HH:mm:ss ±HH:MM` back into
/// a local [DateTime], honoring the recorded offset. Returns null when the
/// value does not match the expected shape.
DateTime? parseExportedTimestamp(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2}):(\d{2})$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  final iso =
      '${match[1]}-${match[2]}-${match[3]}'
      'T${match[4]}:${match[5]}:${match[6]}'
      '${match[7]}${match[8]}:${match[9]}';
  return DateTime.tryParse(iso)?.toLocal();
}
