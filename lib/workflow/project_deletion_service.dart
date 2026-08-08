import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/diagnostics/diagnostic_event.dart';
import 'package:sitemark/diagnostics/diagnostic_recorder.dart';
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
    final encodedId = _encodeProjectId(pending.projectId);
    var latestRevision = -1;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final marker = _parseNewMarkerName(name);
      if (marker != null &&
          marker.encodedProjectId == encodedId &&
          marker.revision > latestRevision) {
        latestRevision = marker.revision;
        continue;
      }
      try {
        final generation = await _readGeneration(entity, name);
        if (generation.pending.projectId == pending.projectId &&
            generation.revision > latestRevision) {
          latestRevision = generation.revision;
        }
      } catch (_) {
        // A corrupt new-format marker was already counted by its reversible
        // filename. An unreadable legacy marker cannot safely claim an ID.
      }
    }
    final nextRevision = latestRevision + 1;
    final marker = File(
      '${directory.path}${Platform.pathSeparator}'
      'deletion-v2-$encodedId-g$nextRevision.json',
    );
    await _writer.write(marker, jsonEncode(pending.toJson()));
  }

  @override
  Future<List<PendingProjectDeletion>> list() async {
    final directory = await _cleanupDirectory();
    final latest = <String, _PendingDeletionGeneration>{};
    final corruptProjectIds = <String>{};
    final unreadableLegacyMarkers = <String>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!_isMarkerName(name)) continue;
      try {
        final generation = await _readGeneration(entity, name);
        final projectId = generation.pending.projectId;
        final current = latest[projectId];
        if (current == null || generation.revision > current.revision) {
          latest[projectId] = generation;
        }
      } catch (_) {
        final marker = _parseNewMarkerName(name);
        final projectId = marker == null
            ? null
            : _decodeProjectId(marker.encodedProjectId);
        if (projectId == null) {
          unreadableLegacyMarkers.add(name);
        } else {
          corruptProjectIds.add(projectId);
        }
      }
    }
    if (unreadableLegacyMarkers.isNotEmpty) {
      throw StateError(
        'Unreadable project deletion marker: '
        '${unreadableLegacyMarkers.first}',
      );
    }
    final corruptOnly = corruptProjectIds
        .where((projectId) => !latest.containsKey(projectId))
        .toList(growable: false);
    if (corruptOnly.isNotEmpty) {
      throw StateError(
        'Unreadable project deletion marker for ${corruptOnly.first}',
      );
    }
    return latest.values
        .map((generation) => generation.pending)
        .toList(growable: false);
  }

  @override
  Future<void> clear(String projectId) async {
    final directory = await _cleanupDirectory();
    final encodedId = _encodeProjectId(projectId);
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final marker = _parseNewMarkerName(name);
      if (marker?.encodedProjectId == encodedId ||
          _isTemporaryMarkerFor(name, encodedId)) {
        await entity.delete();
        continue;
      }
      if (!_isMarkerName(name)) continue;
      try {
        final generation = await _readGeneration(entity, name);
        if (generation.pending.projectId == projectId) {
          await entity.delete();
        }
      } catch (_) {
        // An unreadable legacy filename is not reversible, so deleting it
        // based on a lossy guess could erase another project's ownership.
      }
    }
  }

  static String _legacySafeProjectId(String projectId) =>
      projectId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static String _encodeProjectId(String projectId) =>
      base64Url.encode(utf8.encode(projectId)).replaceAll('=', '');

  static String? _decodeProjectId(String encodedProjectId) {
    try {
      final paddingLength = (4 - encodedProjectId.length % 4) % 4;
      final padded = '$encodedProjectId${'=' * paddingLength}';
      final decoded = utf8.decode(base64Url.decode(padded));
      return _encodeProjectId(decoded) == encodedProjectId ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static _NewDeletionMarkerName? _parseNewMarkerName(String name) {
    final match = RegExp(
      r'^deletion-v2-([A-Za-z0-9_-]*)-g([0-9]+)\.json$',
    ).firstMatch(name);
    if (match == null || _decodeProjectId(match.group(1)!) == null) return null;
    final revision = int.tryParse(match.group(2)!);
    if (revision == null) return null;
    return _NewDeletionMarkerName(
      encodedProjectId: match.group(1)!,
      revision: revision,
    );
  }

  static bool _isMarkerName(String name) =>
      _parseNewMarkerName(name) != null ||
      RegExp(r'^project-(.+)\.json$').hasMatch(name);

  static Future<_PendingDeletionGeneration> _readGeneration(
    File file,
    String name,
  ) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Marker is not a JSON object');
    }
    final projectId = decoded['projectId'];
    final paths = decoded['paths'];
    if (projectId is! String ||
        projectId.isEmpty ||
        paths is! List ||
        paths.any((path) => path is! String)) {
      throw const FormatException('Invalid project deletion marker');
    }
    final revision = _revisionForIdentity(name, projectId);
    if (revision == null) {
      throw const FormatException('Marker filename does not match project ID');
    }
    return _PendingDeletionGeneration(
      pending: PendingProjectDeletion.fromJson(decoded),
      revision: revision,
    );
  }

  static int? _revisionForIdentity(String name, String projectId) {
    final current = _parseNewMarkerName(name);
    if (current != null &&
        _decodeProjectId(current.encodedProjectId) == projectId) {
      return current.revision;
    }

    final legacy = RegExp(r'^project-(.+)\.json$').firstMatch(name);
    if (legacy == null) return null;
    final legacyIdentity = legacy.group(1)!;
    if (legacyIdentity == projectId) return -1;

    final previousGeneration = RegExp(
      r'^project-(.+)-r([0-9]+)\.json$',
    ).firstMatch(name);
    if (previousGeneration == null ||
        previousGeneration.group(1)! != _legacySafeProjectId(projectId)) {
      return null;
    }
    return int.tryParse(previousGeneration.group(2)!);
  }

  static bool _isTemporaryMarkerFor(String name, String encodedId) {
    final prefix = 'deletion-v2-$encodedId-g';
    if (!name.startsWith(prefix)) return false;
    return RegExp(
      '^${RegExp.escape(prefix)}[0-9]+'
      r'\.json\.tmp-.+$',
    ).hasMatch(name);
  }
}

