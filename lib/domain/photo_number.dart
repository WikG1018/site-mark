import 'dart:convert';

/// Sanitizes a project name for use in file names.
///
/// Forbidden characters (matching the Android/Rust blacklist contract):
/// whitespace, control chars (C0 + DEL + C1), and `/ \ : * ? " < > |`.
/// Repeated forbidden runs collapse to a single `_`. The result is trimmed
/// of leading/trailing dots, underscores, and spaces, then truncated to fit
/// the UTF-8 byte budget so the final JPEG name never exceeds 255 bytes.
String safePhotoProjectName(
  String projectName, {
  int maxJpegNameBytes = 255,
  int suffixReserve = 24,
}) {
  var safe = projectName.trim().replaceAll(
    RegExp(r'[\s/\\:*?"<>|\x00-\x1F\x7F\x80-\x9F]+'),
    '_',
  );
  safe = safe.replaceAll(RegExp(r'_+'), '_');
  // Truncate by code points first as a coarse upper bound, then refine by
  // the UTF-8 byte budget below.
  final byteBudget = maxJpegNameBytes - suffixReserve;
  if (byteBudget < 1) {
    // If the reserve is somehow too large, fall back to a small budget.
    return _trimToUtf8Bytes(safe, 1);
  }
  safe = _trimToUtf8Bytes(safe, byteBudget);
  safe = safe.replaceAll(RegExp(r'^[._ ]+|[._ ]+$'), '');
  return safe.isEmpty ? 'Project' : safe;
}

/// Trims [value] to at most [maxBytes] UTF-8 bytes without splitting a
/// multi-byte code point.
String _trimToUtf8Bytes(String value, int maxBytes) {
  final runes = value.runes.toList();
  var result = StringBuffer();
  var used = 0;
  for (final rune in runes) {
    final char = String.fromCharCodes([rune]);
    final charBytes = utf8.encode(char).length;
    if (used + charBytes > maxBytes) break;
    result.write(char);
    used += charBytes;
  }
  return result.toString();
}

/// Formats a unique photo number for filesystem use.
///
/// Format: `{safeProjectName}-{projectIdShort}-SM-{yyyyMMdd}-{seq}`
/// where `projectIdShort` is the first 8 characters of the project ID.
/// This ensures two projects with the same (or sanitized-to-same) name
/// produce different file names, preventing silent overwrites in the
/// Android MediaStore and ZIP export.
String formatPhotoNumber({
  required String projectName,
  required String projectId,
  required DateTime capturedAt,
  required int sequence,
}) {
  if (sequence < 1) {
    throw ArgumentError.value(sequence, 'sequence', 'Must be positive');
  }
  String two(int value) => value.toString().padLeft(2, '0');
  final date =
      '${capturedAt.year.toString().padLeft(4, '0')}'
      '${two(capturedAt.month)}${two(capturedAt.day)}';
  final seq = sequence.toString().padLeft(3, '0');
  // Suffix = "-{projectIdShort}-SM-{date}-{seq}.jpg"
  // Compute reserve dynamically from the actual suffix length.
  final projectIdShort = projectId.length >= 8
      ? projectId.substring(0, 8)
      : projectId;
  final suffix = '-$projectIdShort-SM-$date-$seq.jpg';
  final safe = safePhotoProjectName(projectName, suffixReserve: suffix.length);
  return '$safe-$projectIdShort-SM-$date-$seq';
}
