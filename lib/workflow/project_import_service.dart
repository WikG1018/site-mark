import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
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

/// Thrown when a backup archive is structurally valid but contains data that
/// must not be silently rewritten — e.g. an unreadable capture timestamp.
/// Substituting "now" for a broken capture time would falsify an evidence
/// field, so the whole import is rejected instead.
class InvalidArchiveException implements Exception {
  const InvalidArchiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A not-yet-committed import recorded on disk, so an import interrupted by
/// a process kill can be cleaned up on the next launch. The marker lists
/// every file the import may have created, staged and final alike.
class PendingImport {
  const PendingImport({
    required this.projectId,
    required this.stagingDirectory,
    required this.stagedFiles,
    required this.finalFiles,
  });

  final String projectId;
  final String stagingDirectory;
  final List<String> stagedFiles;
  final List<String> finalFiles;

  List<String> get allFiles => [...stagedFiles, ...finalFiles];

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'stagingDirectory': stagingDirectory,
    'stagedFiles': stagedFiles,
    'finalFiles': finalFiles,
  };

  factory PendingImport.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List? ?? const []).whereType<String>().toList();
    return PendingImport(
      projectId: json['projectId'] as String? ?? '',
      stagingDirectory: json['stagingDirectory'] as String? ?? '',
      stagedFiles: strings('stagedFiles'),
      finalFiles: strings('finalFiles'),
    );
  }
}

/// Persists [PendingImport] markers as JSON files under
/// `<documents>/imports/`.
abstract interface class ImportPendingStore {
  Future<void> writePending(PendingImport pending);

  Future<List<PendingImport>> listPending();

  Future<void> clearPending(String projectId);
}

class AppImportPendingStore implements ImportPendingStore {
  AppImportPendingStore({Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  Future<Directory> _importsDirectory() async {
    final root = await _documentsDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}imports');
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<void> writePending(PendingImport pending) async {
    final directory = await _importsDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'pending-${pending.projectId}.json',
    );
    await file.writeAsString(jsonEncode(pending.toJson()));
  }

  @override
  Future<List<PendingImport>> listPending() async {
    final directory = await _importsDirectory();
    final pendings = <PendingImport>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('pending-') || !name.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is Map<String, dynamic>) {
          final pending = PendingImport.fromJson(decoded);
          if (pending.projectId.isNotEmpty) pendings.add(pending);
        }
      } catch (_) {
        // A corrupt marker cannot be trusted; skip it here. The leftover
        // staging directory remains on disk and is harmless (app-private).
      }
    }
    return pendings;
  }

  @override
  Future<void> clearPending(String projectId) async {
    final directory = await _importsDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}pending-$projectId.json',
    );
    if (await file.exists()) await file.delete();
  }
}

/// Resolves the on-disk staging area for an in-flight import.
abstract interface class ImportStagingPaths {
  Future<String> stagingDirectory(String projectId);

  Future<String> stagedRenderedPath(String projectId, String captureId);

  Future<String> stagedOriginalPath(String projectId, String captureId);
}

class AppImportStagingPaths implements ImportStagingPaths {
  AppImportStagingPaths({Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  @override
  Future<String> stagingDirectory(String projectId) async {
    final root = await _documentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}imports'
      '${Platform.pathSeparator}staging-$projectId',
    );
    await directory.create(recursive: true);
    return directory.path;
  }

  @override
  Future<String> stagedRenderedPath(String projectId, String captureId) async {
    final staging = await stagingDirectory(projectId);
    return '$staging${Platform.pathSeparator}rendered'
        '${Platform.pathSeparator}$captureId.jpg';
  }

  @override
  Future<String> stagedOriginalPath(String projectId, String captureId) async {
    final staging = await stagingDirectory(projectId);
    return '$staging${Platform.pathSeparator}originals'
        '${Platform.pathSeparator}$captureId.jpg';
  }
}

/// Moves staged files into their final locations at the import commit point.
abstract interface class ImportFileCommitter {
  Future<void> moveIntoPlace(String stagedPath, String finalPath);

  Future<void> deleteTree(String path);
}

