import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/platform/platform_services.dart';
import 'package:sitemark/workflow/project_import_service.dart'
    show AtomicMarkerWriter, DartAtomicMarkerWriter;

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
    AtomicMarkerWriter? writer,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _writer = writer ?? DartAtomicMarkerWriter();

  final Future<Directory> Function() _documentsDirectory;
  final AtomicMarkerWriter _writer;

  Future<Directory> _cleanupDirectory() async {
    final root = await _documentsDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}cleanup');
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<void> write(PendingProjectDeletion pending) async {
    final directory = await _cleanupDirectory();
    final safeId = _safeProjectId(pending.projectId);
    var latestRevision = -1;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final marker = _parseMarkerName(entity.uri.pathSegments.last);
      if (marker != null &&
          marker.safeProjectId == safeId &&
          marker.revision > latestRevision) {
        latestRevision = marker.revision;
      }
    }
    final nextRevision = latestRevision + 1;
    final marker = File(
      '${directory.path}${Platform.pathSeparator}'
      'project-$safeId-r$nextRevision.json',
    );
    await _writer.write(marker, jsonEncode(pending.toJson()));
  }

  @override
  Future<List<PendingProjectDeletion>> list() async {
    final directory = await _cleanupDirectory();
    final latest = <String, _PendingDeletionGeneration>{};
    final corruptProjectIds = <String>{};
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final marker = _parseMarkerName(name);
      if (marker == null) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Marker is not a JSON object');
        }
        final projectId = decoded['projectId'];
        final paths = decoded['paths'];
        if (projectId is! String ||
            projectId.isEmpty ||
            paths is! List ||
            paths.any((path) => path is! String) ||
            _safeProjectId(projectId) != marker.safeProjectId) {
          throw const FormatException('Invalid project deletion marker');
        }
        final item = PendingProjectDeletion.fromJson(decoded);
        final current = latest[marker.safeProjectId];
        if (current == null || marker.revision > current.revision) {
          latest[marker.safeProjectId] = _PendingDeletionGeneration(
            pending: item,
            revision: marker.revision,
          );
        }
      } catch (_) {
        corruptProjectIds.add(marker.safeProjectId);
      }
    }
    final corruptOnly = corruptProjectIds
        .where((safeId) => !latest.containsKey(safeId))
        .toList(growable: false);
    if (corruptOnly.isNotEmpty) {
      throw StateError(
        'Unreadable project deletion marker: project-${corruptOnly.first}',
      );
    }
    return latest.values
        .map((generation) => generation.pending)
        .toList(growable: false);
  }

  @override
  Future<void> clear(String projectId) async {
    final directory = await _cleanupDirectory();
    final safeId = _safeProjectId(projectId);
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final marker = _parseMarkerName(name);
      if (marker?.safeProjectId == safeId ||
          _isTemporaryMarkerFor(name, safeId)) {
        await entity.delete();
      }
    }
  }

  static String _safeProjectId(String projectId) =>
      projectId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static _DeletionMarkerName? _parseMarkerName(String name) {
    final generation = RegExp(
      r'^project-(.+)-r([0-9]+)\.json$',
    ).firstMatch(name);
    if (generation != null) {
      return _DeletionMarkerName(
        safeProjectId: generation.group(1)!,
        revision: int.parse(generation.group(2)!),
      );
    }
    final legacy = RegExp(r'^project-(.+)\.json$').firstMatch(name);
    if (legacy == null) return null;
    return _DeletionMarkerName(safeProjectId: legacy.group(1)!, revision: -1);
  }

  static bool _isTemporaryMarkerFor(String name, String safeId) {
    final prefix = 'project-$safeId-r';
    if (!name.startsWith(prefix)) return false;
    return RegExp(
      '^${RegExp.escape(prefix)}[0-9]+'
      r'\.json\.tmp-.+$',
    ).hasMatch(name);
  }
}

class _DeletionMarkerName {
  const _DeletionMarkerName({
    required this.safeProjectId,
    required this.revision,
  });

  final String safeProjectId;
  final int revision;
}

class _PendingDeletionGeneration {
  const _PendingDeletionGeneration({
    required this.pending,
    required this.revision,
  });

  final PendingProjectDeletion pending;
  final int revision;
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
