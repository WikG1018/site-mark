/// User-facing filter for the capture summary list.
///
/// The date components follow a parent-child invariant: selecting a [month]
/// requires a [year], and selecting a [day] requires a [month]. The
/// [localRange] getter expresses the selected date as a half-open
/// `(start, end)` tuple that summary queries apply as
/// `start <= coalesce(capturedAt, createdAt) < end`.
class CaptureFilter {
  const CaptureFilter({this.projectId, this.year, this.month, this.day})
    : assert(month == null || year != null),
      assert(day == null || month != null);

  final String? projectId;
  final int? year;
  final int? month;
  final int? day;

  /// Half-open local date range `(start, end)` or `null` when no [year] is
  /// selected. `start` is inclusive and `end` is exclusive.
  CaptureDateRange? get localRange {
    if (year == null) return null;
    final start = DateTime(year!, month ?? 1, day ?? 1);
    final end = day != null
        ? DateTime(year!, month!, day! + 1)
        : month != null
        ? DateTime(year!, month! + 1)
        : DateTime(year! + 1);
    return (start: start, end: end);
  }

  CaptureFilter selectProject(String? value) =>
      CaptureFilter(projectId: value, year: year, month: month, day: day);

  CaptureFilter selectYear(int? value) =>
      CaptureFilter(projectId: projectId, year: value);

  CaptureFilter selectMonth(int? value) =>
      CaptureFilter(projectId: projectId, year: year, month: value);

  CaptureFilter selectDay(int? value) =>
      CaptureFilter(projectId: projectId, year: year, month: month, day: value);
}

typedef CaptureDateRange = ({DateTime start, DateTime end});
