import 'dart:convert';

/// Sanitizes a project name for use in file names.
///
/// Forbidden characters (matching the Android/Rust blacklist contract):
/// whitespace, control chars (C0 + DEL + C1), `~`, and `/ \ : * ? " < > |`.
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

/// Fallback project-name component used by [formatPhotoNumber].
const fallbackProjectName = 'Project';

/// Formats a short, filesystem-safe photo number.
///
/// Format: `{safeProjectName}-SM-{yyyyMMdd}-{seq}`. The caller allocates the
/// sequence globally for the local day, so a project UUID is not needed in
/// the user-visible number or JPEG name.
String formatPhotoNumber({
  required String projectName,
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
  final suffix = '-SM-$date-$seq.jpg';
  final suffixBytes = utf8.encode(suffix).length;
  final safe = safePhotoProjectName(projectName, suffixReserve: suffixBytes);
  final number = '$safe-SM-$date-$seq';
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