class DartImportFileCommitter implements ImportFileCommitter {
  @override
  Future<void> moveIntoPlace(String stagedPath, String finalPath) async {
    final staged = File(stagedPath);
    final parent = File(finalPath).parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    try {
      await staged.rename(finalPath);
    } on FileSystemException {
      // Rename can fail across volumes on some platforms; copy + delete is
      // the portable fallback for the same-volume staging design anyway.
      await staged.copy(finalPath);
      await staged.delete();
    }
  }

  @override
  Future<void> deleteTree(String path) async {
    final directory = Directory(path);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

/// Restores single-project backup archives produced by
/// `ProjectExportService.exportProject`.
///
/// The archive format is versioned (`manifest.json` → `schema_version`):
/// v1 archives restore records with default watermark settings and without
/// GPS fixes; v2 archives additionally restore the project watermark
/// template and per-photo location. Selection archives are not restorable
/// and are rejected by the archive reader.
///
/// Import is crash-safe: files are extracted into a staging directory while
/// a [PendingImport] marker records the plan on disk. Only after every photo
/// verifies does the import commit — database rows first, then files are
/// moved into place. [cleanupInterruptedImports] removes the leftovers of
/// any import that never committed (e.g. the process was killed).
class ProjectImportService {
  ProjectImportService({
    required this.database,
    required this.images,
    required this.capturePaths,
    required this.originalPaths,
    required this.fileStore,
    required this.stagingPaths,
    required this.pendingStore,
    required this.committer,
    Uuid? uuid,
    DateTime Function()? clock,
  }) : _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final ImagePipeline images;
  final CaptureOutputPaths capturePaths;
  final OriginalPhotoPaths originalPaths;
  final PrivateFileStore fileStore;
  final ImportStagingPaths stagingPaths;
  final ImportPendingStore pendingStore;
  final ImportFileCommitter committer;
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
  /// Throws [InvalidArchiveException] when a photo's capture timestamp does
  /// not match the export format — restoring it with a substituted "now"
  /// would falsify an evidence field, so the backup is rejected as a whole.
  Future<ProjectImportResult> importProject({
    required String zipPath,
    required String projectName,
    void Function(int completed, int total)? onProgress,
  }) async {
    final preview = await inspect(zipPath);
    final capturedTimes = <DateTime>[];
    for (final photo in preview.photos) {
      final parsed = parseExportedTimestamp(photo.capturedAt);
      if (parsed == null) {
        throw InvalidArchiveException(
          'Invalid capture timestamp for ${photo.photoNumber}',
        );
      }
      capturedTimes.add(parsed);
    }

    final watermark = preview.watermark;
    final projectId = _uuid.v4();
    final stagingDir = await stagingPaths.stagingDirectory(projectId);

    // Plan every path up front so the pending marker covers all of them.
    final plans = <_PhotoPlan>[];
    for (var index = 0; index < preview.photos.length; index++) {
      final captureId = _uuid.v4();
      plans.add(
        _PhotoPlan(
          captureId: captureId,
          stagedRendered: await stagingPaths.stagedRenderedPath(
            projectId,
            captureId,
          ),
          stagedOriginal: await stagingPaths.stagedOriginalPath(
            projectId,
            captureId,
          ),
          finalRendered: await capturePaths.renderedPhotoPath(captureId),
          finalOriginal: await originalPaths.originalPhotoPath(captureId),
        ),
      );
    }
    final pending = PendingImport(
      projectId: projectId,
      stagingDirectory: stagingDir,
      stagedFiles: [
        for (final plan in plans) ...[plan.stagedRendered, plan.stagedOriginal],
      ],
      finalFiles: [
        for (final plan in plans) ...[plan.finalRendered, plan.finalOriginal],
      ],
    );
    await pendingStore.writePending(pending);

    var committed = false;
    try {
      for (var index = 0; index < preview.photos.length; index++) {
        final photo = preview.photos[index];
        final plan = plans[index];
        await images.extractArchivePhoto(
          rust.ExtractArchivePhotoRequest(
            zipPath: zipPath,
            photoNumber: photo.photoNumber,
            renderedDestination: plan.stagedRendered,
            originalDestination: photo.hasOriginal ? plan.stagedOriginal : null,
          ),
        );
        onProgress?.call(index + 1, preview.photos.length);
      }

      await database.createProject(
        id: projectId,
        name: projectName,
        watermarkPosition: _validPosition(watermark?.position),
        watermarkOpacity: _validOpacity(watermark?.opacity),
        watermarkAccentColorArgb: watermark?.accentColorArgb,
        watermarkFontScale: _validFontScale(watermark?.fontScale),
      );
      try {
        for (var index = 0; index < preview.photos.length; index++) {
          final photo = preview.photos[index];
          final plan = plans[index];
          await database.insertRestoredCapture(
            id: plan.captureId,
            projectId: projectId,
            photoNumber: photo.photoNumber,
            // An archive without the original still needs an original_path:
            // point at the canonical location and mark it cleared, the same
            // state "clear originals" produces, so the hash stays as evidence.
            originalPath: plan.finalOriginal,
            originalDeletedAt: photo.hasOriginal ? null : _clock(),
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
            createdAt: capturedTimes[index],
            capturedAt: capturedTimes[index],
          );
        }
      } catch (_) {
        await database.deleteProjectCascade(projectId);
        rethrow;
      }

      // Commit point: move staged files into their final locations.
      for (var index = 0; index < plans.length; index++) {
        final plan = plans[index];
        await committer.moveIntoPlace(plan.stagedRendered, plan.finalRendered);
        if (preview.photos[index].hasOriginal) {
          await committer.moveIntoPlace(
            plan.stagedOriginal,
            plan.finalOriginal,
          );
        }
      }
      committed = true;
    } finally {
      if (!committed) {
        await _rollback(pending);
      }
    }

    await pendingStore.clearPending(projectId);
    try {
      await committer.deleteTree(stagingDir);
    } catch (_) {
      // The import is already committed and its crash-recovery marker has
      // been cleared. A leftover empty staging tree is harmless and must not
      // turn a successful restore into a user-visible failure.
    }
    return ProjectImportResult(
      projectId: projectId,
      projectName: projectName.trim(),
      photoCount: preview.photos.length,
      restoredOriginals: preview.photos
          .where((photo) => photo.hasOriginal)
          .length,
    );
  }

  /// Removes leftovers of imports that never committed. Runs at startup
  /// before any recovery work so half-imported projects never surface.
  ///
  /// Every step is best-effort: one failed delete must not abandon the
  /// remaining files, and the database cleanup always runs. The marker is
  /// only cleared after everything was attempted again, so a stubborn file
  /// is retried on the next launch instead of leaking silently.
  Future<void> cleanupInterruptedImports() async {
    final pendings = await pendingStore.listPending();
    for (final pending in pendings) {
      final fullyCleaned = await _rollback(pending);
      if (fullyCleaned) {
        try {
          await pendingStore.clearPending(pending.projectId);
        } catch (_) {
          // Keep the marker; the next launch retries.
        }
      }
    }
  }

  /// Best-effort rollback of a [PendingImport]: deletes every known file,
  /// the staging tree, and the database rows. Individual failures are
  /// swallowed so one stubborn file never blocks the rest; the pending
  /// marker stays in place for the startup cleanup to retry.
  Future<bool> _rollback(PendingImport pending) async {
    var fullyCleaned = true;
    for (final path in pending.allFiles) {
      try {
        await fileStore.deleteIfExists(path);
      } catch (_) {
        // Best-effort: keep deleting the remaining files.
        fullyCleaned = false;
      }
    }
    try {
      await committer.deleteTree(pending.stagingDirectory);
    } catch (_) {
      fullyCleaned = false;
    }
    try {
      await database.deleteProjectCascade(pending.projectId);
    } catch (_) {
      fullyCleaned = false;
    }
    return fullyCleaned;
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

class _PhotoPlan {
  const _PhotoPlan({
    required this.captureId,
    required this.stagedRendered,
    required this.stagedOriginal,
    required this.finalRendered,
    required this.finalOriginal,
  });

  final String captureId;
  final String stagedRendered;
  final String stagedOriginal;
  final String finalRendered;
  final String finalOriginal;
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
