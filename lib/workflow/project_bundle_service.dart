import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/project_name.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/src/rust/api/image_core.dart' as rust;
import 'package:sitemark/workflow/project_deletion_service.dart';
import 'package:sitemark/workflow/project_export_service.dart';
import 'package:sitemark/workflow/project_import_service.dart';
import 'package:uuid/uuid.dart';

enum ProjectBackupKind { singleProject, bundle }

class ProjectBackupResult {
  const ProjectBackupResult({
    required this.kind,
    required this.outputZipPath,
    required this.projectCount,
  });

  final ProjectBackupKind kind;
  final String outputZipPath;
  final int projectCount;
}

class ProjectBackupService {
  ProjectBackupService({
    required this.projectExporter,
    required this.database,
    required this.bundles,
    required this.paths,
    required this.files,
    String Function()? idGenerator,
  }) : _idGenerator = idGenerator ?? const Uuid().v4;

  final ProjectArchiveExporter projectExporter;
  final AppDatabase database;
  final ProjectBundlePipeline bundles;
  final ProjectBundlePaths paths;
  final ProjectBundleFileSystem files;
  final String Function() _idGenerator;

  Future<ProjectBackupResult> exportProjects({
    required List<String> projectIds,
    required bool includeOriginals,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (projectIds.isEmpty) {
      throw StateError('Select at least one project');
    }
    if (projectIds.toSet().length != projectIds.length) {
      throw StateError('A project can only be selected once');
    }
    if (projectIds.length == 1) {
      final result = await projectExporter.exportProject(
        projectId: projectIds.single,
        includeOriginals: includeOriginals,
      );
      onProgress?.call(1, 1);
      return ProjectBackupResult(
        kind: ProjectBackupKind.singleProject,
        outputZipPath: result.outputZipPath,
        projectCount: 1,
      );
    }

    final projects = <Project>[];
    for (final projectId in projectIds) {
      final project = await database.projectById(projectId);
      if (project == null) {
        throw StateError('Project $projectId does not exist');
      }
      projects.add(project);
    }

    final bundleId = _idGenerator();
    final stagingDirectory = await paths.exportStagingDirectory(bundleId);
    final totalSteps = projectIds.length + 1;
    try {
      final sources = <rust.ProjectBundleSource>[];
      for (var index = 0; index < projects.length; index++) {
        final project = projects[index];
        final archivePath = await paths.projectArchivePath(
          stagingDirectory,
          project.id,
        );
        await projectExporter.exportProject(
          projectId: project.id,
          includeOriginals: includeOriginals,
          outputZipPath: archivePath,
        );
        sources.add(
          rust.ProjectBundleSource(
            projectId: project.id,
            projectName: project.name,
            archivePath: archivePath,
          ),
        );
        onProgress?.call(index + 1, totalSteps);
      }
      final outputPath = await paths.backupZipPath();
      final result = await bundles.exportBundle(
        rust.ExportProjectBundleRequest(
          outputZipPath: outputPath,
          projects: sources,
        ),
      );
      onProgress?.call(totalSteps, totalSteps);
      return ProjectBackupResult(
        kind: ProjectBackupKind.bundle,
        outputZipPath: result.outputZipPath,
        projectCount: projects.length,
      );
    } finally {
      try {
        await files.deleteTree(stagingDirectory);
      } catch (_) {
        // The final archive is independent of its temporary inner ZIPs.
      }
    }
  }
}

class PreparedProjectRestore {
  const PreparedProjectRestore({
    required this.sourceZipPath,
    required this.items,
    this.bundleId,
    this.stagingDirectory,
  });

  final String sourceZipPath;
  final String? bundleId;
  final String? stagingDirectory;
  final List<PreparedProjectRestoreItem> items;

  bool get isBundle => bundleId != null;
}

class PreparedProjectRestoreItem {
  const PreparedProjectRestoreItem({
    required this.sourceProjectId,
    required this.targetProjectId,
    required this.archivePath,
    required this.preview,
  });

