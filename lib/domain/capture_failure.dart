enum CaptureFailureCode {
  cameraUnavailable('camera_unavailable'),
  queueUnavailable('queue_unavailable'),
  originalMissing('original_missing'),
  originalModified('original_modified'),
  processingFailed('processing_failed'),
  unexpected('unexpected');

  const CaptureFailureCode(this.storageCode);

  final String storageCode;

  bool get canRetryProcessing => switch (this) {
    CaptureFailureCode.processingFailed ||
    CaptureFailureCode.unexpected => true,
    CaptureFailureCode.cameraUnavailable ||
    CaptureFailureCode.queueUnavailable ||
    CaptureFailureCode.originalMissing ||
    CaptureFailureCode.originalModified => false,
  };

  static CaptureFailureCode fromStorage(String? value) {
    for (final code in values) {
      if (code.storageCode == value) return code;
    }
    return CaptureFailureCode.unexpected;
  }
}
