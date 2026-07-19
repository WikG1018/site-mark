import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';

/// Applies [filter] to already-loaded capture summaries without changing their
/// order or the source list.
List<CaptureSummary> filterCaptureSummaries(
  List<CaptureSummary> summaries,
  CaptureFilter filter,
) {
  final range = filter.localRange;
  return summaries
      .where((summary) {
        if (filter.projectId != null &&
            summary.capture.projectId != filter.projectId) {
          return false;
        }
        if (range == null) return true;
        final capturedAt =
            summary.capture.capturedAt ?? summary.capture.createdAt;
        return !capturedAt.isBefore(range.start) &&
            capturedAt.isBefore(range.end);
      })
      .toList(growable: false);
}
