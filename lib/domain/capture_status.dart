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
    // `failed` may be reset back to `captured` so the background processor can
    // retry after a user-initiated regeneration or a scheduler reconcile.
    CaptureStatus.failed => {CaptureStatus.captured},
    // `ready` may return to `captured` so an edited capture can be re-rendered
    // and re-published by the background queue.
    CaptureStatus.ready => {CaptureStatus.captured},
  };

  /// Whether this status may transition to [next].
  ///
  /// Self-transitions are always allowed so that a background worker re-running
  /// an idempotent step (e.g. `captured -> captured`) does not raise a
  /// `StateError` when the previous invocation already advanced the row.
  bool canTransitionTo(CaptureStatus next) =>
      next == this || allowedNext.contains(next);
}