  final String sourceProjectId;
  final String targetProjectId;
  final String archivePath;
  final rust.ProjectArchivePreview preview;
}

class ProjectBundleRestoreException implements Exception {
  const ProjectBundleRestoreException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class PendingBundleRestore {
  const PendingBundleRestore({
    required this.bundleId,
    required this.stagingDirectory,
    required this.plannedProjectIds,
    this.ownedProjectIds = const [],
  });

  final String bundleId;
  final String stagingDirectory;
  final List<String> plannedProjectIds;
  final List<String> ownedProjectIds;

  Map<String, dynamic> toJson() => {
    'bundleId': bundleId,
    'stagingDirectory': stagingDirectory,
    'plannedProjectIds': plannedProjectIds,
    'ownedProjectIds': ownedProjectIds,
  };

  factory PendingBundleRestore.fromJson(Map<String, dynamic> json) {
    return PendingBundleRestore(
      bundleId: json['bundleId'] as String? ?? '',
      stagingDirectory: json['stagingDirectory'] as String? ?? '',
      plannedProjectIds: (json['plannedProjectIds'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      ownedProjectIds: (json['ownedProjectIds'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  PendingBundleRestore withOwnedProject(String projectId) {
    if (ownedProjectIds.contains(projectId)) return this;
    return PendingBundleRestore(
      bundleId: bundleId,
      stagingDirectory: stagingDirectory,
      plannedProjectIds: plannedProjectIds,
      ownedProjectIds: [...ownedProjectIds, projectId],
    );
  }
}

abstract interface class BundleRestorePendingStore {
  Future<void> write(PendingBundleRestore pending);

  Future<List<PendingBundleRestore>> list();

  Future<void> clear(String bundleId);
}

class AppBundleRestorePendingStore implements BundleRestorePendingStore {
  AppBundleRestorePendingStore({
    Future<Directory> Function()? documentsDirectory,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  @override
  Future<void> write(PendingBundleRestore pending) async {
    final marker = await _marker(pending.bundleId);
    final temporary = File('${marker.path}.tmp');
    await temporary.writeAsString(jsonEncode(pending.toJson()), flush: true);
    await temporary.rename(marker.path);
  }

  @override
  Future<List<PendingBundleRestore>> list() async {
    final directory = await _directory();
    final pending = <PendingBundleRestore>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('bundle-pending-') || !name.endsWith('.json')) {
        continue;
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is Map<String, dynamic>) {
          final item = PendingBundleRestore.fromJson(decoded);
          if (item.bundleId.isNotEmpty &&
              item.stagingDirectory.isNotEmpty &&
              item.plannedProjectIds.isNotEmpty) {
            pending.add(item);
          }
        }
      } catch (_) {
        // A malformed marker is not safe input for destructive cleanup.
      }
    }
    return pending;
  }

  @override
  Future<void> clear(String bundleId) async {
    final marker = await _marker(bundleId);
    if (await marker.exists()) await marker.delete();
  }

  Future<Directory> _directory() async {
    final root = await _documentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}imports'
      '${Platform.pathSeparator}bundle-pending',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _marker(String bundleId) async {
    final safeId = bundleId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final directory = await _directory();
    return File(
      '${directory.path}${Platform.pathSeparator}'
      'bundle-pending-$safeId.json',
    );
  }
}

abstract interface class ProjectBundleRollback {
  Future<void> handoff(String projectId);
}

class ProjectDeletionBundleRollback implements ProjectBundleRollback {
  ProjectDeletionBundleRollback({
    required this.database,
    required this.deletions,
  });

  final AppDatabase database;
  final ProjectDeletionService deletions;

  @override
  Future<void> handoff(String projectId) async {
    if (await database.projectById(projectId) != null) {
      await deletions.deleteProject(projectId);
      return;
    }
    // A previous attempt may already have handed private paths to the durable
    // deletion marker. Retry those markers without replacing them with an
    // empty marker for an already-absent database row.
    await deletions.cleanupInterruptedDeletions();
  }
}

class ProjectBundleService {
  ProjectBundleService({
    required this.database,
    required this.bundles,
    required this.importer,
    required this.paths,
    required this.files,
    required this.pendingStore,
    required this.rollback,
    String Function()? idGenerator,
  }) : _idGenerator = idGenerator ?? const Uuid().v4;

  final AppDatabase database;
  final ProjectBundlePipeline bundles;
  final ProjectArchiveImporter importer;
  final ProjectBundlePaths paths;
  final ProjectBundleFileSystem files;
  final BundleRestorePendingStore pendingStore;
  final ProjectBundleRollback rollback;
  final String Function() _idGenerator;
  static final Set<String> _activeRestoreTargetIds = <String>{};

  Future<PreparedProjectRestore> prepareRestore(String zipPath) async {
    rust.ProjectBundlePreview bundlePreview;
    try {
      bundlePreview = await bundles.readBundle(zipPath);
    } catch (bundleError) {
      if (bundleError is ImagePipelineException &&
          bundleError.kind != ImagePipelineFailureKind.invalidData) {
        throw ProjectBundleRestoreException(
          'The selected backup could not be read',
          cause: bundleError,
        );
      }
      try {
        final preview = await importer.inspect(zipPath);
        return PreparedProjectRestore(
          sourceZipPath: zipPath,
          items: [
            PreparedProjectRestoreItem(
              sourceProjectId: 'single',
              targetProjectId: _idGenerator(),
              archivePath: zipPath,
              preview: preview,
            ),
          ],
        );
      } catch (singleError) {
        throw ProjectBundleRestoreException(
          'The selected file is not a restorable SiteMark backup',
          cause: singleError,
        );
      }
    }

    final bundleId = _idGenerator();
    final stagingDirectory = await paths.restoreStagingDirectory(bundleId);
    try {
      final items = <PreparedProjectRestoreItem>[];
      for (final project in bundlePreview.projects) {
        final archivePath = await paths.projectArchivePath(
          stagingDirectory,
          project.projectId,
        );
        await bundles.extractBundleEntry(
          rust.ExtractProjectBundleEntryRequest(
            zipPath: zipPath,
            archivePath: project.archivePath,
            outputPath: archivePath,
          ),
        );
        final preview = await importer.inspect(archivePath);
        items.add(
          PreparedProjectRestoreItem(
            sourceProjectId: project.projectId,
            targetProjectId: _idGenerator(),
            archivePath: archivePath,
            preview: preview,
          ),
        );
      }
      return PreparedProjectRestore(
        sourceZipPath: zipPath,
        bundleId: bundleId,
        stagingDirectory: stagingDirectory,
        items: items,
      );
    } catch (error) {
      try {
        await files.deleteTree(stagingDirectory);
      } catch (_) {
        // Preparation has not persisted any app data. A leftover private
        // staging directory is safe and can be manually retried by the user.
      }
      throw ProjectBundleRestoreException(
        'The project bundle could not be prepared',
        cause: error,
      );
    }
  }

  Future<List<ProjectImportResult>> restorePrepared({
    required PreparedProjectRestore prepared,
    required Map<String, String> projectNames,
    void Function(int completed, int total)? onProgress,
  }) async {
    final targetIds = {for (final item in prepared.items) item.targetProjectId};
    if (targetIds.length != prepared.items.length) {
      throw const ProjectBundleRestoreException(
        'Prepared target project IDs must be unique',
      );
    }
    if (targetIds.any(_activeRestoreTargetIds.contains)) {
      throw const ProjectBundleRestoreException(
        'This prepared restore is already in progress',
      );
    }
    _activeRestoreTargetIds.addAll(targetIds);
    try {
      return await _restorePreparedReserved(
        prepared: prepared,
        projectNames: projectNames,
        onProgress: onProgress,
      );
    } finally {
      _activeRestoreTargetIds.removeAll(targetIds);
    }
  }

  Future<List<ProjectImportResult>> _restorePreparedReserved({
    required PreparedProjectRestore prepared,
    required Map<String, String> projectNames,
    void Function(int completed, int total)? onProgress,
  }) async {
    for (final item in prepared.items) {
      if (await database.projectById(item.targetProjectId) != null) {
        throw const ProjectBundleRestoreException(
          'A prepared target project already exists',
        );
      }
    }
    final names = await _validatedNames(prepared, projectNames);
    if (!prepared.isBundle) {
      final item = prepared.items.single;
      final result = await importer.importProject(
        zipPath: item.archivePath,
        projectName: names[item.sourceProjectId]!,
        projectId: item.targetProjectId,
        onProgress: onProgress,
      );
      return [result];
    }

    var pending = PendingBundleRestore(
      bundleId: prepared.bundleId!,
      stagingDirectory: prepared.stagingDirectory!,
      plannedProjectIds: [
        for (final item in prepared.items) item.targetProjectId,
      ],
    );
    try {
      await pendingStore.write(pending);
    } catch (error) {
      try {
        await files.deleteTree(pending.stagingDirectory);
      } catch (_) {
        // Best effort. A partially written marker, if any, owns the retry.
      }
      throw ProjectBundleRestoreException(
        'Project bundle restore could not be started',
        cause: error,
      );
    }
    try {
      final totalPhotos = prepared.items.fold<int>(
        0,
        (sum, item) => sum + item.preview.photos.length,
      );
      var completedBeforeItem = 0;
      var lastReported = 0;
      final results = <ProjectImportResult>[];
      for (final item in prepared.items) {
        final itemPhotos = item.preview.photos.length;
        final result = await importer.importProject(
          zipPath: item.archivePath,
          projectName: names[item.sourceProjectId]!,
          projectId: item.targetProjectId,
          onProgress: (completed, _) {
            final next = (completedBeforeItem + completed).clamp(
              lastReported,
              totalPhotos,
            );
            if (next > lastReported) {
              lastReported = next;
              onProgress?.call(next, totalPhotos);
            }
          },
        );
        results.add(result);
        pending = pending.withOwnedProject(item.targetProjectId);
        await pendingStore.write(pending);
        completedBeforeItem += itemPhotos;
      }
      await files.deleteTree(pending.stagingDirectory);
      await pendingStore.clear(pending.bundleId);
      return results;
    } catch (error) {
      await _rollbackPending(pending);
      throw ProjectBundleRestoreException(
        'Project bundle restore failed; all planned projects were rolled back or queued for cleanup',
        cause: error,
      );
    }
  }

  Future<void> discardPrepared(PreparedProjectRestore prepared) async {
    final stagingDirectory = prepared.stagingDirectory;
    if (stagingDirectory != null) {
      await files.deleteTree(stagingDirectory);
    }
  }

  Future<void> cleanupInterruptedBundleRestores() async {
    final pendings = await pendingStore.list();
    for (final pending in pendings) {
      await _rollbackPending(pending);
    }
  }

  Future<Map<String, String>> _validatedNames(
    PreparedProjectRestore prepared,
    Map<String, String> requested,
  ) async {
    final expectedKeys = {
      for (final item in prepared.items) item.sourceProjectId,
    };
    if (requested.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(requested.keys.toSet()).isNotEmpty) {
      throw const ProjectBundleRestoreException(
        'Every prepared project must have exactly one restore name',
      );
    }

    final existing = await database.getProjects();
    final displayKeys = {
      for (final project in existing) normalizedProjectNameKey(project.name),
    };
    final safeKeys = {
      for (final project in existing) safeProjectFileNameKey(project.name),
    };
    final names = <String, String>{};
    for (final item in prepared.items) {
      final name = requested[item.sourceProjectId]!.trim();
      if (name.isEmpty || name.length > 120) {
        throw const ProjectBundleRestoreException(
          'Project names must contain 1 to 120 characters',
        );
      }
      final displayKey = normalizedProjectNameKey(name);
      final safeKey = safeProjectFileNameKey(name);
      if (!displayKeys.add(displayKey) || !safeKeys.add(safeKey)) {
        throw const ProjectBundleRestoreException(
          'Project restore names conflict with an existing or selected project',
        );
      }
      names[item.sourceProjectId] = name;
    }
    return names;
  }

  Future<bool> _rollbackPending(PendingBundleRestore pending) async {
    var safelyHandedOff = true;
    var hasAmbiguousOwnership = false;
    final plannedIds = pending.plannedProjectIds.toSet();
    final ownedIds = pending.ownedProjectIds.where(plannedIds.contains).toSet();
    for (final projectId in ownedIds) {
      try {
        await rollback.handoff(projectId);
      } catch (_) {
        safelyHandedOff = false;
      }
    }
    for (final projectId in plannedIds.difference(ownedIds)) {
      if (await database.projectById(projectId) != null) {
        // A project exists, but the bundle marker never durably recorded that
        // this restore owns it. Preserve both data and marker for a later,
        // explicit resolution instead of risking an unrelated project.
        safelyHandedOff = false;
        hasAmbiguousOwnership = true;
      }
    }
    if (!hasAmbiguousOwnership) {
      try {
        await files.deleteTree(pending.stagingDirectory);
      } catch (_) {
        safelyHandedOff = false;
      }
    }
    if (safelyHandedOff) {
      try {
        await pendingStore.clear(pending.bundleId);
      } catch (_) {
        safelyHandedOff = false;
      }
    }
    return safelyHandedOff;
  }
}
