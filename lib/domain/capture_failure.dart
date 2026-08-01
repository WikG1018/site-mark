enum CaptureFailureCode {
  cameraUnavailable('camera_unavailable'),
  queueUnavailable('queue_unavailable'),
  originalMissing('original_missing'),
  originalModified('original_modified'),
  processingFailed('processing_failed'),
  unexpected('unexpected');

  const CaptureFailureCode(this.storageCode);

  final String storageCode;

  static CaptureFailureCode fromStorage(String? value) {
    for (final code in values) {
      if (code.storageCode == value) return code;
    }
    return CaptureFailureCode.unexpected;
  }
}
