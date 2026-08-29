/// Per-row failure reason for a batched media operation
/// (CaptureActionResult.failures).
///
/// Kept as an enum rather than a message string: user-visible wording is
/// owned by the UI via `AppStrings.captureMediaFailure`, so raw exceptions
/// and private file paths can never reach the user. This is distinct from
/// CaptureFailureCode, which classifies persisted capture records.
enum CaptureMediaFailure {
  /// The capture row no longer exists in the database.
  recordMissing,

  /// clearOriginals was called on a row that is not ready or failed.
  clearStatusNotAllowed,

  /// deleteAll was called on a row that is not ready or failed.
  deleteStatusNotAllowed,

  /// republish was called on a row that is not ready.
  republishStatusNotAllowed,

  /// The capture's project is completed or archived (read-only), so
  /// destructive batch operations must not touch it.
  projectReadOnly,

  /// The retained original file was not found on disk.
  originalMissing,

  /// The rendered watermarked file was not found on disk.
  renderedPhotoMissing,

  /// An unexpected error aborted the operation before it committed.
  operationFailed,
}
