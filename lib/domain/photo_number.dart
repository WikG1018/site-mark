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
  final byteBudget = maxJpegNameBytes - suffixReserve;
  if (byteBudget < 1) {
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
/// Format: `{safeProjectName}-{projectKey}-SM-{yyyyMMdd}-{seq}`
/// where `projectKey` is the project ID with hyphens removed (so a 36-char
/// UUID becomes its 32-char hex form). Embedding the *full* project ID —
/// not a short prefix — guarantees that two distinct project IDs always
/// produce distinct file names, even when the project display names are
/// identical or sanitize to the same value. This prevents silent
/// overwrites in the Android MediaStore and ZIP export.
///
/// [projectId] must be a non-empty ASCII identifier matching
/// `^[A-Za-z0-9_-]+$`. This matches the Rust `safe_archive_component`
/// contract and prevents `/`, whitespace, or non-ASCII characters from
/// being embedded in the file name. The byte budget for the project name
/// is computed from the actual UTF-8 byte length of the suffix so the
/// final JPEG name never exceeds 255 bytes.
String formatPhotoNumber({
  required String projectName,
  required String projectId,
  required DateTime capturedAt,
  required int sequence,
}) {
  if (sequence < 1) {
    throw ArgumentError.value(sequence, 'sequence', 'Must be positive');
  }
  if (projectId.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(projectId)) {
    throw ArgumentError.value(
      projectId,
      'projectId',
      'Expected a non-empty ASCII identifier (A-Z, a-z, 0-9, _, -)',
    );
  }
  String two(int value) => value.toString().padLeft(2, '0');
  final date =
      '${capturedAt.year.toString().padLeft(4, '0')}'
      '${two(capturedAt.month)}${two(capturedAt.day)}';
  final seq = sequence.toString().padLeft(3, '0');
  // Strip hyphens so a 36-char UUID collapses to its 32-char hex form.
  // Two distinct UUIDs always differ in at least one hex digit, so the
  // resulting photo numbers are deterministically distinct.
  final projectKey = projectId.replaceAll('-', '');
  final suffix = '-$projectKey-SM-$date-$seq.jpg';
  // Use UTF-8 byte length, not String.length (UTF-16 code units), so the
  // budget stays correct even if a non-ASCII projectId is ever supplied.
  final suffixBytes = utf8.encode(suffix).length;
  final safe = safePhotoProjectName(projectName, suffixReserve: suffixBytes);
  return '$safe-$projectKey-SM-$date-$seq';
}
