/// Builds the compact title used only in capture lists.
///
/// Full stored photo numbers remain available on the detail screen. Both the
/// legacy UUID-bearing format and the new short format end in the same daily
/// sequence, so the list can display a stable date and sequence for either.
String captureListDisplayName({
  required DateTime? capturedAt,
  required String? photoNumber,
  required String fallback,
}) {
  if (capturedAt == null || photoNumber == null) return fallback;
  final match = RegExp(r'-(\d+)(?:\.jpg)?$').firstMatch(photoNumber);
  if (match == null) return fallback;

  String two(int value) => value.toString().padLeft(2, '0');
  final date =
      '${capturedAt.year.toString().padLeft(4, '0')}-'
      '${two(capturedAt.month)}-${two(capturedAt.day)}';
  return '$date · ${match.group(1)}';
}
