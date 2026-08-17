class CaptureTargetPolicy {
  static final RegExp _safeCaptureId = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$',
  );

  static String fileName(String captureId) {
    if (!_safeCaptureId.hasMatch(captureId)) {
      throw ArgumentError.value(captureId, 'captureId', 'Invalid capture id');
    }
    return '$captureId.jpg';
  }

  static bool isCaptured({required bool exists, required int length}) {
    return exists && length > 0;
  }
}
