class AppStartupRecovery {
  const AppStartupRecovery({
    required this.recoverCamera,
    required this.resolveLocations,
    required this.reconcileQueue,
    required this.cleanupInterruptedImports,
    required this.cleanupInterruptedBundleRestores,
    required this.cleanupInterruptedProjectDeletions,
  });

  final Future<void> Function() recoverCamera;
  final Future<void> Function() resolveLocations;
  final Future<void> Function() reconcileQueue;
  final Future<void> Function() cleanupInterruptedImports;
  final Future<void> Function() cleanupInterruptedBundleRestores;
  final Future<void> Function() cleanupInterruptedProjectDeletions;

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
    try {
      await cleanupInterruptedBundleRestores();
    } catch (_) {
      // Bundle restore cleanup is retried from its durable marker on the next
      // launch. It must not block project deletion or core capture recovery.
    }
    try {
      await cleanupInterruptedProjectDeletions();
    } catch (_) {
      // Project deletion cleanup is retried from its durable marker on the
      // next launch. A storage-side error must not block capture recovery.
    }
    await recoverCamera();
    await resolveLocations();
    await reconcileQueue();
  }
}
