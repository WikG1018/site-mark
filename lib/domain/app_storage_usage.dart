class AppStorageUsage {
  const AppStorageUsage({
    required this.originalBytes,
    required this.renderedBytes,
    required this.exportBytes,
    required this.databaseAndOtherBytes,
  });

  final int originalBytes;
  final int renderedBytes;
  final int exportBytes;
  final int databaseAndOtherBytes;

  int get totalBytes =>
      originalBytes + renderedBytes + exportBytes + databaseAndOtherBytes;
}

class ClearExportsResult {
  const ClearExportsResult({
    required this.deletedFiles,
    required this.freedBytes,
  });

  final int deletedFiles;
  final int freedBytes;
}

String formatStorageBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final whole = value == value.roundToDouble();
  final digits = whole || value >= 10 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}