class _NewDeletionMarkerName {
  const _NewDeletionMarkerName({
    required this.encodedProjectId,
    required this.revision,
  });

  final String encodedProjectId;
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
    this.diagnostics,
  });

  final AppDatabase database;
  final CaptureOutputPaths capturePaths;
  final PrivateFileStore files;
  final ProjectDeletionPendingStore pendingStore;
  final DiagnosticRecorder? diagnostics;

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
    final stopwatch = Stopwatch()..start();
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
    try {
      await pendingStore.write(pending);
      await database.deleteProjectCascade(projectId);
    } catch (error) {
      _recordDeletion(
        DiagnosticOutcome.failed,
        DiagnosticCode.unexpected,
        count: 1,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      rethrow;
    }
    final cleaned = await _deletePaths(pending.paths);
    if (!cleaned) {
      // Database rows are already gone; private file cleanup will retry on
      // the next launch via the durable marker. Record as blocked (not
      // success) because the operation is not fully complete.
      _recordDeletion(
        DiagnosticOutcome.blocked,
        DiagnosticCode.none,
        count: captures.length,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      return const ProjectDeletionResult(cleanupPending: true);
    }
    try {
      await pendingStore.clear(projectId);
    } catch (_) {
      // The files are gone, but preserving the marker lets startup retry the
      // durable commit step without reporting a failed project deletion.
      _recordDeletion(
        DiagnosticOutcome.blocked,
        DiagnosticCode.none,
        count: captures.length,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      return const ProjectDeletionResult(cleanupPending: true);
    }
    _recordDeletion(
      DiagnosticOutcome.success,
      DiagnosticCode.none,
      count: captures.length,
      durationMs: stopwatch.elapsedMilliseconds,
    );
    return const ProjectDeletionResult(cleanupPending: false);
  }

  Future<void> cleanupInterruptedDeletions() async {
    final pendings = await pendingStore.list();
    var remaining = 0;
    var attempted = 0;
    var skippedStillPresent = 0;
    for (final pending in pendings) {
      // Markers are written before the transactional database cascade. A
      // failed cascade leaves its marker in place, so a present project proves
      // this marker is not yet safe to execute against private files.
      if (await database.projectById(pending.projectId) != null) {
        skippedStillPresent += 1;
        continue;
      }
      attempted += 1;
      final cleaned = await _deletePaths(pending.paths);
      if (cleaned) {
        try {
          await pendingStore.clear(pending.projectId);
        } catch (_) {
          // Leave the marker so a later launch can clear it.
          remaining += 1;
        }
      } else {
        remaining += 1;
      }
    }
    // Only record when cleanup work was attempted. Markers left for projects
    // that still exist are intentional (cascade not finished) and must not
    // look like a successful sweep.
    if (attempted > 0) {
      _recordDeletion(
        remaining == 0 ? DiagnosticOutcome.success : DiagnosticOutcome.blocked,
        DiagnosticCode.none,
        count: attempted,
      );
    } else if (skippedStillPresent > 0 && pendings.isNotEmpty) {
      _recordDeletion(
        DiagnosticOutcome.blocked,
        DiagnosticCode.none,
        count: skippedStillPresent,
      );
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

  void _recordDeletion(
    DiagnosticOutcome outcome,
    DiagnosticCode code, {
    int? count,
    int? durationMs,
  }) {
    diagnostics?.record(
      DiagnosticEvent(
        timestamp: DateTime.now(),
        category: DiagnosticCategory.deletion,
        outcome: outcome,
        code: code,
        count: count,
        durationMs: durationMs,
      ),
    );
  }
}
