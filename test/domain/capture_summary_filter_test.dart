import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/domain/capture_filter.dart';
import 'package:sitemark/domain/capture_status.dart';
import 'package:sitemark/domain/capture_summary_filter.dart';

CaptureSummary _summary({
  required String id,
  required String projectId,
  required DateTime capturedAt,
}) {
  return CaptureSummary(
    capture: CaptureRecord(
      id: id,
      projectId: projectId,
      workLocation: 'A 区',
      workContent: '风管',
      photographer: '张工',
      originalPath: '/private/$id.jpg',
      status: CaptureStatus.ready,
      createdAt: capturedAt,
      capturedAt: capturedAt,
      processingAttempts: 0,
      watermarkLocaleCode: 'zh',
      locationResolution: 'resolved',
    ),
    projectName: projectId,
  );
}

void main() {
  test('filters project and half-open year month and day ranges immutably', () {
    final summaries = [
      _summary(
        id: 'other-project',
        projectId: 'project-2',
        capturedAt: DateTime(2026, 7, 16, 9),
      ),
      _summary(
        id: 'before-day',
        projectId: 'project-1',
        capturedAt: DateTime(2026, 7, 15, 23, 59),
      ),
      _summary(
        id: 'in-day',
        projectId: 'project-1',
        capturedAt: DateTime(2026, 7, 16, 12),
      ),
      _summary(
        id: 'at-next-day',
        projectId: 'project-1',
        capturedAt: DateTime(2026, 7, 17),
      ),
      _summary(
        id: 'at-next-month',
        projectId: 'project-1',
        capturedAt: DateTime(2026, 8),
      ),
      _summary(
        id: 'at-next-year',
        projectId: 'project-1',
        capturedAt: DateTime(2027),
      ),
    ];
    final originalOrder = summaries
        .map((summary) => summary.capture.id)
        .toList();

    expect(
      filterCaptureSummaries(
        summaries,
        const CaptureFilter(projectId: 'project-1', year: 2026),
      ).map((summary) => summary.capture.id),
      ['before-day', 'in-day', 'at-next-day', 'at-next-month'],
    );
    expect(
      filterCaptureSummaries(
        summaries,
        const CaptureFilter(projectId: 'project-1', year: 2026, month: 7),
      ).map((summary) => summary.capture.id),
      ['before-day', 'in-day', 'at-next-day'],
    );
    expect(
      filterCaptureSummaries(
        summaries,
        const CaptureFilter(
          projectId: 'project-1',
          year: 2026,
          month: 7,
          day: 16,
        ),
      ).map((summary) => summary.capture.id),
      ['in-day'],
    );
    expect(summaries.map((summary) => summary.capture.id), originalOrder);
  });
}
