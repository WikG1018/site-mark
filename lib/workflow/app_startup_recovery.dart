class AppStartupRecovery {
  const AppStartupRecovery({
    required this.recoverCamera,
    required this.resolveLocations,
    required this.reconcileQueue,
    required this.cleanupInterruptedExports,
    required this.cleanupInterruptedImports,
    required this.cleanupInterruptedBundleRestores,
    required this.cleanupInterruptedProjectDeletions,
    required this.cleanupInterruptedCaptureMedia,
    required this.recoverPublishJournals,
  });

  final Future<void> Function() recoverCamera;
  final Future<void> Function() resolveLocations;
  final Future<void> Function() reconcileQueue;
  final Future<void> Function() cleanupInterruptedExports;
  final Future<void> Function() cleanupInterruptedImports;
  final Future<void> Function() cleanupInterruptedBundleRestores;
  final Future<void> Function() cleanupInterruptedProjectDeletions;
  final Future<void> Function() cleanupInterruptedCaptureMedia;
  final Future<void> Function() recoverPublishJournals;

  Future<void> run() async {
    await _bestEffort(cleanupInterruptedExports);
    // Remove half-imported projects first so they never surface in the UI
    // or confuse the other recovery steps.
    await _bestEffort(cleanupInterruptedImports);
    await _bestEffort(cleanupInterruptedBundleRestores);
    await _bestEffort(cleanupInterruptedProjectDeletions);

    // Kill-process windows must start together. Camera recovery can hang on a
    // dead plugin host; the queue, album cleanup, and publish-journal windows
    // still have to re-enter. Each callback is isolated so one error cannot
    // skip a sibling window.
    await Future.wait([
      _bestEffort(cleanupInterruptedCaptureMedia),
      _bestEffort(recoverPublishJournals),
      _bestEffort(recoverCamera),
      _bestEffort(resolveLocations),
      _bestEffort(reconcileQueue),
    ]);
  }

  Future<void> _bestEffort(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      // Durable work is retried on the next launch. Keep startup moving so an
      // unrelated subsystem can still recover in the current session.
    }
  }
}
