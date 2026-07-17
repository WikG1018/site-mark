String safePhotoProjectName(String projectName) {
  var safe = projectName.trim().replaceAll(
    RegExp(r'[\s/\\:*?"<>|\x00-\x1F\x7F\x80-\x9F]+'),
    '_',
  );
  safe = safe.replaceAll(RegExp(r'_+'), '_');
  safe = String.fromCharCodes(safe.runes.take(60));
  safe = safe.replaceAll(RegExp(r'^[._ ]+|[._ ]+$'), '');
  return safe.isEmpty ? 'Project' : safe;
}

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
  return '${safePhotoProjectName(projectName)}-SM-$date-'
      '${sequence.toString().padLeft(3, '0')}';
}
