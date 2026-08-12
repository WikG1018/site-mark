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
  });

  final Future<void> Function() recoverCamera;
  final Future<void> Function() resolveLocations;
  final Future<void> Function() reconcileQueue;
  final Future<void> Function() cleanupInterruptedExports;
  final Future<void> Function() cleanupInterruptedImports;
  final Future<void> Function() cleanupInterruptedBundleRestores;
  final Future<void> Function() cleanupInterruptedProjectDeletions;
  final Future<void> Function() cleanupInterruptedCaptureMedia;

  Future<void> run() async {
    await _bestEffort(cleanupInterruptedExports);
    // Remove half-imported projects first so they never surface in the UI
    // or confuse the other recovery steps.
    await _bestEffort(cleanupInterruptedImports);
    await _bestEffort(cleanupInterruptedBundleRestores);
    await _bestEffort(cleanupInterruptedProjectDeletions);
    await _bestEffort(cleanupInterruptedCaptureMedia);

    // Core recovery stages are best-effort for the same reason as cleanup:
    // camera/plugin, SQLite, location and WorkManager failures are independent.
    // A transient failure in one subsystem must not skip later recovery work or
    // escape into the root post-frame callback.
    await _bestEffort(recoverCamera);
    await _bestEffort(resolveLocations);
    await _bestEffort(reconcileQueue);
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
