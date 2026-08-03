import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/project_lifecycle.dart';

final class ProjectLifecyclePreview {
  const ProjectLifecyclePreview({
    required this.projectId,
    required this.expectedStatus,
    required this.targetStatus,
    required this.processingCount,
    required this.failedCount,
  });

  final String projectId;
  final ProjectLifecycleStatus expectedStatus;
  final ProjectLifecycleStatus targetStatus;
  final int processingCount;
  final int failedCount;
}

final class ProjectLifecycleProcessingException implements Exception {
  const ProjectLifecycleProcessingException(this.processingCount);

  final int processingCount;

  @override
  String toString() =>
      'ProjectLifecycleProcessingException(processingCount: $processingCount)';
}

final class ProjectLifecycleConfirmationRequiredException implements Exception {
  const ProjectLifecycleConfirmationRequiredException(this.failedCount);

  final int failedCount;

  @override
  String toString() =>
      'ProjectLifecycleConfirmationRequiredException(failedCount: $failedCount)';
}

final class ProjectLifecycleConflictException implements Exception {
  const ProjectLifecycleConflictException();

  @override
  String toString() => 'ProjectLifecycleConflictException()';
}

final class ProjectLifecycleInvalidTransitionException implements Exception {
  const ProjectLifecycleInvalidTransitionException({
    required this.from,
    required this.to,
  });

  final ProjectLifecycleStatus from;
  final ProjectLifecycleStatus to;

  @override
  String toString() =>
      'ProjectLifecycleInvalidTransitionException(from: $from, to: $to)';
}

const _allowedTransitions =
    <ProjectLifecycleStatus, Set<ProjectLifecycleStatus>>{
      ProjectLifecycleStatus.active: {
        ProjectLifecycleStatus.completed,
        ProjectLifecycleStatus.archived,
      },
      ProjectLifecycleStatus.completed: {
        ProjectLifecycleStatus.active,
        ProjectLifecycleStatus.archived,
      },
      ProjectLifecycleStatus.archived: {ProjectLifecycleStatus.active},
    };

final class ProjectLifecycleService {
  ProjectLifecycleService(this._database);

  final AppDatabase _database;

  Future<ProjectLifecyclePreview> preview(
    String projectId,
    ProjectLifecycleStatus targetStatus,
  ) async {
    final project = await _database.projectById(projectId);
    if (project == null) {
      throw StateError('Project does not exist');
    }
    _assertAllowed(project.lifecycleStatus, targetStatus);
    final counts = await _countStatuses(projectId);
    return ProjectLifecyclePreview(
      projectId: projectId,
      expectedStatus: project.lifecycleStatus,
      targetStatus: targetStatus,
      processingCount: counts.processing,
      failedCount: counts.failed,
    );
  }

  Future<Project> transition(
    ProjectLifecyclePreview preview, {
    required bool confirmFailed,
  }) {
    return _database.transaction(() async {
      final project = await _database.projectById(preview.projectId);
      if (project == null ||
          project.lifecycleStatus != preview.expectedStatus) {
        throw const ProjectLifecycleConflictException();
      }
      _assertAllowed(project.lifecycleStatus, preview.targetStatus);

      if (preview.targetStatus != ProjectLifecycleStatus.active) {
        final counts = await _countStatuses(preview.projectId);
        if (counts.processing > 0) {
          throw ProjectLifecycleProcessingException(counts.processing);
        }
        if (counts.failed > 0 && !confirmFailed) {
          throw ProjectLifecycleConfirmationRequiredException(counts.failed);
        }
      }

      final updated = await _database.updateProjectLifecycleStatus(
        projectId: preview.projectId,
        expectedStatus: preview.expectedStatus,
        targetStatus: preview.targetStatus,
      );
      if (updated == null) {
        throw const ProjectLifecycleConflictException();
      }
      return updated;
    });
  }

  void _assertAllowed(ProjectLifecycleStatus from, ProjectLifecycleStatus to) {
    final allowed = _allowedTransitions[from] ?? const {};
    if (!allowed.contains(to)) {
      throw ProjectLifecycleInvalidTransitionException(from: from, to: to);
    }
  }

  Future<({int processing, int failed})> _countStatuses(
    String projectId,
  ) async {
    final rows = await (_database.select(
      _database.captureRecords,
    )..where((row) => row.projectId.equals(projectId))).get();
    var processing = 0;
    var failed = 0;
    for (final row in rows) {
      switch (row.status) {
        case CaptureStatus.pendingCamera:
        case CaptureStatus.captured:
        case CaptureStatus.rendering:
          processing++;
        case CaptureStatus.failed:
          failed++;
        case CaptureStatus.ready:
          break;
      }
    }
    return (processing: processing, failed: failed);
  }
}
