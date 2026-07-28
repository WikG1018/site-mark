import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/platform/platform_services.dart';

class ProjectDeletionPreview {
  const ProjectDeletionPreview({
    required this.projectName,
    required this.captureCount,
    required this.privateOriginalCount,
  });

  final String projectName;
  final int captureCount;
  final int privateOriginalCount;
}

class ProjectDeletionResult {
  const ProjectDeletionResult({required this.cleanupPending});

  final bool cleanupPending;
}

class PendingProjectDeletion {
  const PendingProjectDeletion({required this.projectId, required this.paths});

  final String projectId;
  final List<String> paths;

  Map<String, dynamic> toJson() => {'projectId': projectId, 'paths': paths};

  factory PendingProjectDeletion.fromJson(Map<String, dynamic> json) {
    final paths = (json['paths'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    return PendingProjectDeletion(
      projectId: json['projectId'] as String? ?? '',
      paths: paths,
    );
  }
}

abstract interface class ProjectDeletionPendingStore {
  Future<void> write(PendingProjectDeletion pending);

  Future<List<PendingProjectDeletion>> list();

  Future<void> clear(String projectId);
}

/// Persists crash-recovery markers under `<documents>/cleanup/`.
///
/// Each marker includes only the project ID and app-private file paths. System
/// gallery URIs are intentionally outside this contract.
class AppProjectDeletionPendingStore implements ProjectDeletionPendingStore {
  AppProjectDeletionPendingStore({
    Future<Directory> Function()? documentsDirectory,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  Future<Directory> _cleanupDirectory() async {
    final root = await _documentsDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}cleanup');
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<void> write(PendingProjectDeletion pending) async {
    final marker = await _markerFile(pending.projectId);
    await marker.writeAsString(jsonEncode(pending.toJson()));
  }

  @override
  Future<List<PendingProjectDeletion>> list() async {
    final directory = await _cleanupDirectory();
    final pending = <PendingProjectDeletion>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('project-') || !name.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is Map<String, dynamic>) {
          final item = PendingProjectDeletion.fromJson(decoded);
          if (item.projectId.isNotEmpty) pending.add(item);
        }
      } catch (_) {
        // Ignore corrupt markers: their contents cannot safely guide cleanup.
      }
    }
    return pending;
  }

  @override
  Future<void> clear(String projectId) async {
    final marker = await _markerFile(projectId);
    if (await marker.exists()) await marker.delete();
  }

  Future<File> _markerFile(String projectId) async {
    final directory = await _cleanupDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}project-$projectId.json',
    );
  }
}

class ProjectDeletionService {
  ProjectDeletionService({
    required this.database,
    required this.capturePaths,
    required this.files,
    required this.pendingStore,
  });

  final AppDatabase database;
  final CaptureOutputPaths capturePaths;
  final PrivateFileStore files;
  final ProjectDeletionPendingStore pendingStore;

  Future<ProjectDeletionPreview> preview(String projectId) async {
    final project = await database.projectById(projectId);
    if (project == null) throw StateError('Project does not exist');
    final captures = await database.capturesForProject(projectId);
    return ProjectDeletionPreview(
      projectName: project.name,
      captureCount: captures.length,
      privateOriginalCount: captures
          .where((capture) => capture.originalDeletedAt == null)
          .length,
    );
  }

  Future<ProjectDeletionResult> deleteProject(String projectId) async {
    final captures = await database.capturesForProject(projectId);
    final paths = <String>{};
    for (final capture in captures) {
      paths.add(capture.originalPath);
      paths.add(await capturePaths.renderedPhotoPath(capture.id));
    }
    final pending = PendingProjectDeletion(
      projectId: projectId,
      paths: paths.toList(growable: false),
    );
    await pendingStore.write(pending);
    await database.deleteProjectCascade(projectId);
    final cleaned = await _deletePaths(pending.paths);
    if (!cleaned) return const ProjectDeletionResult(cleanupPending: true);
    try {
      await pendingStore.clear(projectId);
    } catch (_) {
      // The files are gone, but preserving the marker lets startup retry the
      // durable commit step without reporting a failed project deletion.
      return const ProjectDeletionResult(cleanupPending: true);
    }
    return const ProjectDeletionResult(cleanupPending: false);
  }

  Future<void> cleanupInterruptedDeletions() async {
    final pendings = await pendingStore.list();
    for (final pending in pendings) {
      // Markers are written before the transactional database cascade. A
      // failed cascade leaves its marker in place, so a present project proves
      // this marker is not yet safe to execute against private files.
      if (await database.projectById(pending.projectId) != null) continue;
      final cleaned = await _deletePaths(pending.paths);
      if (cleaned) {
        try {
          await pendingStore.clear(pending.projectId);
        } catch (_) {
          // Leave the marker so a later launch can clear it.
        }
      }
    }
  }

  Future<bool> _deletePaths(List<String> paths) async {
    var cleaned = true;
    for (final path in paths) {
      try {
        await files.deleteIfExists(path);
      } catch (_) {
        cleaned = false;
      }
    }
    return cleaned;
  }
}
