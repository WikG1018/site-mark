class AppStartupRecovery {
  const AppStartupRecovery({
    required this.recoverCamera,
    required this.resolveLocations,
    required this.reconcileQueue,
    required this.cleanupInterruptedImports,
  });

  final Future<void> Function() recoverCamera;
  final Future<void> Function() resolveLocations;
  final Future<void> Function() reconcileQueue;
  final Future<void> Function() cleanupInterruptedImports;

  Future<void> run() async {
    // Remove half-imported projects first so they never surface in the UI
    // or confuse the other recovery steps.
    try {
      await cleanupInterruptedImports();
    } catch (_) {
      // Import cleanup is retried from its durable marker on the next launch.
      // A storage-side cleanup error must not block camera, location, or
      // background-queue recovery for otherwise healthy captures.
    }
    await recoverCamera();
    await resolveLocations();
    await reconcileQueue();
  }
}
