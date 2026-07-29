import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_status.dart';

enum ProjectBackupDisposition { empty, ready, processing, failed, missing }

class ProjectBackupProjectSnapshot {
  const ProjectBackupProjectSnapshot({
    required this.projectId,
    required this.projectName,
    required this.disposition,
    required this.readyCount,
    required this.processingCount,
    required this.failedCount,
  });

  final String projectId;
  final String? projectName;
  final ProjectBackupDisposition disposition;
  final int readyCount;
  final int processingCount;
  final int failedCount;
}

class ProjectBackupSnapshot {
  const ProjectBackupSnapshot({
    required this.capturedAt,
    required this.projects,
  });

  final DateTime capturedAt;
  final List<ProjectBackupProjectSnapshot> projects;

  int get processingCount =>
      projects.fold(0, (sum, project) => sum + project.processingCount);
  int get failedCount =>
      projects.fold(0, (sum, project) => sum + project.failedCount);
}

class ProjectBackupPreflightService {
  const ProjectBackupPreflightService(this.database);

  final AppDatabase database;

  Future<ProjectBackupSnapshot> inspect(List<String> projectIds) async {
    if (projectIds.isEmpty) {
      throw ArgumentError.value(projectIds, 'projectIds', 'must not be empty');
    }
    if (projectIds.toSet().length != projectIds.length) {
      throw ArgumentError.value(
        projectIds,
        'projectIds',
        'must not contain duplicates',
      );
    }
    final projects = <ProjectBackupProjectSnapshot>[];
    for (final projectId in projectIds) {
      final project = await database.projectById(projectId);
      if (project == null) {
        projects.add(
          ProjectBackupProjectSnapshot(
            projectId: projectId,
            projectName: null,
            disposition: ProjectBackupDisposition.missing,
            readyCount: 0,
            processingCount: 0,
            failedCount: 0,
          ),
        );
        continue;
      }
      final captures = await database.capturesForProject(projectId);
      final ready = captures
          .where((capture) => capture.status == CaptureStatus.ready)
          .length;
      final failed = captures
          .where((capture) => capture.status == CaptureStatus.failed)
          .length;
      final processing = captures.length - ready - failed;
      final disposition = switch ((captures.isEmpty, failed, processing)) {
        (true, _, _) => ProjectBackupDisposition.empty,
        (_, > 0, _) => ProjectBackupDisposition.failed,
        (_, _, > 0) => ProjectBackupDisposition.processing,
        _ => ProjectBackupDisposition.ready,
      };
      projects.add(
        ProjectBackupProjectSnapshot(
          projectId: project.id,
          projectName: project.name,
          disposition: disposition,
          readyCount: ready,
          processingCount: processing,
          failedCount: failed,
        ),
      );
    }
    return ProjectBackupSnapshot(
      capturedAt: DateTime.now(),
      projects: List.unmodifiable(projects),
    );
  }
}
