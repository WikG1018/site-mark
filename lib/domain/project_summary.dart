import 'package:sitemark/data/app_database.dart';

final class ProjectSummary {
  const ProjectSummary({
    required this.project,
    required this.captureCount,
    required this.lastCaptureAt,
    this.recentCaptureIds = const [],
  });

  final Project project;
  final int captureCount;
  final DateTime? lastCaptureAt;
  final List<String> recentCaptureIds;
}
