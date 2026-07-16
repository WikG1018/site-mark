enum CaptureStatus {
  pendingCamera,
  captured,
  rendering,
  ready,
  failed;

  Set<CaptureStatus> get allowedNext => switch (this) {
    CaptureStatus.pendingCamera => {
      CaptureStatus.captured,
      CaptureStatus.failed,
    },
    CaptureStatus.captured => {CaptureStatus.rendering, CaptureStatus.failed},
    CaptureStatus.rendering => {CaptureStatus.ready, CaptureStatus.failed},
    CaptureStatus.failed => {CaptureStatus.captured, CaptureStatus.rendering},
    CaptureStatus.ready => const {},
  };

  bool canTransitionTo(CaptureStatus next) => allowedNext.contains(next);
}
