import 'package:drift/drift.dart';

enum ProjectLifecycleStatus { active, completed, archived }

class ProjectLifecycleStatusConverter
    extends TypeConverter<ProjectLifecycleStatus, String> {
  const ProjectLifecycleStatusConverter();

  @override
  ProjectLifecycleStatus fromSql(String value) {
    for (final status in ProjectLifecycleStatus.values) {
      if (status.name == value) {
        return status;
      }
    }
    throw StateError('Unknown project lifecycle status: $value');
  }

  @override
  String toSql(ProjectLifecycleStatus value) => value.name;
}

final class ProjectReadOnlyException implements Exception {
  const ProjectReadOnlyException(this.projectId, this.status);

  final String projectId;
  final ProjectLifecycleStatus status;

  @override
  String toString() =>
      'ProjectReadOnlyException(projectId: $projectId, status: $status)';
}
