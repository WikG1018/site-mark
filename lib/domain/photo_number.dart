import 'dart:convert';

/// Sanitizes a project name for use in file names.
///
/// Forbidden characters (matching the Android/Rust blacklist contract):
/// whitespace, control chars (C0 + DEL + C1), `~` (reserved as the dedicated
/// field separator in [formatPhotoNumber]), and `/ \ : * ? " < > |`.
/// Repeated forbidden runs collapse to a single `_`. The result is trimmed
/// of leading/trailing dots, underscores, and spaces, then truncated to fit
/// the UTF-8 byte budget so the final JPEG name never exceeds 255 bytes.
String safePhotoProjectName(
  String projectName, {
  int maxJpegNameBytes = 255,
  int suffixReserve = 24,
}) {
  var safe = projectName.trim().replaceAll(
    RegExp(r'[\s~ /\\:*?"<>|\x00-\x1F\x7F\x80-\x9F]+'),
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

/// Fallback project-name component used by [formatPhotoNumber] when the
/// sanitized project name is empty. Exported so the suffix-length guard can
/// account for it.
const fallbackProjectName = 'Project';

/// Formats a unique photo number for filesystem use.
///
/// Format: `{safeProjectName}~{projectId}-SM-{yyyyMMdd}-{seq}`
///
/// The `~` character is a **dedicated field separator**. It is added to the
/// `safePhotoProjectName` blacklist so it can never appear in the sanitized
/// project name, and it is excluded from the `projectId` ASCII whitelist
/// (`^[A-Za-z0-9_-]+$`). This makes `~` an unambiguous boundary between the
/// two fields, preventing cross-field collisions such as
/// `(A, B-C)` vs `(A-B, C)` from producing the same photo number.
///
/// `projectId` is embedded verbatim — hyphens are preserved — so the
/// mapping from project ID to photo number is strictly one-to-one. Two
/// distinct project IDs always produce distinct file names, even when the
/// project display names are identical or sanitize to the same value.
///
/// [projectId] must be a non-empty ASCII identifier matching
/// `^[A-Za-z0-9_-]+$`. This matches the Rust `safe_archive_component`
/// contract and prevents `/`, whitespace, `~`, or non-ASCII characters from
/// being embedded in the file name.
///
/// The byte budget for the project name is computed from the actual UTF-8
/// byte length of the suffix (not `String.length`, which is UTF-16 code
/// units). If the suffix alone is so long that even the
/// [fallbackProjectName] would not fit within 255 bytes, an
/// [ArgumentError] is thrown — the final JPEG name is guaranteed never to
/// exceed 255 UTF-8 bytes.
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
  // Use the projectId verbatim. Hyphens are already allowed by both the
  // Dart and Rust whitelists, and preserving them keeps the project-ID to
  // file-name mapping strictly one-to-one (e.g. "project-1" and "project1"
  // stay distinct).
  final projectKey = projectId;
  // Use ~ as the field separator. It is blacklisted in safePhotoProjectName
  // and excluded from the projectId whitelist, so it cannot appear in either
  // field — making it an unambiguous boundary.
  final suffix = '~$projectKey-SM-$date-$seq.jpg';
  final suffixBytes = utf8.encode(suffix).length;
  final fallbackBytes = utf8.encode(fallbackProjectName).length;
  if (suffixBytes + fallbackBytes > 255) {
    throw ArgumentError.value(
      projectId,
      'projectId',
      'Project ID is too long for a valid JPEG file name (suffix would '
          'leave no room for the project name within 255 UTF-8 bytes)',
    );
  }
  final safe = safePhotoProjectName(projectName, suffixReserve: suffixBytes);
  final number = '$safe~$projectKey-SM-$date-$seq';
  // Defensive final check: never emit a number whose .jpg name would
  // exceed the POSIX NAME_MAX of 255 bytes.
  if (utf8.encode('$number.jpg').length > 255) {
    throw StateError(
      'Generated JPEG name exceeds 255 UTF-8 bytes '
      '(got ${utf8.encode('$number.jpg').length})',
    );
  }
  return number;
}
